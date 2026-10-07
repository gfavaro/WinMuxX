import AppKit
import SwiftUI

final class WorkspaceSidebarProjectRenameNSTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        debugWorkspaceSidebarRenameLog("textField becomeFirstResponder result=\(result) windowKey=\(window?.isKeyWindow.description ?? "nil") firstResponder=\(String(describing: window?.firstResponder))")
        return result
    }

    override func resignFirstResponder() -> Bool {
        debugWorkspaceSidebarRenameLog("textField resignFirstResponder windowKey=\(window?.isKeyWindow.description ?? "nil") firstResponder=\(String(describing: window?.firstResponder))")
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        debugWorkspaceSidebarRenameLog("textField keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") stringBefore=\(stringValue)")
        super.keyDown(with: event)
    }
}

struct WorkspaceSidebarProjectRenameTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void
    let onPanelReady: @MainActor (WorkspaceSidebarPanel) -> Void

    func makeNSView(context: Context) -> NSTextField {
        debugWorkspaceSidebarRenameLog("makeNSView text=\(text)")
        let field = WorkspaceSidebarProjectRenameNSTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = context.environment.workspaceSidebarAppearance == .system ? .labelColor : .white
        field.appearance = NSAppearance(named: context.environment.workspaceSidebarAppearance == .custom || context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        field.font = .systemFont(ofSize: 12.5, weight: .medium)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.focus(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.textColor = context.environment.workspaceSidebarAppearance == .system ? .labelColor : .white
        field.appearance = NSAppearance(named: context.environment.workspaceSidebarAppearance == .custom || context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        debugWorkspaceSidebarRenameLog("updateNSView didFocus=\(context.coordinator.didFocus) text=\(text) field=\(field.stringValue) windowKey=\(field.window?.isKeyWindow.description ?? "nil") firstResponder=\(String(describing: field.window?.firstResponder))")
        if field.stringValue != text {
            field.stringValue = text
        }
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.focus(field)
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.isAttached = false
        field.delegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel, onPanelReady: onPanelReady)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onCommit: @MainActor @Sendable () -> Void
        let onCancel: @MainActor @Sendable () -> Void
        let onPanelReady: @MainActor (WorkspaceSidebarPanel) -> Void
        var isAttached = true
        var didFocus = false
        var focusAttempts = 0

        init(
            text: Binding<String>,
            onCommit: @escaping @MainActor @Sendable () -> Void,
            onCancel: @escaping @MainActor @Sendable () -> Void,
            onPanelReady: @escaping @MainActor (WorkspaceSidebarPanel) -> Void
        ) {
            _text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
            self.onPanelReady = onPanelReady
        }

        @MainActor
        func focus(_ field: NSTextField) {
            guard isAttached, !didFocus else { return }
            guard let window = field.window else {
                debugWorkspaceSidebarRenameLog("focus noWindow attempt=\(focusAttempts)")
                scheduleFocusRetry(field)
                return
            }
            let panel = (window as? WorkspaceSidebarPanel) ?? WorkspaceSidebarPanel.shared
            debugWorkspaceSidebarRenameLog("focus attempt=\(focusAttempts) before panelKey=\(panel.isKeyWindow) fieldWindowKey=\(window.isKeyWindow) firstResponder=\(String(describing: window.firstResponder))")
            panel.prepareForInlineTextEditing()
            onPanelReady(panel)
            window.makeKeyAndOrderFront(nil)
            let didBecomeFirstResponder = window.makeFirstResponder(field)
            field.selectText(nil)
            didFocus = didBecomeFirstResponder && window.isKeyWindow && window.firstResponder === field.currentEditor()
            debugWorkspaceSidebarRenameLog("focus result makeFirstResponder=\(didBecomeFirstResponder) didFocus=\(didFocus) windowKey=\(window.isKeyWindow) firstResponder=\(String(describing: window.firstResponder)) currentEditor=\(String(describing: field.currentEditor())) selectedRange=\(field.currentEditor()?.selectedRange ?? NSRange(location: -1, length: -1))")
            if !didFocus {
                scheduleFocusRetry(field)
            }
        }

        @MainActor
        private func scheduleFocusRetry(_ field: NSTextField) {
            guard focusAttempts < 8 else { return }
            focusAttempts += 1
            debugWorkspaceSidebarRenameLog("scheduleFocusRetry attempt=\(focusAttempts)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak field] in
                guard let self, let field else { return }
                self.focus(field)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
            debugWorkspaceSidebarRenameLog("controlTextDidChange text=\(text)")
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            debugWorkspaceSidebarRenameLog("control command=\(commandSelector) text=\(textView.string)")
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
                case #selector(NSResponder.insertNewline(_:)):
                    text = textView.string
                    onCommit()
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    onCancel()
                    return true
                default:
                    return false
            }
        }
    }
}

struct WorkspaceSidebarProjectRenameField: View {
    @SidebarColors var sidebarColors: WorkspaceSidebarPalette
    let project: WorkspaceSidebarProjectViewModel
    @Binding var text: String
    let onCommit: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void

    var body: some View {
        WorkspaceSidebarProjectRenameTextField(
            text: $text,
            onCommit: onCommit,
            onCancel: onCancel,
            onPanelReady: { panel in
                startInlineTextEditing(on: panel)
            },
        )
            .padding(.horizontal, 6)
            .frame(height: workspaceSidebarDropdownHeight)
            .background {
                RoundedRectangle(cornerRadius: workspaceSidebarPlateCornerRadius, style: .continuous)
                    .fill(sidebarColors.foreground.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarPlateCornerRadius, style: .continuous)
                    .strokeBorder(workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex).opacity(0.75), lineWidth: 0.8)
            }
            .onAppear {
                debugWorkspaceSidebarRenameLog("renameField onAppear project=\(project.id.rawValue) text=\(text)")
            }
            .onDisappear {
                debugWorkspaceSidebarRenameLog("renameField onDisappear project=\(project.id.rawValue) text=\(text)")
                WorkspaceSidebarPanel.activeInlineTextEditingPanel?.endInlineTextEditing()
            }
    }

    @MainActor
    private func startInlineTextEditing(on panel: WorkspaceSidebarPanel) {
        WorkspaceSidebarPanel.activeInlineTextEditingPanel?.endInlineTextEditing()
        panel.beginInlineTextEditing(onCancel: onCancel)
    }

}

