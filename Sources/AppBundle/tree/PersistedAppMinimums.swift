import AppKit
import Combine

struct AppMinimumEvidence: Equatable, Identifiable {
    let bundleId: String
    let size: CGSize
    var id: String { bundleId }
    var unknownAxes: [String] {
        [size.width == 0 ? "width" : nil, size.height == 0 ? "height" : nil].compactMap { $0 }
    }
}

struct MinimumEvidenceGeneration: Equatable, Codable {
    let global: UInt64
    let app: UInt64
}

/// Confirmed evidence only. Invalid persisted values never constrain a layout.
@MainActor final class PersistedAppMinimums: ObservableObject {
    static let shared = PersistedAppMinimums(defaults: .standard)
    private let defaults: UserDefaults
    private let key = "confirmedAppMinimumSizes.v2"
    private let globalGenerationKey = "confirmedAppMinimums.globalResetGeneration.v1"
    private let appGenerationsKey = "confirmedAppMinimums.appResetGenerations.v1"
    private var sizes: [String: [Double]]
    private var globalGeneration: UInt64
    private var appGenerations: [String: UInt64]
    @Published private(set) var revision: UInt64 = 0

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // Earlier evidence could mistake a repeated grid snap for a minimum.
        defaults.removeObject(forKey: "confirmedAppMinimumSizes.v1")
        sizes = defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        globalGeneration = UInt64(defaults.string(forKey: globalGenerationKey) ?? "0") ?? 0
        appGenerations = (defaults.dictionary(forKey: appGenerationsKey) as? [String: String] ?? [:]).mapValues { UInt64($0) ?? 0 }
    }

    func size(for bundleId: String?) -> CGSize? {
        guard let bundleId, let values = sizes[bundleId], values.count == 2,
              values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 100_000 }) else { return nil }
        let size = CGSize(width: values[0], height: values[1])
        return size == .zero ? nil : size
    }

    var isEmpty: Bool { sizes.isEmpty }

    var snapshot: [AppMinimumEvidence] {
        sizes.keys.sorted().compactMap { bundleId in
            guard let size = size(for: bundleId) else { return nil }
            return AppMinimumEvidence(bundleId: bundleId, size: size)
        }
    }

    func evidenceGeneration(for bundleId: String?) -> MinimumEvidenceGeneration {
        MinimumEvidenceGeneration(global: globalGeneration, app: bundleId.map { appGenerations[$0, default: 0] } ?? 0)
    }

    func acceptsEvidence(_ generation: MinimumEvidenceGeneration, for bundleId: String?, savedBundleId: String?) -> Bool {
        let current = evidenceGeneration(for: bundleId)
        if let savedBundleId, savedBundleId != bundleId { return false }
        if savedBundleId == nil && (generation.global != 0 || generation.app != 0) { return false }
        return generation == current
    }

    func remember(_ size: CGSize, for bundleId: String?) {
        guard let bundleId, !bundleId.isEmpty,
              size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0 else { return }
        let next: [Double]? = size == .zero ? nil : [Double(size.width), Double(size.height)]
        guard sizes[bundleId] != next else { return }
        sizes[bundleId] = next
        persistSizes()
        revision &+= 1
    }

    func forget(_ bundleId: String) {
        guard sizes[bundleId] != nil || appGenerations[bundleId] == nil else { return }
        sizes.removeValue(forKey: bundleId)
        appGenerations[bundleId, default: 0] &+= 1
        persistSizes()
        persistGenerations()
        for window in MacWindow.allWindows where window.macApp.rawAppBundleId == bundleId { window.resetLearnedMinimum() }
        revision &+= 1
    }

    func forgetAll() {
        sizes = [:]
        globalGeneration &+= 1
        appGenerations = [:]
        persistSizes()
        persistGenerations()
        for window in MacWindow.allWindows { window.resetLearnedMinimum() }
        revision &+= 1
    }

    func reset() { forgetAll() }

    private func persistSizes() {
        if sizes.isEmpty { defaults.removeObject(forKey: key) }
        else { defaults.set(sizes, forKey: key) }
    }

    private func persistGenerations() {
        defaults.set(String(globalGeneration), forKey: globalGenerationKey)
        defaults.set(appGenerations.mapValues(String.init), forKey: appGenerationsKey)
    }
}
