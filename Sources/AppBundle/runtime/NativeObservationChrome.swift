import Common

/// Refreshes what follows a native observation (tray, borders, desktop history, the
/// listing of desktops not showing and the sidebar) once per burst of completed reads.
@MainActor
final class NativeObservationChrome {
    static let shared = NativeObservationChrome()
    private var task: Task<Void, Never>?
    private(set) var requests = 0
    private(set) var refreshes = 0

    func schedule() {
        requests += 1
        guard task == nil else { return }
        let owner = runtime
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard let self else { return }
            self.task = nil
            self.refreshes += 1
            await owner.withValue {
                updateTrayText()
                WindowBorderController.shared.refresh()
                owner.workspaceBackend.noteNativeActivity()
                NativeUnvisitedWindows.shared.refresh()
                await updateWorkspaceSidebarModel()
            }
        }
    }
}
