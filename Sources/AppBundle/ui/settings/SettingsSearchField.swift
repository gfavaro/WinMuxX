import AppKit
import SwiftUI

/// The Settings sidebar search field. SwiftUI's `.searchable` field ignored ⌘F and never
/// reported Return on the supported macOS versions; this AppKit field handles both.
struct SettingsSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: @MainActor () -> Void

    func makeNSView(context: Context) -> SettingsSearchNSField {
        let field = SettingsSearchNSField()
        field.placeholderString = "Find settings"
        field.setAccessibilityLabel("Find settings")
        field.setAccessibilityHelp("Return opens the first result. Tab moves to the results.")
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.recentsAutosaveName = nil
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: SettingsSearchNSField, context: Context) {
        context.coordinator.parent = self
        if !overlayHasMarkedText(field.currentEditor()), field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleNSView(_ field: SettingsSearchNSField, coordinator: Coordinator) {
        field.delegate = nil
        field.target = nil
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SettingsSearchField

        init(parent: SettingsSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            searchChanged(field)
        }

        @objc func searchChanged(_ field: NSSearchField) {
            guard !overlayHasMarkedText(field.currentEditor()) else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() else { return false }
            parent.text = textView.string
            parent.onSubmit()
            return true
        }
    }
}

final class SettingsSearchNSField: NSSearchField {
    /// The window offers unhandled key equivalents to its views, so ⌘F reaches this field
    /// whenever its Settings window is key, without a menu item.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isSettingsFindShortcut(event.modifierFlags, event.charactersIgnoringModifiers), let window, event.window === window {
            return window.makeFirstResponder(self)
        }
        return super.performKeyEquivalent(with: event)
    }
}

func isSettingsFindShortcut(_ modifiers: NSEvent.ModifierFlags, _ characters: String?) -> Bool {
    modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command && characters?.lowercased() == "f"
}
