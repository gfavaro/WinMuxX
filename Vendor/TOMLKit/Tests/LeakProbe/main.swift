import TOMLKit

// A standalone process keeps AppKit/framework lifetime allocations out of leaks.
// No user configuration or native windows are accessed.
let document = """
name = "fixture"
enabled = true
count = 12
ratio = 1.5
date = 2026-10-17
time = 12:34:56
stamp = 2026-10-17T12:34:56-03:00
local = 2026-10-17T12:34:56
items = [{ name = "nested", values = [1, 2, 3] }]
[nested]
text = "retained child"
"""

struct Encoded: Codable { let name: String; let values: [Int] }

@inline(never)
func exercise() throws {
    let table = try TOMLTable(string: document)
    precondition(table["name"]?.string == "fixture")
    precondition(table["enabled"]?.bool == true)
    precondition(table["count"]?.int == 12)
    precondition(table["ratio"]?.double == 1.5)
    _ = table["date"]?.date?.debugDescription
    _ = table["time"]?.time?.debugDescription
    _ = table["stamp"]?.dateTime?.debugDescription
    _ = table["local"]?.dateTime?.debugDescription
    _ = table.keys
    _ = table.values
    for (_, value) in table { _ = value.debugDescription }
    for format: ConversionFormat in [.toml, .json, .yaml] { _ = table.convert(to: format) }
    let child = try TOMLTable(string: document)["nested"]!.table!
    precondition(child["text"]?.string == "retained child")
    let array = TOMLArray(["one", 2, true])
    _ = array.remove(at: 1)
    let replacement: TOMLArray = [1, 2]
    array[0] = replacement
    _ = array.debugDescription
    _ = table.remove(at: "nested")
    let encoded = try TOMLTable(Encoded(name: "roundtrip", values: [1, 2, 3]))
    let decoded = try TOMLDecoder().decode(Encoded.self, from: encoded)
    precondition(decoded.name == "roundtrip")
    do { _ = try TOMLTable(string: "invalid = [") ; preconditionFailure("Expected parse error") }
    catch is TOMLParseError {}
}

let arguments = Array(CommandLine.arguments.dropFirst())
precondition(arguments.count <= 1, "Usage: TOMLLeakProbe [iterations]")
let iterations = arguments.first.flatMap(Int.init) ?? (arguments.isEmpty ? 1_000 : 0)
precondition((1...1_000_000).contains(iterations), "iterations must be in 1...1000000")
for _ in 0..<iterations { try exercise() }
print("Completed \(iterations) TOML parse/read/encode/error cycles")
