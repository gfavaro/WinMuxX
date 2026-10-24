import AppKit
import SwiftUI

enum WorkspaceOverviewKeyAction: Equatable {
    case dismiss, move(Int), cycleWindow(backward: Bool), activate, page(Int)
}

func workspaceOverviewKeyAction(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                               hasMarkedText: Bool) -> WorkspaceOverviewKeyAction? {
    guard !hasMarkedText, modifiers.intersection([.command, .option, .control]).isEmpty,
          !modifiers.contains(.shift) || keyCode == 48 else { return nil }
    switch keyCode {
    case 53: return .dismiss
    case 123: return .move(-1)
    case 124: return .move(1)
    case 125: return .move(4)
    case 126: return .move(-4)
    case 48: return .cycleWindow(backward: modifiers.contains(.shift))
    case 36, 76: return .activate
    case 116: return .page(-1)
    case 121: return .page(1)
    default: return nil
    }
}

@MainActor
final class WorkspaceOverviewPanel: NSPanelHud {
    let model: WorkspaceOverviewDisplayModel
    let presentation = WorkspaceOverviewPresentation()
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init(model: WorkspaceOverviewDisplayModel, monitorName: String, frame: CGRect) {
        self.model = model
        super.init()
        identifier = NSUserInterfaceItemIdentifier("WinMux.workspaceOverview")
        title = "Workspace Overview"
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        applyWinMuxLayer(.overlay)
        setFrame(frame, display: false)
        contentView = NSHostingView(rootView: WorkspaceOverviewView(model: model, monitorName: monitorName))
    }
    func prepareForReuse(name: String, frame: CGRect) {
        setFrame(frame, display: false)
        if let hosting = contentView as? NSHostingView<WorkspaceOverviewView> {
            hosting.rootView = WorkspaceOverviewView(model: model, monitorName: name)
        }
    }

    override func mouseDown(with event: NSEvent) { model.dismiss?() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let action = workspaceOverviewKeyAction(keyCode: event.keyCode, modifiers: event.modifierFlags,
                hasMarkedText: overlayHasMarkedText(firstResponder)) {
            // Native controls and editors keep their own navigation/activation.
            // Escape remains an overlay dismissal unless composition owns it.
            if firstResponder is NSTextView || (firstResponder is NSControl && action != .dismiss) {
                super.sendEvent(event); return
            }
            switch action {
            case .dismiss: model.dismiss?()
            case .move(let delta): model.moveSelection(delta)
            case .cycleWindow(let backward): model.cycleWindow(backward: backward)
            case .activate: model.activateSelection()
            case .page(let delta): model.changePage(delta)
            }
            return
        }
        super.sendEvent(event)
    }
}
