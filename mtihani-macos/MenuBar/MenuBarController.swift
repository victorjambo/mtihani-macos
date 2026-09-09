import AppKit
import Combine
import SwiftUI

/// Owns the native menu-bar item and presents the existing SwiftUI controls in
/// an AppKit popover. Keeping presentation in AppKit avoids relying on
/// `MenuBarExtra` to activate an LSUIElement application.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let appState: AppState
    private let updateManager: UpdateManager
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(appState: AppState, updateManager: UpdateManager) {
        self.appState = appState
        self.updateManager = updateManager
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
        popover.delegate = self
        popover.animates = true
        popover.contentSize = NSSize(width: 300, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                appState: appState,
                updateManager: updateManager,
                openSettings: { [weak self] in
                    self?.showSettings()
                },
                closePopover: { [weak self] in
                    self?.popover.performClose(nil)
                }
            )
        )
    }

    func popoverDidShow(_ notification: Notification) {
        stopMonitoringOutsideClicks()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.window === self.popover.contentViewController?.view.window {
                return event
            }
            // The status button handles its own toggle on mouse-up. Closing on
            // mouse-down here would cause that toggle to reopen the popover.
            if let button = self.statusItem.button,
                event.window === button.window,
                button.bounds.contains(button.convert(event.locationInWindow, from: nil))
            {
                return event
            }
            self.popover.performClose(nil)
            return event
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitoringOutsideClicks()
    }

    private func stopMonitoringOutsideClicks() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
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
            .combineLatest(updateManager.$state)
            .sink { [weak self] state, updateState in
                self?.updateStatusItem(for: state, updateAvailable: updateState.updateAvailable)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(for state: CaptureState, updateAvailable: Bool = false) {
        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(systemSymbolName: symbolName(for: state), accessibilityDescription: state.title)
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = false
        // Retain the capture status image while making background update alerts discoverable.
        button.title = updateAvailable ? " ·" : ""
        button.imagePosition = updateAvailable ? .imageLeading : .imageOnly
        statusItem.length = updateAvailable ? NSStatusItem.variableLength : NSStatusItem.squareLength
        let label = "Mtihani – \(state.title)" + (updateAvailable ? " – Update available" : "")
        button.toolTip = label
        button.setAccessibilityLabel(label)
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

    private func showSettings() {
        popover.performClose(nil)

        let windowController: NSWindowController
        if let settingsWindowController {
            windowController = settingsWindowController
        } else {
            let hostingController = NSHostingController(
                rootView: SettingsView(appState: appState, updateManager: updateManager)
            )
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Mtihani Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()

            windowController = NSWindowController(window: window)
            settingsWindowController = windowController
        }

        NSApp.activate()
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    deinit {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
