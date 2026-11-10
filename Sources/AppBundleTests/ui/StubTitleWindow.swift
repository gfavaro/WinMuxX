@testable import AppBundle

/// Mutable title source shared by cache and session-accessor tests.
final class StubTitleWindow: Window {
    var stubTitle: String
    var titleGetCount: Int = 0

    @MainActor
    init(id: UInt32, title: String) {
        stubTitle = title
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: Workspace.get(byName: "title-test"), adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }

    override func closeAxWindow() {}

    @MainActor
    override var title: String {
        get async {
            titleGetCount += 1
            return stubTitle
        }
    }

    @MainActor override var isMacosFullscreen: Bool { get async throws { false } }
    @MainActor override var isMacosMinimized: Bool { get async throws { false } }
}
