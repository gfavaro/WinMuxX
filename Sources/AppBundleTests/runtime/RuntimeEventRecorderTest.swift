@testable import AppBundle
import Foundation
import Common
import XCTest

@MainActor
final class RuntimeEventRecorderTest: WorkspaceTestCase {
    func testDiagnosticFlagsUseQueryPathWithoutLayoutOrNativeStateReads() async throws {
        let window = TestWindow.new(id: 99, parent: focus.workspace.rootTilingContainer)
        let untouched = Workspace.get(byName: "unreconciled-empty")
        for index in 0..<3 {
            var args = DebugWindowsCmdArgs(rawArgs: [])
            args.eventsStart = index == 0
            args.checkModel = index == 1
            args.eventsStop = index == 2
            let command = DebugWindowsCommand(args: args)
            XCTAssertTrue(command.isQuery)
            _ = try await runCommandSession(.socketServer(args), .forceRun,
                isQuery: command.isQuery, shouldSchedulePostRefresh: !command.canSkipPostCommandRefresh) {
                try await command.run(.defaultEnv, .emptyStdin)
            }
        }
        XCTAssertNil(window.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(window.nativeStateFetchCount, 0)
        XCTAssertTrue(Workspace.existing(byName: untouched.name) === untouched)
        XCTAssertFalse(runtime.events.isRecording)
    }

    func testExplicitModelScanRefusesUnsettledRefresh() async throws {
        var args = DebugWindowsCmdArgs(rawArgs: [])
        args.checkModel = true
        let active = Task<Void, Error> { }
        runtime.refresh.activeRefreshTask = active
        defer { runtime.refresh.activeRefreshTask = nil; active.cancel() }
        let accepted = try await DebugWindowsCommand(args: args).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(accepted.exitCode, 1)
    }

    func testDisabledOverflowResetAndOrdering() {
        let recorder = RuntimeEventRecorder(eventLimit: 2)
        recorder.record(.cancelled, source: .refresh, generation: 0)
        XCTAssertTrue(recorder.events.isEmpty)
        recorder.start()
        for generation in 0..<4 { recorder.record(.cancelled, source: .refresh, generation: UInt64(generation)) }
        XCTAssertEqual(recorder.events.map(\.generation), [2, 3])
        XCTAssertEqual(recorder.dropped, 2)
        XCTAssertLessThanOrEqual(recorder.events[0].monotonicNanoseconds, recorder.events[1].monotonicNanoseconds)
        recorder.stop()
        XCTAssertEqual(recorder.payloadBytes, 0)
        XCTAssertEqual(recorder.dropped, 0)
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertFalse(recorder.isRecording)
    }

    func testByteBoundAndOversizedPayload() {
        let recorder = RuntimeEventRecorder(byteLimit: 320)
        recorder.start()
        for i in 0..<100 { recorder.record(.refreshRequested, source: .refresh, generation: UInt64(i)) }
        XCTAssertLessThanOrEqual(recorder.payloadBytes, 320)
        XCTAssertGreaterThan(recorder.dropped, 0)
        let tiny = RuntimeEventRecorder(byteLimit: 1)
        tiny.start(); tiny.record(.cancelled, source: .refresh, generation: 1)
        XCTAssertEqual(tiny.dropped, 1)
        XCTAssertTrue(tiny.events.isEmpty)
    }

    func testTypedFrameReasonAndViewportDoNotRetainWindowObjects() {
        let recorder = RuntimeEventRecorder()
        recorder.start()
        let frame = Rect(topLeftX: -200, topLeftY: 10, width: 800, height: 600)
        recorder.record(.nativeFrameObserved, source: .nativeState, generation: 7, windowID: 1,
            viewport: MonitorViewportId(topLeftCorner: .init(x: -1200, y: 0)), observedFrame: frame)
        recorder.record(.cancelled, source: .refresh, generation: 8)
        recorder.record(.staleObservation, source: .nativeState, generation: 7)
        XCTAssertEqual(recorder.events[0].observedFrame?.x, -200)
        XCTAssertNotNil(recorder.events[0].viewport)
        XCTAssertEqual(recorder.events[1].reason, "task-cancelled")
        XCTAssertEqual(recorder.events[2].reason, "native-generation-changed")
    }

    func testPrivateExportRedactsConfigAndFailurePreservesRecording() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("secret-config")
        try Data("secret title and personal config".utf8).write(to: config)
        let recorder = RuntimeEventRecorder()
        recorder.start(); recorder.record(.staleObservation, source: .nativeState, generation: 3, windowID: 42)
        XCTAssertThrowsError(try recorder.export(to: directory.appendingPathComponent("absent/log"), configURL: config, topology: []))
        XCTAssertEqual(recorder.events.count, 1)
        let url = directory.appendingPathComponent("events.json")
        try recorder.export(to: url, configURL: config, topology: ["0,0,1920,1080"])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains(config.path))
        XCTAssertTrue(text.contains("configSHA256"))
        XCTAssertTrue(text.contains("\"schema\":2"))
        XCTAssertTrue(text.contains("workMetrics"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        recorder.stop()
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testWorkMetricsAreOptInBoundedAndDiscardOldCollectionCompletions() {
        let metrics = RuntimeWorkMetrics(sampleLimit: 2)
        metrics.record(.axRead, failed: false, duration: 0.01, generation: 0)
        XCTAssertEqual(metrics.snapshot().operations["axRead"], nil)
        let old = metrics.start()
        metrics.record(.axRead, failed: false, duration: 0.01, generation: old)
        metrics.record(.axRead, failed: true, duration: 0.02, generation: old)
        metrics.record(.axRead, failed: false, duration: 0.025, generation: old)
        metrics.record(.axWrite, failed: false, duration: 0.03, generation: old)
        XCTAssertEqual(metrics.snapshot().operations["axRead"], 3)
        XCTAssertEqual(metrics.snapshot().operations["axWrite"], 1)
        XCTAssertEqual(metrics.snapshot().droppedSamples, 1)
        XCTAssertEqual(metrics.snapshot().failures, 1)
        metrics.stop()
        let current = metrics.start()
        metrics.record(.axRead, failed: false, duration: 0.04, generation: old)
        XCTAssertNil(metrics.snapshot().operations["axRead"])
        metrics.record(.axRead, failed: false, duration: 0.04, generation: current)
        XCTAssertEqual(metrics.snapshot().operations["axRead"], 1)
        metrics.stop()
    }
}
