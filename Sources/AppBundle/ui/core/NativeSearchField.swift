import AppKit

final class NativeSearchField: NSSearchField {
    var onAttach: (@MainActor () -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onAttach?()
    }
}
