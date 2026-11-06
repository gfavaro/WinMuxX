@testable import AppBundle
import XCTest

@MainActor
final class ConfigurationReferenceTest: WorkspaceTestCase {

    func testExamplesParseAsIndependentConfigurationSnippets() {
        for section in configurationReferenceSections {
            guard let example = section.example else { continue }
            let result = parseConfig("config-version = 2\n" + example)
            XCTAssertTrue(result.errors.isEmpty, "\(section.id): \(result.errors)")
        }
    }

    func testReferenceUsesAppDefaultsInsteadOfPersonalValues() {
        XCTAssertFalse(configurationReferenceSections.contains { $0.id == "padding" })
    }
}
