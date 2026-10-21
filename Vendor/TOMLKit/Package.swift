// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TOMLKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TOMLKit", targets: ["TOMLKit"])],
    targets: [
        .target(name: "CTOML", cxxSettings: [.define("TOML_EXCEPTIONS", to: "1")]),
        .target(name: "TOMLKit", dependencies: ["CTOML"]),
        .executableTarget(name: "TOMLLeakProbe", dependencies: ["TOMLKit"], path: "Tests/LeakProbe"),
    ],
    swiftLanguageModes: [.v5],
    cLanguageStandard: .c99,
    cxxLanguageStandard: .cxx17
)
