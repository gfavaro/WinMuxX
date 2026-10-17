import AppKit
import Common
import ImageIO
import QuartzCore

struct WorkspaceSwipeSnapshotKey: Hashable, Sendable {
    let workspace: WorkspaceId
    let display: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    @MainActor
    init(workspace: Workspace, monitor: Monitor, rect: Rect) {
        self.workspace = workspace.id
        display = monitor.displayUUID ?? String(describing: monitor.rect.topLeftCorner)
        x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
    }

    init(workspace: WorkspaceId, display: String, rect: CGRect) {
        self.workspace = workspace; self.display = display
        x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
    }
}

/// Only immutable values cross to the renderer; AX objects and workspace trees stay on MainActor.
struct WorkspaceSwipeSnapshotRequest: Sendable {
    struct Window: Sendable {
        let id: UInt32
        let frame: CGRect
    }
    let key: WorkspaceSwipeSnapshotKey
    let screenRect: CGRect?
    let wallpaper: URL?
    let windows: [Window]

    @MainActor
    init(workspace: Workspace, monitor: Monitor, rect: Rect) {
        screenRect = nil
        key = WorkspaceSwipeSnapshotKey(workspace: workspace, monitor: monitor, rect: rect)
        let screens = NSScreen.screens
        let index = monitor.monitorAppKitNsScreenScreensId - 1
        wallpaper = screens.indices.contains(index) ? NSWorkspace.shared.desktopImageURL(for: screens[index]) : nil
        windows = workspace.allLeafWindowsRecursive.compactMap { node in
            guard let window = node as? MacWindow, case .standard = window.layoutReason else { return nil }
            if let group = window.nearestWindowTabGroup, group.usesWindowTabBehavior, group.tabActiveWindow !== window { return nil }
            guard let saved = window.workspacePreviewFrame ?? window.lastAppliedLayoutPhysicalRect else { return nil }
            let origin = window.workspacePreviewMonitorOrigin ?? monitor.rect.topLeftCorner
            return Window(id: window.windowId, frame: CGRect(
                x: saved.minX - origin.x + monitor.rect.minX - rect.minX,
                y: rect.height - (saved.minY - origin.y + monitor.rect.minY - rect.minY) - saved.height,
                width: saved.width, height: saved.height))
        }
    }

    init(key: WorkspaceSwipeSnapshotKey, wallpaper: URL? = nil, windows: [Window] = []) {
        self.key = key; self.wallpaper = wallpaper; self.windows = windows; screenRect = nil
    }
    init(screenKey: WorkspaceSwipeSnapshotKey, rect: CGRect) {
        key = screenKey
        screenRect = rect
        wallpaper = nil
        windows = []
    }
}

struct WorkspaceSwipeSnapshotResult: Sendable {
    let image: CGImage
    let renderMs: Double
    let renderedOnMainThread = Thread.isMainThread
}

struct WorkspaceSwipeSnapshotCache {
    private var images: [WorkspaceSwipeSnapshotKey: CGImage] = [:]
    private var order: [WorkspaceSwipeSnapshotKey] = []
    private(set) var bytes = 0
    let maxImages: Int
    let maxBytes: Int
    var count: Int { images.count }

    init(maxImages: Int = 4, maxBytes: Int = 64 * 1024 * 1024) {
        self.maxImages = maxImages; self.maxBytes = maxBytes
    }

