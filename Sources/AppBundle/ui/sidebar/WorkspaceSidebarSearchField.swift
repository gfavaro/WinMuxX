import AppKit
import SwiftUI

final class WorkspaceSidebarNativeSearchField: NSSearchField {
    var onAttach: (@MainActor () -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onAttach?()
    }
}

struct WorkspaceSidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    let requestsFocus: Bool
    let onEditorReady: @MainActor (WorkspaceSidebarPanel) -> Void
    let onCommand: @MainActor (WorkspaceSidebarInlineTextKey) -> Void

    func makeNSView(context: Context) -> WorkspaceSidebarNativeSearchField {
        let field = WorkspaceSidebarNativeSearchField()
        field.placeholderString = "Search windows…"
        field.setAccessibilityLabel("Search windows")
        field.controlSize = .small
        field.font = .systemFont(ofSize: 12)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.recentsAutosaveName = nil
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.onAttach = { [weak field, weak coordinator = context.coordinator] in
            guard let field, let coordinator else { return }
            coordinator.scheduleFocus(field)
        }
        return field
    }

    func updateNSView(_ field: WorkspaceSidebarNativeSearchField, context: Context) {
        context.coordinator.parent = self
        field.appearance = NSAppearance(named: context.environment.workspaceSidebarAppearance == .custom || context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        if field.stringValue != text { field.stringValue = text }
        if !requestsFocus { context.coordinator.didFocus = false }
        context.coordinator.scheduleFocus(field)
    }

    static func dismantleNSView(_ field: WorkspaceSidebarNativeSearchField, coordinator: Coordinator) {
        field.onAttach = nil
        field.delegate = nil
        field.target = nil
        coordinator.isAttached = false
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: WorkspaceSidebarSearchField
        var didFocus = false
        var isAttached = true

        init(parent: WorkspaceSidebarSearchField) { self.parent = parent }

        func scheduleFocus(_ field: NSSearchField) {
            guard parent.requestsFocus, !didFocus else { return }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, self.isAttached,
                      self.parent.requestsFocus, !self.didFocus,
                      let panel = field.window as? WorkspaceSidebarPanel,
                      panel.inlineTextEditingActive else { return }
                panel.prepareForInlineTextEditing()
                if panel.makeFirstResponder(field) {
                    // Keep the buffered first keystroke and append at its end.
                    field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
                    self.didFocus = true
                    self.parent.onEditorReady(panel)
                }
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField,
                  let panel = field.window as? WorkspaceSidebarPanel else { return }
            didFocus = true
            parent.onEditorReady(panel)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        @objc func searchChanged(_ field: NSSearchField) {
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Composition and all editing commands belong to the native editor.
            guard !textView.hasMarkedText() else { return false }
            let command: WorkspaceSidebarInlineTextKey
            switch selector {
                case #selector(NSResponder.moveUp(_:)): command = .moveUp
                case #selector(NSResponder.moveDown(_:)): command = .moveDown
                case #selector(NSResponder.insertNewline(_:)): command = .commit
                case #selector(NSResponder.cancelOperation(_:)): command = .cancel
                default: return false
            }
            parent.text = textView.string
            parent.onCommand(command)
            return true
        }
    }
}
