import Common

@MainActor
func activateMonitorViewportFallbackWorkspaceForTests(on monitor: Monitor) -> Workspace {
    let workspace = getOrCreateMonitorViewportFallbackWorkspace(for: monitor)
    check(monitor.setActiveWorkspace(workspace))
    return workspace
}
