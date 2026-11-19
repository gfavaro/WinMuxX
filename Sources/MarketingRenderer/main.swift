import Foundation

/// `winmux-marketing-renderer <directory>` writes one PNG per scene and the sidebar looks;
/// `--scene <name> <file>` writes a single scene.
@main
struct MarketingRendererCommand {
    @MainActor
    static func main() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let index = arguments.firstIndex(of: "--scene") {
            guard arguments.indices.contains(index + 2), let scene = MarketingScene(rawValue: arguments[index + 1]) else {
                let names = MarketingScene.allCases.map(\.rawValue).joined(separator: ", ")
                FileHandle.standardError.write(Data("usage: --scene <\(names)> <file.png>\n".utf8))
                exit(2)
            }
            let output = URL(fileURLWithPath: arguments[index + 2], relativeTo: root).standardizedFileURL
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await renderMarketingScene(scene, to: output)
            print(output.path)
            return
        }
        arguments.removeAll { $0.hasPrefix("--") }
        let directory = URL(fileURLWithPath: arguments.first ?? ".release/marketing", relativeTo: root).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scene in MarketingScene.allCases {
            let output = directory.appendingPathComponent("\(scene.rawValue).png")
            try await renderMarketingScene(scene, to: output)
            print(output.path)
        }
        try await renderWinMuxSidebarAppearanceProofs(to: directory.appendingPathComponent("sidebar"))
        print(directory.appendingPathComponent("sidebar").path)
    }
}