struct WorkspaceSidebarWorkspaceRenameField: View {
    @SidebarColors var sidebarColors: WorkspaceSidebarPalette
    @Binding var text: String
    let workspaceName: String
    let onCommit: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void

    var body: some View {
        WorkspaceSidebarProjectRenameTextField(
            text: $text,
            onCommit: onCommit,
            onCancel: onCancel,
            onPanelReady: { panel in
                startInlineTextEditing(on: panel)
            },
        )
        .padding(.horizontal, 6)
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                .fill(sidebarColors.foreground.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                .strokeBorder(sidebarColors.foreground.opacity(0.62), lineWidth: 0.8)
        }
        .onAppear {
            debugWorkspaceSidebarRenameLog("workspaceRenameField onAppear workspace=\(workspaceName) text=\(text)")
        }
        .onDisappear {
            debugWorkspaceSidebarRenameLog("workspaceRenameField onDisappear workspace=\(workspaceName) text=\(text)")
            WorkspaceSidebarPanel.activeInlineTextEditingPanel?.endInlineTextEditing()
        }
    }

    @MainActor
    private func startInlineTextEditing(on panel: WorkspaceSidebarPanel) {
        WorkspaceSidebarPanel.activeInlineTextEditingPanel?.endInlineTextEditing()
        panel.beginInlineTextEditing(onCancel: onCancel)
    }

}
