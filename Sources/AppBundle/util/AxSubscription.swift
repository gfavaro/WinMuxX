import AppKit
import Common

/// The subscription is active as long as you keep this class in memory
final class AxSubscription {
    let obs: AXObserver
    let ax: AXUIElement
    let axThreadToken: AxAppThreadToken = axTaskLocalAppThreadToken ?? dieT("axTaskLocalAppThreadToken is not initialized")
    var notifKeys: Set<String> = []
    private let windowIdContext: UnsafeMutablePointer<UInt32>?

    private init(obs: AXObserver, ax: AXUIElement, windowId: UInt32?) {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        self.obs = obs
        self.ax = ax
        if let windowId {
            let context = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
            context.initialize(to: windowId)
            windowIdContext = context
        } else {
            windowIdContext = nil
        }
    }

    private func subscribe(_ key: String) throws -> Bool {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        if AXObserverAddNotification(obs, ax, key as CFString, windowIdContext) == .success {
            notifKeys.insert(key)
            return true
        } else {
            return false
        }
    }

    static func bulkSubscribe(_ nsApp: NSRunningApplication, _ ax: AXUIElement, _ job: RunLoopJob, _ handlerToNotifKeyMapping: HandlerToNotifKeyMapping, windowId: UInt32? = nil) throws -> [AxSubscription] {
        var result: [AxSubscription] = []
        var visitedNotifKeys: Set<String> = []
        for (handler, notifKeys) in handlerToNotifKeyMapping {
            try job.checkCancellation()
            guard let obs = AXObserver.new(nsApp.processIdentifier, handler) else { return [] }
            let subscription = AxSubscription(obs: obs, ax: ax, windowId: windowId)
            for key: String in notifKeys {
                try job.checkCancellation()
                assert(visitedNotifKeys.insert(key).inserted)
                if try !subscription.subscribe(key) { return [] }
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
            result.append(subscription)
        }
        return result
    }

    deinit {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        for notifKey in notifKeys {
            AXObserverRemoveNotification(obs, ax, notifKey as CFString)
        }
        windowIdContext?.deinitialize(count: 1)
        windowIdContext?.deallocate()
    }
}

typealias HandlerToNotifKeyMapping = [(AXObserverCallback, [String])]
