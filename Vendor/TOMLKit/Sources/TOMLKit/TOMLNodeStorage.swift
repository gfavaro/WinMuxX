// Local ownership patch; see ../../README.md and LICENSE.
import CTOML
#if canImport(Darwin)
import Darwin.C
#else
import Glibc
#endif

/// Owns one native root. Nested views share this owner without copying subtrees.
/// Replacing/removing a node invalidates views of that node; retaining a view
/// keeps its document alive but does not make concurrent mutation safe.
final class TOMLNodeStorage {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { nodeDelete(pointer) }
}

func takeTOMLString(_ pointer: UnsafePointer<CChar>) -> String {
    defer { free(UnsafeMutablePointer(mutating: pointer)) }
    return String(cString: pointer)
}
