@testable import AppBundle
import Foundation
import XCTest

private struct ConfigFixtureExpectation: Decodable {
    let parser: Bool
    let schema: Bool
}

@MainActor
final class ConfigurationSchemaFixturesTest: XCTestCase {
    func testSharedConfigFixturesMatchParserExpectations() throws {
        let directory = projectRoot.appending(path: "resources/test-fixtures/config-schema")
        let expectationData = try Data(contentsOf: directory.appending(path: "expectations.json"))
        let expectations = try JSONDecoder().decode([String: ConfigFixtureExpectation].self, from: expectationData)
        let fixtureNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".toml") }
            .sorted()

        XCTAssertEqual(Set(fixtureNames), Set(expectations.keys), "Every TOML fixture needs explicit parser and schema expectations")
        for name in fixtureNames {
            let source = try String(contentsOf: directory.appending(path: name), encoding: .utf8)
            let errors = parseConfig(source).errors
            let expectation = try XCTUnwrap(expectations[name], "Missing expectation for \(name)")
            XCTAssertEqual(errors.isEmpty, expectation.parser, "Unexpected parser outcome for \(name): \(errors.map(\.description).joined(separator: "\n"))")
        }
    }
}
