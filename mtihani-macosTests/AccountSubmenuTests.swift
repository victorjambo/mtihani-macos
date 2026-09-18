import AppKit
import XCTest

@testable import mtihani_macos

@MainActor
final class AccountSubmenuTests: XCTestCase {
    func testNativeSubmenuContainsAccountActionsAndDispatchesThem() {
        var actions: [String] = []
        let row = AccountSubmenuRow(
            name: "Example User", email: "user@example.com",
            manageAccount: { actions.append("manage") },
            switchAccount: { actions.append("switch") },
            signOut: { actions.append("signout") }, trackingChanged: { _ in })
        let coordinator = row.makeCoordinator()
        let menu = coordinator.makeMenu()
        XCTAssertEqual(
            menu.items.map(\.title),
            ["user@example.com", "", "Manage account", "Switch account", "Sign out"])
        XCTAssertFalse(menu.items[0].isEnabled)
        for index in 2...4 { menu.performActionForItem(at: index) }
        XCTAssertEqual(actions, ["manage", "switch", "signout"])
    }
}
