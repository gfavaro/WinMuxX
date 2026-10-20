import AppKit
import Common
import ScreenCaptureKit

/// Actor isolation alone is insufficient when the native screenshot suspends.
/// Each producer holds one slot until completion, even when cancellation is ignored.
actor WorkspaceCaptureGate {
    private let onQueued: @Sendable () -> Void
    init(onQueued: @escaping @Sendable () -> Void = {}) { self.onQueued = onQueued }
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        if busy { await withCheckedContinuation { waiting.append($0); onQueued() } }
        else { busy = true }
        defer {
            if waiting.isEmpty { busy = false }
            else { waiting.removeFirst().resume() }
        }
        try Task.checkCancellation()
        let result = try await operation()
        try Task.checkCancellation()
        return result
    }
}

extension WorkspaceSwipeSnapshotRenderer {
    /// One shareable-content query per overview opening, including parked windows.
    func prepareOverview(_ session: UUID) async -> [UInt32: Int] {
        let ranks = windowRanks()
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess() else { return ranks }
        if #available(macOS 14, *) {
            let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard !Task.isCancelled else { return ranks }
            overviewCaptureSession = session
            overviewCaptureWindows = Dictionary((content?.windows ?? []).map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return ranks
    }

    func endOverview(_ session: UUID) {
        guard overviewCaptureSession == session else { return }
        overviewCaptureSession = nil
        overviewCaptureWindows.removeAll()
    }

    func renderOverview(_ request: WorkspaceSwipeSnapshotRequest) async throws -> CGImage {
        if #available(macOS 14, *), request.allowCapture {
            return try await captureGate.run { try await self.renderModernOverview(request) }
        }
        return try await render(request).image
    }

    @available(macOS 14, *)
    private func renderModernOverview(_ request: WorkspaceSwipeSnapshotRequest) async throws -> CGImage {
        try Task.checkCancellation()
        let width = request.key.width, height = request.key.height
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw CocoaError(.coderInvalidValue) }
        let scale = min(1, request.maximumPixelSize.width / width, request.maximumPixelSize.height / height)
        guard let context = CGContext(data: nil, width: max(1, Int(width * scale)), height: max(1, Int(height * scale)),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Take only this session's descriptors. Closing releases the service cache;
        // a native call already in flight may retain its one descriptor until it returns.
        let windows = overviewCaptureSession == request.overviewSession ? overviewCaptureWindows : [:]
        for item in request.windows {
            try Task.checkCancellation()
            context.setFillColor(CGColor(gray: 0.23, alpha: 1))
            context.fill(item.frame)
            guard let window = windows[item.id] else { continue }
            let configuration = SCStreamConfiguration()
            let windowScale = min(scale, request.maximumPixelSize.width / max(1, item.frame.width),
                                  request.maximumPixelSize.height / max(1, item.frame.height))
            configuration.width = max(1, Int(item.frame.width * windowScale))
            configuration.height = max(1, Int(item.frame.height * windowScale))
            configuration.showsCursor = false
            configuration.scalesToFit = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.captureResolution = .nominal
            if #available(macOS 14.2, *) { configuration.includeChildWindows = false }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            // No fallback to CGWindowListCreateImage on modern systems: its compatibility
            // proxy leaked CGRect dictionaries in the measured macOS 27.2 workload.
            let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            if let image { context.draw(image, in: item.frame) }
        }
        guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return image
    }
}
