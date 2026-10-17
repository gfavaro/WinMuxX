import XCTest
@testable import TOMLKit

final class TomlOwnershipTest: XCTestCase {
    func testNestedValueRetainsDocumentUntilLastViewIsReleased() throws {
        var root: TOMLTable? = try TOMLTable(string: "[nested]\ntext = 'alive'")
        weak var owner = root!.storage
        var child: TOMLValue? = root!["nested"]?["text"]
        root = nil
        XCTAssertNotNil(owner)
        XCTAssertEqual(child?.string, "alive")
        child = nil
        XCTAssertNil(owner)
    }

    func testNestedArrayAndTableViewsShareDocumentOwner() throws {
        var root: TOMLTable? = try TOMLTable(string: "items = [{ name = 'nested' }]")
        weak var owner = root!.storage
        var array = root!["items"]!.array
        var table = array![0].table
        XCTAssertTrue(array!.storage === root!.storage)
        XCTAssertTrue(table!.storage === root!.storage)
        root = nil
        array = nil
        XCTAssertEqual(table?["name"]?.string, "nested")
        XCTAssertNotNil(owner)
        table = nil
        XCTAssertNil(owner)
    }

    func testLiteralAndEncodedTemporariesOwnTheirNativeRoots() throws {
        var value: TOMLValue? = ["nested": ["name": "literal"]]
        weak var owner = value!.storage
        XCTAssertEqual(value?["nested"]?["name"]?.string, "literal")
        value = nil
        XCTAssertNil(owner)

        struct Fixture: Codable, Equatable { let name: String; let values: [Int] }
        let fixture = Fixture(name: "encoded", values: [1, 2, 3])
        var encoded: TOMLTable? = try TOMLTable(fixture)
        weak var encodedOwner = encoded!.storage
        XCTAssertEqual(try TOMLDecoder().decode(Fixture.self, from: encoded!), fixture)
        encoded = nil
        XCTAssertNil(encodedOwner)
    }

    func testRemovedValuesOwnIndependentCopies() throws {
        var root: TOMLTable? = try TOMLTable(string: "[nested]\nname = 'removed'")
        weak var rootOwner = root!.storage
        var removed = root!.remove(at: "nested")?.tomlValue
        weak var removedOwner = removed!.storage
        XCTAssertFalse(removed!.storage === root!.storage)
        root = nil
        XCTAssertNil(rootOwner)
        XCTAssertEqual(removed?["name"]?.string, "removed")
        removed = nil
        XCTAssertNil(removedOwner)

        var array: TOMLArray? = ["first", "second"]
        var element = array!.remove(at: 0).tomlValue
        weak var arrayOwner = array!.storage
        array = nil
        XCTAssertNil(arrayOwner)
        XCTAssertEqual(element.string, "first")
        element = false
    }

    func testValuesRetainDocumentButKeysAreIndependentSwiftStrings() throws {
        var root: TOMLTable? = try TOMLTable(string: "name = 'value'\ncount = 3")
        weak var owner = root!.storage
        let keys = root!.keys
        var values = root!.values
        root = nil
        XCTAssertEqual(Set(keys), ["name", "count"])
        XCTAssertEqual(values.compactMap(\.string), ["value"])
        XCTAssertNotNil(owner)
        values.removeAll()
        XCTAssertNil(owner)
        XCTAssertEqual(Set(keys), ["name", "count"])
        XCTAssertEqual(TOMLTable().keys, [])
        XCTAssertTrue(TOMLTable().values.isEmpty)
    }

    func testRepeatedParseAndReleaseDoesNotRetainNativeOwner() throws {
        for _ in 0..<500 {
            var root: TOMLTable? = try TOMLTable(string: "items = [{ name = 'fixture', flags = [true, false] }]")
            weak var owner = root!.storage
            XCTAssertEqual(root!["items"]?[0]?["name"]?.string, "fixture")
            XCTAssertEqual(root!["items"]?[0]?["flags"]?[1]?.bool, false)
            _ = root!.convert()
            root = nil
            XCTAssertNil(owner)
        }
    }

    func testDateTimeOffsetsAndParseErrorsSurviveNativeBufferCleanup() throws {
        let root = try TOMLTable(string: "stamp = 2026-10-17T12:34:56-03:00\nlocal = 2026-10-17T12:34:56")
        let stamp = root["stamp"]!.dateTime!
        XCTAssertEqual(stamp.offset?.offset, -180)
        XCTAssertTrue(stamp.debugDescription.hasSuffix("-03:00"))
        XCTAssertNil(root["local"]!.dateTime!.offset)
        for _ in 0..<100 {
            XCTAssertThrowsError(try TOMLTable(string: "broken = [")) { error in
                guard let error = error as? TOMLParseError else { return XCTFail("Unexpected error") }
                XCTAssertFalse(error.description.isEmpty)
                XCTAssertEqual(error.source.begin.line, 1)
            }
        }
    }
}
