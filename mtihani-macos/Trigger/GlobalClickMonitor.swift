//
//  GlobalClickMonitor.swift
//  mtihani-macos
//

import AppKit
import OSLog

/// Observes global left-button mouse-down events and reports the configured
/// native click count without consuming or replacing the original events.
@MainActor
final class GlobalClickMonitor: CaptureTriggerMonitor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.victorjambo.mtihani-macos",
        category: "trigger"
    )

    private let requiredClickCount: @MainActor @Sendable () -> Int
    private let onTrigger: @MainActor @Sendable () -> Void
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    var isMonitoring: Bool {
        globalEventMonitor != nil && localEventMonitor != nil
    }

    init(
        requiredClickCount: @escaping @MainActor @Sendable () -> Int = { 3 },
        onTrigger: @escaping @MainActor @Sendable () -> Void
    ) {
        self.requiredClickCount = requiredClickCount
        self.onTrigger = onTrigger
    }

    @discardableResult
    func start() -> Bool {
        guard !isMonitoring else {
            return true
        }

        let requiredClickCount = requiredClickCount
        let onTrigger = onTrigger

        guard let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown,
            handler: { event in
                let interpreter = TripleClickInterpreter(
                    requiredClickCount: requiredClickCount()
                )
                guard interpreter.isTrigger(button: .left, clickCount: event.clickCount) else {
                    return
                }

                Task { @MainActor in
                    onTrigger()
                }
            }
        ) else {
            Self.logger.error("Unable to register the global click monitor")
            return false
        }

        guard let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown,
            handler: { event in
                let interpreter = TripleClickInterpreter(
                    requiredClickCount: requiredClickCount()
                )
                if interpreter.isTrigger(button: .left, clickCount: event.clickCount) {
                    Task { @MainActor in
                        onTrigger()
                    }
                }
                return event
            }
        ) else {
            NSEvent.removeMonitor(globalMonitor)
            Self.logger.error("Unable to register the local click monitor")
            return false
        }

        globalEventMonitor = globalMonitor
        localEventMonitor = localMonitor
        Self.logger.info("Global click monitoring started")
        return true
    }

    func stop() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        Self.logger.info("Global click monitoring stopped")
    }

    deinit {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
    }
}
