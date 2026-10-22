import Common
import Foundation
import Network

private struct Subscriber {
    let events: Set<ServerEventType>
    let writer: SubscriberEventWriter
    var needsInitialState = false
}

@MainActor private var subscribers: [UniqueToken: Subscriber] = [:]

@MainActor
func handleSubscribeAndWaitTillError(_ connection: NWConnection, _ args: SubscribeCmdArgs) async {
    let id = UniqueToken()
    let writer = SubscriberEventWriter(send: { payload in
        await connection.writeAtomicPayload(payload).error == nil
    }, disconnect: { connection.cancel() })
    _ = registerSubscriber(id: id, events: args.events, writer: writer, sendInitial: args.sendInitial)
    defer { unregisterSubscriber(id) }

    // Keep connection alive - wait for client to disconnect
    await connection.readTillError()
}

private let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return e
}()

@MainActor
func broadcastEvent(_ event: ServerEvent) {
    let recipients = subscribers.filter { $0.value.events.contains(event.eventType) }
    guard !recipients.isEmpty, let payload = try? jsonEncoder.encode(event) else { return }
    for (id, subscriber) in recipients {
        subscriber.writer.enqueue(payload)
        if subscriber.writer.isClosed { subscribers.removeValue(forKey: id) }
    }
}

@MainActor var hasPublicStateSubscribers: Bool {
    subscribers.values.contains { $0.events.contains(.stateChanged) }
}

@MainActor func broadcastPublicState(_ state: PublicStateEnvelope, changed: Bool = true) {
    guard let payload = try? jsonEncoder.encode(state) else { return }
    for (id, subscriber) in subscribers where subscriber.events.contains(.stateChanged) && (changed || subscriber.needsInitialState) {
        subscriber.writer.enqueue(payload)
        subscribers[id]?.needsInitialState = false
        if subscriber.writer.isClosed { subscribers.removeValue(forKey: id) }
    }
}

@MainActor @discardableResult
func registerSubscriber(id: UniqueToken = UniqueToken(), events: Set<ServerEventType>,
                        writer: SubscriberEventWriter, sendInitial: Bool) -> UniqueToken {
    subscribers[id] = Subscriber(events: events, writer: writer)
    if sendInitial {
        let f = focus
        for eventType in events {
            let event: ServerEvent
            switch eventType {
                case .stateChanged:
                    // A subscriber arriving during an awaited transaction gets its
                    // first snapshot at the settled boundary, never an intermediate tree.
                    if runtime.publicState.transactionDepth > 0 {
                        subscribers[id]?.needsInitialState = true
                        continue
                    }
                    guard let payload = try? jsonEncoder.encode(publicStateSnapshot()) else { writer.close(); return id }
                    writer.enqueue(payload)
                    continue
                case .focusChanged:
                    event = .focusChanged(windowId: f.windowOrNil?.windowId, workspace: f.workspace.name)
                case .workspaceChanged:
                    event = .workspaceChanged(workspace: f.workspace.name, prevWorkspace: f.workspace.name)
                case .modeChanged:
                    event = .modeChanged(mode: activeMode)
                case .focusedMonitorChanged:
                    event = .focusedMonitorChanged(
                        workspace: f.workspace.name,
                        monitorId_oneBased: f.workspace.workspaceMonitor.monitorId_oneBased ?? 0,
                    )
                case .windowDetected, .bindingTriggered: continue
            }
            guard let payload = try? jsonEncoder.encode(event) else { writer.close(); return id }
            writer.enqueue(payload)
        }
    }

    return id
}

@MainActor func unregisterSubscriber(_ id: UniqueToken) {
    subscribers.removeValue(forKey: id)?.writer.close()
}

@MainActor var hasPendingInitialStateSubscribers: Bool {
    subscribers.values.contains { $0.needsInitialState }
}
