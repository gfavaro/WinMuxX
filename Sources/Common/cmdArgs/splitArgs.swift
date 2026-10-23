import Foundation

extension String {
    // Input: "  foo   bar ". Output: ["foo", "bar"]
    // Input "foo 'bar baz'". Output ["foo", "bar baz"]
    public func splitArgs() -> Parsed<[String]> {
        var result: [String] = []
        var arg: String = ""
        var state: State = .parseArgWhitespaceSeparator
        let scalars = Array(self.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            switch state { // State machine
                case .parseArgWhitespaceSeparator:
                    if scalar == "\"" || scalar == "\'" {
                        state = .parseArg(quoteChar: Character(scalar))
                    } else if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                        state = .parseArg(quoteChar: nil)
                        arg.unicodeScalars.append(scalar)
                    }
                case .parseArg(let quoteChar):
                    if let quoteChar, scalar == "\\", index + 1 < scalars.count,
                       (scalars[index + 1] == quoteChar.unicodeScalars.first || scalars[index + 1] == "\\") {
                        arg.unicodeScalars.append(scalars[index + 1])
                        index += 1
                    } else if quoteChar?.unicodeScalars.first == scalar {
                        result.append(arg)
                        arg = ""
                        state = .parseArgWhitespaceSeparator
                    } else if quoteChar == nil && CharacterSet.whitespacesAndNewlines.contains(scalar) {
                        result.append(arg)
                        state = .parseArgWhitespaceSeparator
                        arg = ""
                    } else if quoteChar == nil && (scalar == "\'" || scalar == "\"") {
                        return .failure("Unexpected quote \(scalar) in argument '\(arg)'")
                    } else {
                        arg.unicodeScalars.append(scalar)
                    }
            }
            index += 1
        }
        if case .parseArg(let quoteChar) = state {
            if let quoteChar {
                return .failure("Last quote \(quoteChar) isn't closed")
            } else {
                result.append(arg)
            }
        }
        return .success(result)
    }
}

private enum State {
    case parseArg(quoteChar: Character?)
    case parseArgWhitespaceSeparator
}

extension [String] {
    public func joinArgs() -> String {
        self.map {
            let containsWhitespaces = $0.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            let containsSingleQuote = $0.contains("'")
            let containsDoubleQuote = $0.contains("\"")
            return switch true {
                case containsDoubleQuote && !containsSingleQuote:
                    $0.quoted(with: "'")
                case containsSingleQuote && !containsDoubleQuote:
                    $0.quoted(with: "\"")
                case containsSingleQuote && containsDoubleQuote:
                    $0.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").quoted(with: "\"")
                case containsWhitespaces:
                    $0.quoted(with: "'")
                default:
                    $0
            }
        }.joined(separator: " ")
    }
}
