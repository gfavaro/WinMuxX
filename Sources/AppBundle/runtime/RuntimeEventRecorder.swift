import Foundation
import CryptoKit
import Common

/// Typed fields deliberately exclude titles, paths, keystrokes and arbitrary native text.
/// No payload is constructed, encoded or retained unless recording is explicitly enabled.
@MainActor
final class RuntimeEventRecorder {
    enum Kind: String, Codable { case refreshRequested, refreshCoalesced, refreshCompleted, cancelled, staleObservation, workspaceActivated, nativeFrameObserved, nativeFrameWritten }
    enum Source: String, Codable { case refresh, nativeState, model }
    struct Frame: Codable, Equatable {
        let x: Double, y: Double, width: Double, height: Double
        init(_ rect: Rect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    }
    struct Event: Codable, Equatable {
        let monotonicNanoseconds: UInt64
        let kind: Kind
        let source: Source
        let generation: UInt64
        let windowID: UInt32?
        let workspaceID: String?
        let viewport: String?
        let reason: String?
        let intendedFrame: Frame?
        let observedFrame: Frame?
    }
    private(set) var isRecording = false
    private(set) var dropped = 0
    private(set) var payloadBytes = 0
    private var records: [(event: Event, bytes: Int)?] = []
    private var head = 0
    private var count = 0
    let eventLimit: Int
    let byteLimit: Int
    init(eventLimit: Int = 2048, byteLimit: Int = 1_048_576) {
        self.eventLimit = max(0, eventLimit)
        self.byteLimit = max(0, byteLimit)
    }
    var events: [Event] { (0..<count).compactMap { records[(head + $0) % records.count]?.event } }
    func start() { reset(); isRecording = true }
    func stop() { isRecording = false; reset() }
    func reset() { records.removeAll(keepingCapacity: false); head = 0; count = 0; payloadBytes = 0; dropped = 0 }
    func record(_ kind: Kind, source: Source, generation: UInt64, windowID: UInt32? = nil, workspaceID: WorkspaceId? = nil, viewport: MonitorViewportId? = nil, intendedFrame: Rect? = nil, observedFrame: Rect? = nil) {
        guard isRecording else { return }
        let event = Event(monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds, kind: kind,
                          source: source, generation: generation, windowID: windowID, workspaceID: workspaceID?.rawValue,
                          viewport: viewport?.description,
                          reason: kind == .cancelled ? "task-cancelled" : kind == .staleObservation ? "native-generation-changed" : nil,
                          intendedFrame: intendedFrame.map(Frame.init), observedFrame: observedFrame.map(Frame.init))
        guard let data = try? JSONEncoder().encode(event) else { return }
        let bytes = data.count + 1 // include the serialized array separator
        guard eventLimit > 0, bytes + 2 <= byteLimit else { dropped += 1; return }
        if records.isEmpty { records = Array(repeating: nil, count: eventLimit) }
        while count >= eventLimit || payloadBytes + bytes + 2 > byteLimit {
            payloadBytes -= records[head]?.bytes ?? 0
            records[head] = nil
            head = (head + 1) % eventLimit
            count -= 1
            dropped += 1
        }
        records[(head + count) % eventLimit] = (event, bytes)
        count += 1
        payloadBytes += bytes
    }
    /// Export is explicit, private and atomic. Failure leaves the recording intact.
    func export(to url: URL, configURL: URL, topology: [String]) throws {
        struct Envelope: Encodable {
            let schema = 1
            let build: String
            let session: String
            let configSHA256: String?
            let topology: [String]
            let dropped: Int
            let events: [Event]
        }
        let fingerprint = (try? Data(contentsOf: configURL)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        let envelope = Envelope(build: gitHash, session: session.uuidString, configSHA256: fingerprint,
                                topology: topology, dropped: dropped, events: events)
        try writePrivateData(JSONEncoder().encode(envelope), to: url)
    }
    private(set) var session = UUID()
}
