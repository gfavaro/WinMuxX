import Darwin
import Foundation
import ObjectiveC

// Adds a user desktop to a display with SkyLight's synchronous bridged
// window-management operation, the counterpart of `NativeWindowSpaceMover`. It
// works with SIP enabled through the same kind of unexported dispatcher and private
// class; either can disappear in a macOS update, and creation then reports itself
// unavailable. It never removes a desktop or moves a window. Callers confirm the new
// desktop from a fresh topology read.
//
// Adapted from Dinky (MIT, Copyright (c) 2026 Mikkel Malmberg),
// Sources/DinkyPrivate/spaces.m.
public enum NativeSpaceCreator {
    private typealias Perform = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias Alloc = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
    private typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, UInt32, NSDictionary) -> UnsafeMutableRawPointer?
    private typealias SpaceID = @convention(c) (UnsafeMutableRawPointer, Selector) -> UInt64

    private static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    private static let dispatcherSymbol =
        "__ZL54_SLSPerformSynchronousBridgedWindowManagementOperationP46SLSSynchronousBridgedWindowManagementOperation"
    private static let operationClass = "SLSBridgedSpaceCreateOperation"
    private static let initSelector = NSSelectorFromString("initWithOptions:values:")
    private static let spaceIDSelector = NSSelectorFromString("spaceID")

    private struct Resolved: @unchecked Sendable {
        let perform: Perform
        let cls: AnyClass
        let alloc: Alloc
        let initialize: Initialize
    }

    /// Resolved once per process; nil when this macOS lacks either private piece.
    private static let resolved: Resolved? = {
        _ = dlopen(skyLight, RTLD_LAZY | RTLD_LOCAL)
        guard let address = NativeWindowSpaceMover.symbol(dispatcherSymbol, in: skyLight),
              let cls = objc_getClass(operationClass) as? AnyClass,
              let allocMethod = class_getClassMethod(cls, NSSelectorFromString("alloc")),
              class_respondsToSelector(cls, initSelector),
              let initMethod = class_getInstanceMethod(cls, initSelector) else { return nil }
        return Resolved(perform: unsafeBitCast(address, to: Perform.self), cls: cls,
            alloc: unsafeBitCast(method_getImplementation(allocMethod), to: Alloc.self),
            initialize: unsafeBitCast(method_getImplementation(initMethod), to: Initialize.self))
    }()

    public static var isAvailable: Bool { resolved != nil }

    /// Appends a user desktop to the display's strip. Returns the new Space ID, or nil
    /// when the operation could not run or returned no Space.
    @MainActor
    public static func create(onDisplay displayIdentifier: String) -> UInt64? {
        guard let resolved, !displayIdentifier.isEmpty else { return nil }
        return autoreleasepool {
            // A user Space (type 0) on the given display, the keys Dinky passes.
            let values: NSDictionary = ["type": 0, "Display Identifier": displayIdentifier]
            guard let allocated = resolved.alloc(resolved.cls, NSSelectorFromString("alloc")),
                  let operation = resolved.initialize(allocated, initSelector, 0, values) else { return nil }
            defer { Unmanaged<AnyObject>.fromOpaque(operation).release() } // alloc/init returned it retained
            // The result is not owned by the caller.
            guard let result = resolved.perform(operation) else { return nil }
            let object = Unmanaged<AnyObject>.fromOpaque(result).takeUnretainedValue()
            guard let resultClass = object_getClass(object), class_respondsToSelector(resultClass, spaceIDSelector),
                  let method = class_getInstanceMethod(resultClass, spaceIDSelector) else { return nil }
            let spaceID = unsafeBitCast(method_getImplementation(method), to: SpaceID.self)(result, spaceIDSelector)
            return spaceID == 0 ? nil : spaceID
        }
    }
}
