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

    /// The parser is the source of truth; the editor schema follows it key for key.
    func testSchemaListsExactlyTheParserRootKeys() throws {
        let data = try Data(contentsOf: projectRoot.appending(path: "docs/schemas/winmuxx.schema.json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys).subtracting(configRootKeys).sorted(), [], "Schema keys the parser rejects")
        XCTAssertEqual(configRootKeys.subtracting(properties.keys).sorted(), [], "Parser keys missing from the schema")
    }
}
