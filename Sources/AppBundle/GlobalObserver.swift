import AppKit
import Common
import HotKey
import PrivateApi

enum GlobalObserver {
    @MainActor private static var isInitialized = false
    @MainActor private static var notificationObserverTokens: [NSObjectProtocol] = []
    @MainActor private static var eventMonitorTokens: [Any] = []
    @MainActor private static var focusFollowsMouseTask: Task<Void, Never>?

    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == lockScreenAppBundleId {
            return
        }
        let notifName = notification.name.rawValue
        Task { @MainActor in
            if !TrayMenuModel.shared.isEnabled { return }
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                scheduleRefreshSession(.globalObserver(notifName), optimisticallyPreLayoutWorkspaces: true)
            } else {
                scheduleRefreshSession(.globalObserver(notifName))
            }
        }
    }

    private static func onHideApp(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.globalObserver(notifName), token) {
                if config.automaticallyUnhideMacosHiddenApps {
                    if let w = prevFocus?.windowOrNil,
                       w.macAppUnsafe.nsApp.isHidden,
                       // "Hide others" (cmd-alt-h) -> don't force focus
                       // "Hide app" (cmd-h) -> force focus
                       MacApp.allAppsMap.values.count(where: { $0.nsApp.isHidden }) == 1
                    {
                        // Force focus
                        _ = w.focusWindow()
                        w.nativeFocus()
                    }
                    for app in MacApp.allAppsMap.values {
                        app.nsApp.unhide()
                    }
                }
            }
        }
    }

    // NSEvent monitor callbacks arrive on the main thread. Running their bodies synchronously
    // instead of spawning a Task avoids an allocation + run-loop hop per input event — pointer
    // events fire at 60-120Hz, so the Task-per-event pattern adds constant latency and churn.
    private static func runOnMainActor(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }

    private static func onKeyDown(_ event: NSEvent) {
        runOnMainActor {
            noteTapBindingKeyDown()
        }
    }


    private static func onFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        runOnMainActor {
            noteTapBindingFlagsChanged(keyCode: keyCode, modifierFlags: modifierFlags)
        }
    }

    private static func onPointerActivity(_ event: NSEvent) {
        let isLeftMouseDownEvent = event.type == .leftMouseDown
        let timestamp = event.timestamp
        let screenPoint = NSEvent.mouseLocation
        let point = normalizeAppKitScreenPoint(screenPoint)
        runOnMainActor {
            MousePointerTracker.shared.note(point: point, timestamp: timestamp)
            scheduleFocusFollowsMouse(point: point, timestamp: timestamp)
            WorkspaceSidebarPanel.trapCursorForVisiblePanelsIfNeeded()
            WorkspaceSidebarPanel.noteHoverPointerActivityForVisiblePanels(timestamp: timestamp)
            if isLeftMouseDownEvent {
                Task { @MainActor in
                    await WindowMouseInteractionDriver.shared.capturePendingResizeCandidate()
                }
            }
            noteTapBindingKeyDown()
        }
    }

    @MainActor
    static func cancelFocusFollowsMouse() {
        FocusFollowsMouseController.shared.cancel()
        focusFollowsMouseTask?.cancel()
        focusFollowsMouseTask = nil
    }

    @MainActor
    private static func scheduleFocusFollowsMouse(point: CGPoint, timestamp: TimeInterval) {
        guard TrayMenuModel.shared.isEnabled, config.focusFollowsMouse, !isLeftMouseButtonDown,
              !isMouseManipulationActive,
              let window = point.findIn(tree: focus.workspace.rootTilingContainer, virtual: false),
              window.participatesInWorkspaceFocus,
              window != focus.windowOrNil else {
            cancelFocusFollowsMouse()
            return
        }
        _ = FocusFollowsMouseController.shared.notePointer(windowId: window.windowId, point: point, timestamp: timestamp)
        focusFollowsMouseTask?.cancel()
        let dwell = max(config.focusFollowsMouseDwell, 0)
        focusFollowsMouseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(dwell))
            guard !Task.isCancelled, TrayMenuModel.shared.isEnabled, config.focusFollowsMouse,
                  !isMouseManipulationActive,
                  !isLeftMouseButtonDown,
                  let target = Window.get(byId: window.windowId), target.nodeWorkspace == focus.workspace,
                  target.participatesInWorkspaceFocus,
                  let ready = FocusFollowsMouseController.shared.isReady(dwell: Double(dwell) / 1000, timestamp: ProcessInfo.processInfo.systemUptime),
                  ready == window.windowId else { return }
            _ = target.focusWindow()
            target.nativeFocus()
            FocusFollowsMouseController.shared.markFocused(window.windowId)
        }
    }

    @MainActor
    static func initObserver() {
        guard !isInitialized else { return }
        isInitialized = true
        WindowBorderController.shared.startMissionControlMonitoring()
        if !winmux_watch_window_closures({ windowId in
            Task { @MainActor in
                guard let window = MacWindow.allWindowsMap[windowId] else {
                    invalidateClosedWindowsCacheForNativeClosure(windowId)
                    return
                }
                let app = window.macApp
                window.garbageCollect(skipClosedWindowsCache: false)
                invalidateClosedWindowsCacheForNativeClosure(windowId)
                try? await app.unregisterDestroyedWindow(windowId)
                scheduleRefreshSession(.globalObserver("nativeWindowClosed"))
            }
        }) {
            print("WinMuxX: WindowServer close notifications unavailable; using AX fallback")
        }
        DoubleSidedWindowGesture.shared.install()

        let nc = NSWorkspace.shared.notificationCenter
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif))

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            // todo reduce number of refreshSession in the callback
            //  resetManipulatedWithMouseIfPossible might call its own refreshSession
            //  The end of the callback calls refreshSession
            Task { @MainActor in
                finishWorkspaceSidebarDragAfterGlobalMouseUp()
                guard let token: RunSessionGuard = .isServerEnabled else { return }
                try await resetManipulatedWithMouseIfPossible()
                // Drag-end releases the sidebar expansion locks without any pointer movement;
                // hover must be re-evaluated for a stationary cursor.
                WorkspaceSidebarPanel.scheduleHoverRecheckForVisiblePanels()
                let mouseLocation = mouseLocation
                let clickedMonitor = mouseLocation.monitorApproximation
                switch true {
                    // Detect clicks on desktop of different monitors
                    case clickedMonitor.activeWorkspace != focus.workspace:
                        _ = try await runLightSession(.globalObserverLeftMouseUp, token) {
                            clickedMonitor.activeWorkspace.focusWorkspace()
                        }
                    // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                    //  And trigger new window detection that could be delayed due to mouseDown event
                    default:
                        scheduleRefreshSession(.globalObserverLeftMouseUp)
                }
            }
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { event in
            let timestamp = event.timestamp
            let point = normalizeAppKitScreenPoint(NSEvent.mouseLocation)
            runOnMainActor {
                MousePointerTracker.shared.note(point: point, timestamp: timestamp)
                WorkspaceSidebarPanel.trapCursorForVisiblePanelsIfNeeded()
                refreshPendingWindowDragIntentFromGlobalMouseDrag()
            }
        })

        let pointerActivityMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]
        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: pointerActivityMask, handler: onPointerActivity))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: pointerActivityMask) { event in
            onPointerActivity(event)
            return event
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: onFlagsChanged))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            onFlagsChanged(event)
            return event
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: onKeyDown))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            onKeyDown(event)
            // Check if this key matches a recently-pressed prefix (sequence binding)
            if handleSequenceKeyDown(event: event) {
                return nil // consume the event
            }
            // If this is a sequence prefix key (e.g. Escape), arm the sequence detector
            if let prefix = Key(carbonKeyCode: UInt32(event.keyCode)),
               sequenceBindingsPrefixKeys.contains(prefix) {
                noteSequencePrefixKeyPressed(prefix)
            }
            if event.modifierFlags.contains(.control), event.keyCode == 34 {
                return nil // consume the event
            }
            return event
        })
    }

    @MainActor private static func retainEventMonitor(_ monitor: Any?) {
        guard let monitor else { return }
        eventMonitorTokens.append(monitor)
    }
}
