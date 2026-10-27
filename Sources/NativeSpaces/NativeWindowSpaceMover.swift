import Darwin
import Foundation
import MachO
import ObjectiveC

// Moves windows between native Spaces with SkyLight's bridged window-management
// operation, the one write this module performs on Space membership. It works with
// SIP enabled but needs a dispatcher SkyLight does not export, found by scanning
// SkyLight's symbol table, plus a private Objective-C class. Either can disappear in
// a macOS update; the mover then reports itself unavailable instead of guessing.
// Only explicit commands and user-configured rules call it, and callers confirm the
// move from a fresh membership read.
//
// Adapted from Dinky (MIT, Copyright (c) 2026 Mikkel Malmberg),
// Sources/DinkyPrivate/move.m and skylight.m.
public enum NativeWindowSpaceMover {
    private typealias Perform = @convention(c) (UnsafeMutableRawPointer) -> Int64
    private typealias Alloc = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
    private typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, NSArray, UInt64) -> UnsafeMutableRawPointer?

    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    private static let dispatcherSymbol =
        "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation"
    private static let operationClass = "SLSBridgedMoveWindowsToManagedSpaceOperation"

    private struct Resolved: @unchecked Sendable {
        let perform: Perform
        let cls: AnyClass
        let alloc: Alloc
        let initialize: Initialize
    }

    /// Resolved once per process; nil when this macOS lacks either private piece.
    private static let resolved: Resolved? = {
        _ = dlopen(skyLight, RTLD_LAZY | RTLD_LOCAL)
        let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
        guard let address = symbol(dispatcherSymbol, in: skyLight),
              let cls = objc_getClass(operationClass) as? AnyClass,
              let allocMethod = class_getClassMethod(cls, NSSelectorFromString("alloc")),
              class_respondsToSelector(cls, initSelector),
              let initMethod = class_getInstanceMethod(cls, initSelector) else { return nil }
        return Resolved(perform: unsafeBitCast(address, to: Perform.self), cls: cls,
            alloc: unsafeBitCast(method_getImplementation(allocMethod), to: Alloc.self),
            initialize: unsafeBitCast(method_getImplementation(initMethod), to: Initialize.self))
    }()

    public static var isAvailable: Bool { resolved != nil }

    /// Starts an asynchronous move of the windows to the Space. True only means the
    /// operation was dispatched; confirm membership before relying on it.
    @MainActor
    public static func move(windowIDs: [UInt32], toSpaceID spaceID: UInt64) -> Bool {
        guard let resolved, !windowIDs.isEmpty, spaceID != 0 else { return false }
        let windows = windowIDs.map { NSNumber(value: Int32(bitPattern: $0)) } as NSArray
        let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
        guard let allocated = resolved.alloc(resolved.cls, NSSelectorFromString("alloc")),
              let operation = resolved.initialize(allocated, initSelector, windows, spaceID) else { return false }
        _ = resolved.perform(operation)
        Unmanaged<AnyObject>.fromOpaque(operation).release() // alloc/init returned it retained
        return true
    }

    /// The address of a symbol in a loaded image's symbol table, exported or not.
    static func symbol(_ name: String, in imagePath: String) -> UnsafeMutableRawPointer? {
        for index in 0..<_dyld_image_count() where String(cString: _dyld_get_image_name(index)) == imagePath {
            guard let header = _dyld_get_image_header(index) else { return nil }
            let slide = _dyld_get_image_vmaddr_slide(index)
            var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
            var linkedit: segment_command_64?
            var symtab: symtab_command?
            for _ in 0..<header.pointee.ncmds {
                let command = cursor.load(as: load_command.self)
                if command.cmd == LC_SEGMENT_64 {
                    let segment = cursor.load(as: segment_command_64.self)
                    let name = withUnsafeBytes(of: segment.segname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                    if name == SEG_LINKEDIT { linkedit = segment }
                } else if command.cmd == LC_SYMTAB {
                    symtab = cursor.load(as: symtab_command.self)
                }
                cursor = cursor.advanced(by: Int(command.cmdsize))
            }
            guard let linkedit, let symtab,
                  let base = UnsafeRawPointer(bitPattern: Int(linkedit.vmaddr) - Int(linkedit.fileoff) + slide) else { return nil }
            let strings = base.advanced(by: Int(symtab.stroff)).assumingMemoryBound(to: CChar.self)
            let symbols = base.advanced(by: Int(symtab.symoff)).assumingMemoryBound(to: nlist_64.self)
            for entry in UnsafeBufferPointer(start: symbols, count: Int(symtab.nsyms))
                where strcmp(strings.advanced(by: Int(entry.n_un.n_strx)), name) == 0 {
                return UnsafeMutableRawPointer(bitPattern: Int(entry.n_value) + slide)
            }
            return nil
        }
        return nil
    }
}
