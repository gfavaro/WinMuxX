import Common
import Foundation
import Network

private struct Subscriber {
    let events: Set<ServerEventType>
    let writer: SubscriberEventWriter
}

@MainActor private var subscribers: [UniqueToken: Subscriber] = [:]

@MainActor
func handleSubscribeAndWaitTillError(_ connection: NWConnection, _ args: SubscribeCmdArgs) async {
    let id = UniqueToken()
    let writer = SubscriberEventWriter(send: { payload in
        await connection.writeAtomicPayload(payload).error == nil
    }, disconnect: { connection.cancel() })
    subscribers[id] = Subscriber(events: args.events, writer: writer)
    defer { writer.close(); subscribers.removeValue(forKey: id) }
    if args.sendInitial {
        let f = focus
        for eventType in args.events {
            let event: ServerEvent
            switch eventType {
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
            guard let payload = try? jsonEncoder.encode(event) else { writer.close(); return }
            writer.enqueue(payload)
        }
    }

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
