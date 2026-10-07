import AppKit
import SwiftUI

struct WorkspaceSidebarScopeSegmentedControl: NSViewRepresentable {
    let scopes: [WorkspaceSidebarMonitorScopeViewModel]
    let selectedScopeId: String?
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.controlSize = .small
        control.segmentStyle = .rounded
        control.trackingMode = .selectOne
        control.font = .systemFont(ofSize: 12)
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectScope(_:))
        control.setAccessibilityLabel("Workspace scope")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.appearance = NSAppearance(named: context.environment.workspaceSidebarAppearance == .custom || context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        control.segmentCount = scopes.count
        for (index, scope) in scopes.enumerated() {
            control.setLabel(scope.id == workspaceSidebarFocusedScopeId ? "Focus" : scope.displayName, forSegment: index)
            control.setToolTip(scope.subtitle.map { "\(scope.displayName), \($0)" } ?? scope.displayName, forSegment: index)
        }
        control.selectedSegment = scopes.firstIndex { $0.id == selectedScopeId } ?? -1
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: WorkspaceSidebarScopeSegmentedControl
        init(parent: WorkspaceSidebarScopeSegmentedControl) { self.parent = parent }

        @objc func selectScope(_ control: NSSegmentedControl) {
            guard parent.scopes.indices.contains(control.selectedSegment) else { return }
            parent.onSelect(parent.scopes[control.selectedSegment].id)
        }
    }
}
