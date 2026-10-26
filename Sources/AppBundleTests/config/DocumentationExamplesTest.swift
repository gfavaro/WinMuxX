@testable import AppBundle
import XCTest

@MainActor
final class DocumentationExamplesTest: XCTestCase {
    func testWorkspaceDisplayRecipeParses() {
        let (_, errors) = parseConfig("""
            config-version = 2

            [workspace.Code]
            layout = 'master'

            [workspace.Code.display.'Built-in']
            layout = 'scrolling'
            """)
        XCTAssertTrue(errors.isEmpty, errors.map(\.description).joined(separator: "\n"))
    }

    func testActivationExclusionRecipeParses() {
        let (_, errors) = parseConfig("""
            config-version = 2
            [follow-app-activation]
            enabled = true
            exclude-apps = ['com.example.Utility']
            """)
        XCTAssertTrue(errors.isEmpty, errors.map(\.description).joined(separator: "\n"))
    }

    func testModifierSideRecipeParses() {
        let (_, errors) = parseConfig("""
            config-version = 2
            [modifiers]
            alt = 'left'
            """)
        XCTAssertTrue(errors.isEmpty, errors.map(\.description).joined(separator: "\n"))
    }

    func testDisplayHookRecipeParses() {
        let (_, errors) = parseConfig("""
            config-version = 2
            on-display-changed = 'exec-and-forget echo "$WINMUX_PREV_DISPLAYS -> $WINMUX_DISPLAYS"'
            """)
        XCTAssertTrue(errors.isEmpty, errors.map(\.description).joined(separator: "\n"))
    }
}
