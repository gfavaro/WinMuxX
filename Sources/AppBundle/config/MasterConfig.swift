import CoreGraphics
import Common
import TOMLKit

enum MasterSide: String, CaseIterable {
    case left, right, top, bottom
    var orientation: Orientation { self == .left || self == .right ? .h : .v }
    var isReversed: Bool { self == .right || self == .bottom }
}

struct MasterConfig: ConvenienceCopyable, Equatable {
    var size = 0.6
    var side = MasterSide.left
    var stackLayout = Layout.tiles
    /// Main windows side by side on a display at least twice as wide as tall.
    var ultrawideMains = 1
}

/// A display this much wider than tall counts as ultrawide (21:9 is about 2.4).
let ultrawideAspectRatio: CGFloat = 2

func parseMaster(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> MasterConfig {
    parseTable(raw, MasterConfig(), [
        "size": Parser(\.size) { raw, trace in
            (raw.double ?? raw.int.map(Double.init)).orFailure(.semantic(trace, "Must be a number between 0.1 and 0.9"))
                .filter(.semantic(trace, "Must be a number between 0.1 and 0.9")) { $0.isFinite && (0.1...0.9).contains($0) }
        },
        "side": Parser(\.side) { raw, trace in
            parseString(raw, trace).flatMap { MasterSide(rawValue: $0).orFailure(.semantic(trace, "Expected left, right, top or bottom")) }
        },
        "ultrawide-mains": Parser(\.ultrawideMains) { raw, trace in
            raw.int.orFailure(.semantic(trace, "Expected 1 or 2")).filter(.semantic(trace, "Expected 1 or 2")) { $0 == 1 || $0 == 2 }
        },
        "stack-layout": Parser(\.stackLayout) { raw, trace in
            parseString(raw, trace).flatMap { value in
                value.parseLayout().orFailure(.semantic(trace, "Expected tiles or accordion"))
                    .filter(.semantic(trace, "Expected tiles or accordion")) { $0 == .tiles || $0 == .stacked }
            }
        },
    ], trace, &errors)
}
