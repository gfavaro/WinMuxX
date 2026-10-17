@testable import AppBundle
import AppKit
import XCTest
import Common

@MainActor final class ModifierSidesTest: XCTestCase {
    func testDefaultBothAcceptsEitherSideAndIgnoresCapsLock() {
        let sides = ModifierSides()
        for key in [TapModifierKey.leftAlt, .rightAlt] {
            XCTAssertTrue(sides.matches(.option, flags: [.option, .capsLock, key.deviceSpecificModifierFlag]))
        }
        XCTAssertFalse(sides.restricts(.option))
    }

    func testRestrictedSidesRequireOnlyTheSelectedPhysicalKey() {
        for side in [ModifierSides.Side.left, .right] {
            var sides = ModifierSides()
            sides.alt = side
            let selected: TapModifierKey = side == .left ? .leftAlt : .rightAlt
            let other: TapModifierKey = side == .left ? .rightAlt : .leftAlt
            XCTAssertTrue(sides.restricts(.option))
            XCTAssertTrue(sides.matches(.option, flags: [.option, selected.deviceSpecificModifierFlag]))
            XCTAssertFalse(sides.matches(.option, flags: [.option, other.deviceSpecificModifierFlag]))
            XCTAssertFalse(sides.matches(.option, flags: [.option, selected.deviceSpecificModifierFlag, other.deviceSpecificModifierFlag]))
            XCTAssertFalse(sides.matches(.option, flags: .option))
            XCTAssertFalse(sides.matches(.option, flags: [.option, .command, selected.deviceSpecificModifierFlag]))
            XCTAssertFalse(sides.restricts(.command))
        }
    }

    func testCombinedModifiersAndEverySide() {
        var sides = ModifierSides()
        sides.alt = .left
        sides.cmd = .right
        sides.ctrl = .left
        sides.shift = .right
        let flags: NSEvent.ModifierFlags = [.option, .command, .control, .shift,
            TapModifierKey.leftAlt.deviceSpecificModifierFlag, TapModifierKey.rightCmd.deviceSpecificModifierFlag,
            TapModifierKey.leftCtrl.deviceSpecificModifierFlag, TapModifierKey.rightShift.deviceSpecificModifierFlag]
        XCTAssertTrue(sides.matches([.option, .command, .control, .shift], flags: flags))
        XCTAssertFalse(sides.matches([.option, .command, .control, .shift], flags: flags.subtracting(TapModifierKey.rightShift.deviceSpecificModifierFlag)))
    }

    func testConfigValidationAndDefaults() {
        let valid = parseConfig("[modifiers]\nalt = 'left'\ncmd = 'right'")
        XCTAssertTrue(valid.errors.isEmpty, "\(valid.errors)")
        XCTAssertEqual(valid.config.modifierSides.alt, .left)
        XCTAssertEqual(valid.config.modifierSides.cmd, .right)
        XCTAssertEqual(valid.config.modifierSides.ctrl, .both)
        XCTAssertFalse(parseConfig("[modifiers]\nalt = 'either'").errors.isEmpty)
        XCTAssertFalse(parseConfig("[modifiers]\noption = 'left'").errors.isEmpty)
    }

    func testModeChangesReloadAndSuspensionUpdateFilteredLookup() async throws {
        let previousConfig = config
        let previousMode = activeMode
        let enabled = TrayMenuModel.shared.isEnabled
        defer {
            resetHotKeys()
            config = previousConfig
            activeMode = previousMode
            TrayMenuModel.shared.isEnabled = enabled
        }
        TrayMenuModel.shared.isEnabled = true
        config = parseConfig("""
        [modifiers]
        alt = 'left'
        [mode.main.binding]
        alt-h = []
        [mode.service.binding]
        alt-l = []
        """).config
        let left: NSEvent.ModifierFlags = [.option, TapModifierKey.leftAlt.deviceSpecificModifierFlag]
        let right: NSEvent.ModifierFlags = [.option, TapModifierKey.rightAlt.deviceSpecificModifierFlag]
        try await activateMode(mainModeId)
        XCTAssertNotNil(sideFilteredBinding(keyCode: 4, flags: left))
        XCTAssertNil(sideFilteredBinding(keyCode: 4, flags: right))
        setHotkeysSuspended(true)
        XCTAssertNil(sideFilteredBinding(keyCode: 4, flags: left))
        setHotkeysSuspended(false)
        try await activateMode("service")
        XCTAssertNil(sideFilteredBinding(keyCode: 4, flags: left))
        XCTAssertNotNil(sideFilteredBinding(keyCode: 37, flags: left))
        config.modifierSides.alt = .both
        try await activateMode("service")
        XCTAssertNil(sideFilteredBinding(keyCode: 37, flags: left))
    }
}
