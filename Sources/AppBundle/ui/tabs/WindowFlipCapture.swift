import AppKit

struct WindowFlipImages: Sendable {
    let front: CGImage
    let back: CGImage
    let background: CGImage
}

/// At most one native capture remains active, even if it ignores cancellation.
/// A deadline completes navigation without presenting a late animation.
@MainActor
final class WindowFlipPreparation {
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var completion: ((WindowFlipImages?) -> Void)?
    private let sleep: @Sendable () async throws -> Void
    var isBusy: Bool { work != nil }

    init(sleep: @escaping @Sendable () async throws -> Void = {
        try await Task.sleep(for: .milliseconds(80))
    }) { self.sleep = sleep }

    @discardableResult
    func begin(capture: @escaping @Sendable () async throws -> WindowFlipImages,
               completion: @escaping (WindowFlipImages?) -> Void) -> Bool {
        guard work == nil else { return false }
        self.completion = completion
        work = Task { @MainActor [weak self] in
            let images = try? await capture()
            guard let self else { return }
            self.work = nil
            if !Task.isCancelled { self.finish(images) }
        }
        deadline = Task { @MainActor [weak self, sleep] in
            do { try await sleep() } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.work?.cancel()
            self.finish(nil)
        }
        return true
    }

    func cancel() {
        completion = nil
        deadline?.cancel()
        deadline = nil
        work?.cancel()
    }

    func waitUntilIdle() async { await work?.value }

    private func finish(_ images: WindowFlipImages?) {
        deadline?.cancel()
        deadline = nil
        let completion = self.completion
        self.completion = nil
        completion?(images)
    }

    isolated deinit { work?.cancel(); deadline?.cancel() }
}

actor WindowFlipCapture {
    static let shared = WindowFlipCapture()

    func capture(front: UInt32, back: UInt32, rect: CGRect, padding: CGFloat) throws -> WindowFlipImages {
        try Task.checkCancellation()
        let first = try image(rect: .null, options: .optionIncludingWindow, id: front, trim: true)
        try Task.checkCancellation()
        let second = try image(rect: .null, options: .optionIncludingWindow, id: back, trim: true)
        try Task.checkCancellation()
        let background = try image(rect: rect.insetBy(dx: -padding, dy: -padding),
            options: .optionOnScreenBelowWindow, id: front, trim: false)
        try Task.checkCancellation()
        return WindowFlipImages(front: first, back: second, background: background)
    }

    private func image(rect: CGRect, options: CGWindowListOption, id: UInt32, trim: Bool) throws -> CGImage {
        try autoreleasepool {
            guard var image = CGWindowListCreateImage(rect, options, id, [.boundsIgnoreFraming, .nominalResolution]) else {
                throw CocoaError(.fileReadUnknown)
            }
            if trim, image.width > 2, image.height > 2,
               let cropped = image.cropping(to: CGRect(x: 1, y: 1, width: image.width - 2, height: image.height - 2)) {
                image = cropped
            }
            return try boundedWindowFlipImage(image)
        }
    }
}

/// Three retained images total at most roughly 24 MiB of RGBA pixels.
func boundedWindowFlipImage(_ image: CGImage) throws -> CGImage {
    let width = Double(image.width), height = Double(image.height)
    let scale = min(1, 2048 / max(width, height), sqrt(2_000_000 / (width * height)))
    guard scale < 1 else { return image }
    guard let context = CGContext(data: nil, width: max(1, Int(width * scale)), height: max(1, Int(height * scale)),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.coderInvalidValue) }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
    guard let output = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
    return output
}
