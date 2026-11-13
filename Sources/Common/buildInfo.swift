import MachO

// script/fork-build.sh links the version and commit into this section with `ld -sectcreate`, so
// building never rewrites a tracked source file. Debug builds have no section.
private let buildInfo: [String] = {
    var size: UInt = 0
    guard let data = getsectiondata(#dsohandle.assumingMemoryBound(to: mach_header_64.self), "__TEXT", "__winmux_build", &size)
    else { return [] }
    return String(decoding: UnsafeBufferPointer(start: data, count: Int(size)), as: UTF8.self)
        .split(separator: "\n").map(String.init)
}()

public let winMuxAppVersion = buildInfo.getOrNil(atIndex: 0) ?? "0.0.0-SNAPSHOT"
public let gitHash = buildInfo.getOrNil(atIndex: 1) ?? "SNAPSHOT"
public let gitShortHash = buildInfo.getOrNil(atIndex: 2) ?? "SNAPSHOT"
