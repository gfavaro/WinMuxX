import AppKit
import os

/// Captures errors that optional AX getters/setters deliberately hide. Scoped to
/// one window operation, so a dead element can be replaced without polling first.
final class AXWindowOperation: Sendable {
    @TaskLocal static var current: AXWindowOperation?
    private let invalid = OSAllocatedUnfairLock(initialState: false)

    func record(_ error: AXError) {
        if error == .invalidUIElement { invalid.withLock { $0 = true } }
    }

    var needsReplacement: Bool { invalid.withLock { $0 } }
}

func withRecoverableWindow<Element, Value>(
    load: (_ replacing: Bool) throws -> Element?,
    body: (Element) throws -> Value?
) throws -> Value? {
    for attempt in 0...1 {
        guard let element = try load(attempt != 0) else { return nil }
        let operation = AXWindowOperation()
        let value: Value?
        do { value = try AXWindowOperation.$current.withValue(operation) { try body(element) } }
        catch let failure as AXReadFailure where failure.code == .invalidUIElement {
            operation.record(failure.code)
            value = nil
        }
        if operation.needsReplacement {
            if attempt == 0 { continue }
            throw AXReadFailure(code: .invalidUIElement)
        }
        return value
    }
    return nil
}
