import AppKit

func paletteQuickSelectIndex(characters: String?, modifiers: NSEvent.ModifierFlags,
                             hasMarkedText: Bool) -> Int? {
    guard !hasMarkedText,
          modifiers.intersection([.command, .option, .control, .shift]) == .command,
          let digit = characters.flatMap(Int.init), (1...9).contains(digit) else { return nil }
    return digit - 1
}
