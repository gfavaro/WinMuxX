import AppKit
import SwiftUI

enum PaletteSearchCommand: Equatable {
    case previous, next, activate, dismiss
}

/// Native editing (including composition, selection and paste) stays with AppKit.
struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    let onCommand: @MainActor (PaletteSearchCommand) -> Void

    func makeNSView(context: Context) -> NativeSearchField {
        let field = NativeSearchField()
        field.placeholderString = "Search windows…"
        field.setAccessibilityLabel("Search windows")
        field.setAccessibilityHelp("Up and down select a result. Return opens it. Escape closes the palette.")
        field.font = .systemFont(ofSize: 15)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.recentsAutosaveName = nil
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.onAttach = { [weak field, weak coordinator = context.coordinator] in
            if let field { coordinator?.scheduleFocus(field) }
        }
        return field
    }

    func updateNSView(_ field: NativeSearchField, context: Context) {
        context.coordinator.parent = self
        let appearance: NSAppearance.Name = context.environment.colorScheme == .dark ? .darkAqua : .aqua
        if field.appearance?.name != appearance { field.appearance = NSAppearance(named: appearance) }
        if !overlayHasMarkedText(field.currentEditor()), field.stringValue != text { field.stringValue = text }
        context.coordinator.scheduleFocus(field)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleNSView(_ field: NativeSearchField, coordinator: Coordinator) {
        coordinator.isAttached = false
        field.onAttach = nil
        field.delegate = nil
        field.target = nil
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: PaletteSearchField
        var isAttached = true
        private var didFocus = false
        private var focusScheduled = false

        init(parent: PaletteSearchField) { self.parent = parent }

        func scheduleFocus(_ field: NSSearchField) {
            guard !didFocus, !focusScheduled, isAttached else { return }
            focusScheduled = true
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self else { return }
                self.focusScheduled = false
                guard self.isAttached, !self.didFocus, let field,
                      let window = field.window, window.isVisible else { return }
                self.didFocus = window.makeFirstResponder(field)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            searchChanged(field)
        }

        @objc func searchChanged(_ field: NSSearchField) {
            guard isAttached, !overlayHasMarkedText(field.currentEditor()) else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard isAttached, !textView.hasMarkedText() else { return false }
            let command: PaletteSearchCommand
            switch selector {
            case #selector(NSResponder.moveUp(_:)): command = .previous
            case #selector(NSResponder.moveDown(_:)): command = .next
            case #selector(NSResponder.insertNewline(_:)): command = .activate
            case #selector(NSResponder.cancelOperation(_:)): command = .dismiss
            default: return false
            }
            parent.text = textView.string
            parent.onCommand(command)
            return true
        }
    }
}
