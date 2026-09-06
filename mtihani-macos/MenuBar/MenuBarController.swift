import AppKit
import Combine
import SwiftUI

/// Owns the native menu-bar item and presents the existing SwiftUI controls in
/// an AppKit popover. Keeping presentation in AppKit avoids relying on
/// `MenuBarExtra` to activate an LSUIElement application.
@MainActor
final class MenuBarController: NSObject {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        popover = NSPopover()
        super.init()

        configurePopover()
        configureStatusItem()
        observeCaptureState()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 300, height: 390)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(appState: appState)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        updateStatusItem(for: appState.captureCoordinator.state)
    }

    private func observeCaptureState() {
        appState.captureCoordinator.$state
            .sink { [weak self] state in
                self?.updateStatusItem(for: state)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(for state: CaptureState) {
        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(systemSymbolName: symbolName(for: state), accessibilityDescription: state.title)
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Mtihani – \(state.title)"
        button.setAccessibilityLabel("Mtihani – \(state.title)")
    }

    private func symbolName(for state: CaptureState) -> String {
        switch state {
        case .idle:
            "circle.fill"
        case .capturing:
            "camera.viewfinder"
        case .uploading:
            "arrow.up.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(
                relativeTo: sender.bounds,
                of: sender,
                preferredEdge: .minY
            )
        }
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
