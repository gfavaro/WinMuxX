@testable import AppBundle
import Common
import XCTest

@MainActor
final class AeroSporkAdoptionConfigTest: XCTestCase {
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("config.toml") }
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: directory) }

    func testBackupsRotateAndAllReplacementsArePrivate() throws {
        for value in 0...7 {
            try ConfigFileStore.edit(at: url) { _ in "focus-follows-mouse-dwell = \(value)\n" }
        }
        XCTAssertEqual(try String(contentsOf: url), "focus-follows-mouse-dwell = 7\n")
        for index in 1...5 {
            let backup = url.appendingPathExtension("backup.\(index)")
            XCTAssertEqual(try String(contentsOf: backup), "focus-follows-mouse-dwell = \(7 - index)\n")
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int, 0o600)
        }
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("backup.6").path))
    }

    func testNoOpAndInvalidEditLeaveFileAndBackupsUnchanged() throws {
        let original = "# retained comment\nfocus-follows-mouse-dwell = 9\n"
        try ConfigFileStore.replace(at: url, text: original, expected: nil)
        XCTAssertFalse(try ConfigFileStore.edit(at: url) { $0 })
        XCTAssertThrowsError(try ConfigFileStore.edit(at: url) { _ in "focus-follows-mouse-dwell = 'bad'" })
        XCTAssertEqual(try String(contentsOf: url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("backup.1").path))
    }

    func testRawEditorRefusesAnExternalChange() throws {
        try ConfigFileStore.replace(at: url, text: "focus-follows-mouse-dwell = 3", expected: nil)
        try "focus-follows-mouse-dwell = 4".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ConfigFileStore.replace(at: url, text: "focus-follows-mouse-dwell = 5", expected: "focus-follows-mouse-dwell = 3"))
        XCTAssertEqual(try String(contentsOf: url), "focus-follows-mouse-dwell = 4")
    }

    func testStructuredEditReappliesToExternalChangesAndPreservesSymlink() throws {
        let target = directory.appendingPathComponent("actual.toml")
        try "focus-follows-mouse-dwell = 3\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        var attempts = 0
        try ConfigFileStore.edit(at: url) { text in
            attempts += 1
            if attempts == 1 { try "# external\nfocus-follows-mouse-dwell = 4\n".write(to: target, atomically: true, encoding: .utf8) }
            return text + "# our edit\n"
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(try String(contentsOf: target), "# external\nfocus-follows-mouse-dwell = 4\n# our edit\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), target.path)
    }

    func testPrivateStateWriteKeepsModeAcrossAtomicReplacement() throws {
        try writePrivateData(Data("one".utf8), to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try writePrivateData(Data("two".utf8), to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data("two".utf8))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
    }

    func testUuidSelectsTheCorrectIdenticalDisplayAndNeverFallsBack() throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 800)
        let a = "AAAAAAAA-0000-4000-8000-000000000001", b = "AAAAAAAA-0000-4000-8000-000000000002"
        let monitors = [TestMonitor(displayUUID: a, monitorAppKitNsScreenScreensId: 1, name: "Same", rect: rect, visibleRect: rect, isMain: true),
                        TestMonitor(displayUUID: b, monitorAppKitNsScreenScreensId: 2, name: "Same", rect: rect, visibleRect: rect, isMain: false)]
        setMonitorsForTests(monitors)
        let selector = try XCTUnwrap(parseMonitorDescription("uuid:" + b.lowercased()).getOrNil())
        XCTAssertEqual(selector.resolveMonitor(sortedMonitors: monitors)?.displayUUID, b)
        XCTAssertNil(selector.resolveMonitor(sortedMonitors: [monitors[0]]))
        XCTAssertNil(parseMonitorDescription("uuid:invalid").getOrNil())
        XCTAssertEqual(parseMonitorDescription("main").getOrNil(), .main)
    }
}
