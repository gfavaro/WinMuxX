@testable import AppBundle
import Common
import XCTest

final class ForkIdentityTest: XCTestCase {
    func testForkIdentityDoesNotUseUpstreamSocketOrState() {
        XCTAssertEqual(stableWinMuxAppId, "com.gfavaro.winmuxx")
        XCTAssertTrue(winMuxAppId.hasPrefix(stableWinMuxAppId))
        XCTAssertTrue(winMuxAppName.hasPrefix("WinMuxX"))
        XCTAssertTrue(socketPath.contains(winMuxAppId))
        XCTAssertFalse(socketPath.contains("com.zimengxiong"))
        XCTAssertEqual(forkRepositoryURL, "https://github.com/gfavaro/WinMuxX")
    }

    func testForkConfigurationHasAnIndependentOwnedDirectory() {
        XCTAssertEqual(generatedConfigDirectoryName, "winmuxx")
        XCTAssertEqual(generatedConfigFileName, "winmux.toml")
        XCTAssertEqual(generatedConfigUrl().deletingLastPathComponent().lastPathComponent, "winmuxx")
        XCTAssertTrue(legacyConfigCandidateUrls().contains { $0.path.hasSuffix("/winmux/winmux.toml") })
        XCTAssertTrue(legacyConfigCandidateUrls().first?.path.hasSuffix("/winmux-gf/winmux.toml") == true)
    }

    func testAppRenameRetainsTheExistingPersonalForkStateDirectory() {
        XCTAssertEqual(winMuxAppSupportDirectoryName, "WinMux-GF")
    }
}