    mutating func image(for key: WorkspaceSwipeSnapshotKey) -> CGImage? {
        guard let image = images[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return image
    }

    mutating func insert(_ image: CGImage, for key: WorkspaceSwipeSnapshotKey) {
        let cost = image.bytesPerRow * image.height
        guard maxImages > 0, cost <= maxBytes else { return }
        if let old = images.removeValue(forKey: key) { bytes -= old.bytesPerRow * old.height }
        order.removeAll { $0 == key }
        images[key] = image; order.append(key); bytes += cost
        while images.count > maxImages || bytes > maxBytes {
            let oldest = order.removeFirst()
            if let removed = images.removeValue(forKey: oldest) { bytes -= removed.bytesPerRow * removed.height }
        }
    }

    mutating func clear() { images.removeAll(); order.removeAll(); bytes = 0 }
}

/// One active render plus one replaceable request, even if a native capture ignores cancellation.
@MainActor
final class WorkspaceSwipeSnapshots {
    typealias Renderer = @Sendable (WorkspaceSwipeSnapshotRequest) async throws -> WorkspaceSwipeSnapshotResult
    private struct Job {
        let generation: Int
        let request: WorkspaceSwipeSnapshotRequest
        let completion: @MainActor (Result<WorkspaceSwipeSnapshotResult, any Error>) -> Void
    }
    var cache = WorkspaceSwipeSnapshotCache()
    private let renderer: Renderer
    private var task: Task<Void, Never>?
    private var pending: Job?
    private var generation = 0

    init(renderer: @escaping Renderer = { try await WorkspaceSwipeSnapshotRenderer.shared.render($0) }) {
        self.renderer = renderer
    }

    func request(_ request: WorkspaceSwipeSnapshotRequest,
                 completion: @escaping @MainActor (Result<WorkspaceSwipeSnapshotResult, any Error>) -> Void) {
        cancel()
        pending = Job(generation: generation, request: request, completion: completion)
        startNext()
    }

    func cancel() { generation += 1; pending = nil; task?.cancel() }
    func invalidate() { cancel(); cache.clear() }

    private func startNext() {
        guard task == nil, let job = pending else { return }
        pending = nil
        let renderer = renderer
        task = Task { @MainActor [weak self] in
            let result: Result<WorkspaceSwipeSnapshotResult, any Error>
            do { result = .success(try await renderer(job.request)) } catch { result = .failure(error) }
            guard let self else { return }
            self.task = nil
            if self.generation == job.generation, !Task.isCancelled {
                if case .success(let snapshot) = result { self.cache.insert(snapshot.image, for: job.request.key) }
                job.completion(result)
            }
            self.startNext()
        }
    }
}

/// Offscreen rendering has its own executor and local graphics contexts.
private actor WorkspaceSwipeSnapshotRenderer {
    static let shared = WorkspaceSwipeSnapshotRenderer()

    func render(_ request: WorkspaceSwipeSnapshotRequest) throws -> WorkspaceSwipeSnapshotResult {
        try Task.checkCancellation()
        let start = CACurrentMediaTime()
        if let rect = request.screenRect {
            guard let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.nominalResolution]) else {
                throw CocoaError(.fileReadUnknown)
            }
            try Task.checkCancellation()
            return WorkspaceSwipeSnapshotResult(image: image, renderMs: (CACurrentMediaTime() - start) * 1000)
        }
        let width = request.key.width, height = request.key.height
        let scale = min(1, 2048 / max(width, height))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: max(1, Int(width * scale)), height: max(1, Int(height * scale)),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let url = request.wallpaper, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let wallpaper = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                        kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) {
            let ratio = max(width / Double(wallpaper.width), height / Double(wallpaper.height))
            let size = CGSize(width: Double(wallpaper.width) * ratio, height: Double(wallpaper.height) * ratio)
            context.draw(wallpaper, in: CGRect(x: (width - size.width) / 2, y: (height - size.height) / 2, width: size.width, height: size.height))
        }
        try Task.checkCancellation()
        var windows = request.windows
        if windows.count > 1 {
            let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            var rank: [UInt32: Int] = [:]
            for (index, item) in info.enumerated() {
                if let id = item[kCGWindowNumber as String] as? UInt32 { rank[id] = index }
            }
            windows.sort { (rank[$0.id] ?? 0) > (rank[$1.id] ?? 0) }
        }
        for window in windows {
            try Task.checkCancellation()
            autoreleasepool {
                if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, window.id, [.boundsIgnoreFraming, .nominalResolution]) {
                    context.draw(image, in: window.frame)
                }
            }
        }
        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return WorkspaceSwipeSnapshotResult(image: image, renderMs: (CACurrentMediaTime() - start) * 1000)
    }
}
