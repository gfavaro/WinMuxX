import AppKit

/// Confirmed evidence only. Invalid persisted values never constrain a layout.
@MainActor final class PersistedAppMinimums {
    static let shared = PersistedAppMinimums(defaults: .standard)
    private let defaults: UserDefaults
    private let key = "confirmedAppMinimumSizes.v2"
    private var sizes: [String: [Double]]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // Earlier evidence could mistake a repeated grid snap for a minimum.
        defaults.removeObject(forKey: "confirmedAppMinimumSizes.v1")
        sizes = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }

    func size(for bundleId: String?) -> CGSize? {
        guard let bundleId, let values = sizes[bundleId], values.count == 2,
              values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100_000 }) else { return nil }
        let size = CGSize(width: values[0], height: values[1])
        return size == .zero ? nil : size
    }

    var isEmpty: Bool { sizes.isEmpty }

    func remember(_ size: CGSize, for bundleId: String?) {
        guard let bundleId, !bundleId.isEmpty,
              size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0 else { return }
        let next: [Double]? = size == .zero ? nil : [Double(size.width), Double(size.height)]
        guard sizes[bundleId] != next else { return }
        sizes[bundleId] = next
        defaults.set(sizes, forKey: key)
    }

    func reset() {
        sizes = [:]
        defaults.removeObject(forKey: key)
    }
}
