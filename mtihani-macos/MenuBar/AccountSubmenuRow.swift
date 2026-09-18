import AppKit
import SwiftUI

/// A plain account row with a native, keyboard-accessible menu opening at its
/// trailing edge, rather than an NSPopUpButton-style dropdown.
struct AccountSubmenuRow: NSViewRepresentable {
    let name: String
    let email: String
    let manageAccount: @MainActor () -> Void
    let switchAccount: @MainActor () -> Void
    let signOut: @MainActor () -> Void
    let trackingChanged: @MainActor @Sendable (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = AccountMenuButton(
            title: "", target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "person", accessibilityDescription: nil)!)
        let title = NSTextField(labelWithString: name)
        title.tag = 1
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chevron = NSImageView(
            image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)!)
        let row = NSStackView(views: [icon, title, chevron])
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            chevron.widthAnchor.constraint(equalToConstant: 10),
        ])
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        (button.viewWithTag(1) as? NSTextField)?.stringValue = name
        button.setAccessibilityLabel(name)
        button.setAccessibilityHelp("Open account submenu")
        button.toolTip = name
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: AccountSubmenuRow
        init(_ parent: AccountSubmenuRow) { self.parent = parent }

        func makeMenu() -> NSMenu {
            let menu = NSMenu(title: "Account")
            let email = NSMenuItem(title: parent.email, action: nil, keyEquivalent: "")
            email.isEnabled = false
            menu.addItem(email)
            menu.addItem(.separator())
            for (title, action) in [
                ("Manage account", #selector(manage)),
                ("Switch account", #selector(switchAccount)),
                ("Sign out", #selector(signOut)),
            ] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            return menu
        }

        @objc func showMenu(_ sender: NSButton) {
            parent.trackingChanged(true)
            defer { parent.trackingChanged(false) }
            makeMenu().popUp(
                positioning: nil,
                at: NSPoint(x: sender.bounds.maxX + 6, y: sender.bounds.maxY), in: sender)
        }
        @objc private func manage() { parent.manageAccount() }
        @objc private func switchAccount() { parent.switchAccount() }
        @objc private func signOut() { parent.signOut() }
    }
}

private final class AccountMenuButton: NSButton {
    // Keep the icon, label and chevron part of one clickable/focusable row.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
}
