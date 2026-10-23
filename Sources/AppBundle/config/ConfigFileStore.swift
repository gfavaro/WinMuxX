import Foundation
import TOMLKit

/// A synchronous MainActor transaction writes validated bytes without suspending.
/// Structured edits always start from the latest disk text, not a view model's projection.
@MainActor
enum ConfigFileStore {
    static let backupCount = 5

    struct Conflict: LocalizedError {
        var errorDescription: String? { "The config changed on disk. Reload it and retry your edit." }
    }

    static func read(_ url: URL) throws -> String? {
        do { return try String(contentsOf: url, encoding: .utf8) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
    }

    /// Foundation leaves a dangling final symlink unresolved. Bootstrap must write
    /// through it so a dotfiles link survives until its target becomes available.
    private static func writableTarget(for url: URL, depth: Int = 0) -> URL {
        guard depth < 32,
              let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return url.resolvingSymlinksInPath().standardizedFileURL
        }
        let target = destination.hasPrefix("/")
            ? URL(filePath: destination)
            : url.deletingLastPathComponent().appending(path: destination)
        return writableTarget(for: target.standardizedFileURL, depth: depth + 1)
    }

    @discardableResult
    static func edit(at url: URL, _ transform: (String) throws -> String) throws -> Bool {
        let target = writableTarget(for: url)
        for _ in 0..<3 {
            let original = try read(target)
            let rendered = try transform(original ?? starterConfigText())
            try validate(rendered)
            guard try read(target) == original else { continue }
            return try commit(rendered, original: original, to: target)
        }
        throw Conflict()
    }

    @discardableResult
    static func replace(at url: URL, text: String, expected: String?) throws -> Bool {
        let target = writableTarget(for: url)
        try validate(text)
        guard try read(target) == expected else { throw Conflict() }
        return try commit(text, original: expected, to: target)
    }

    static func installBootstrap(_ text: String, at url: URL, legacy: Bool = false) throws {
        let target = writableTarget(for: url)
        guard try read(target) == nil else { return }
        if legacy { _ = try TOMLTable(string: text) } else { try validate(text) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writePrivateData(Data(text.utf8), to: target)
    }

    private static func validate(_ text: String) throws {
        let parsed = parseConfig(text)
        guard parsed.errors.isEmpty else {
            throw NSError(domain: "WinMux.Config", code: 1,
                userInfo: [NSLocalizedDescriptionKey: parsed.errors.map(\.description).joined(separator: "\n")])
        }
    }

    private static func commit(_ text: String, original: String?, to target: URL) throws -> Bool {
        guard text != original else { return false }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let original {
            for index in stride(from: backupCount, through: 2, by: -1) {
                let previous = target.appendingPathExtension("backup.\(index - 1)")
                if FileManager.default.fileExists(atPath: previous.path) {
                    try writePrivateData(Data(contentsOf: previous), to: target.appendingPathExtension("backup.\(index)"))
                }
            }
            try writePrivateData(Data(original.utf8), to: target.appendingPathExtension("backup.1"))
        }
        // Re-check after backup I/O as well: never knowingly overwrite an external edit.
        guard try read(target) == original else { throw Conflict() }
        try writePrivateData(Data(text.utf8), to: target)
        return true
    }
}

/// A retained raw editor draft keeps the baseline it was actually edited against.
struct RawConfigDraft: Equatable {
    let text: String
    let baseline: String?
}
