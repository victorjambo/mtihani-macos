//
//  GlobalClickMonitor.swift
//  mtihani-macos
//

import AppKit
import OSLog

/// Observes global left-button mouse-down events and reports native
/// triple-clicks without consuming or replacing the original events.
@MainActor
final class GlobalClickMonitor: CaptureTriggerMonitor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.victorjambo.mtihani-macos",
        category: "trigger"
    )

    private let interpreter: TripleClickInterpreter
    private let onTrigger: @MainActor @Sendable () -> Void
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    var isMonitoring: Bool {
        globalEventMonitor != nil && localEventMonitor != nil
    }

    init(
        interpreter: TripleClickInterpreter = TripleClickInterpreter(),
        onTrigger: @escaping @MainActor @Sendable () -> Void
    ) {
        self.interpreter = interpreter
        self.onTrigger = onTrigger
    }

    @discardableResult
    func start() -> Bool {
        guard !isMonitoring else {
            return true
        }

        let interpreter = interpreter
        let onTrigger = onTrigger

        guard let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown,
            handler: { event in
                guard interpreter.isTrigger(button: .left, clickCount: event.clickCount) else {
                    return
                }

                Task { @MainActor in
                    onTrigger()
                }
            }
        ) else {
            Self.logger.error("Unable to register the global triple-click monitor")
            return false
        }

        guard let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown,
            handler: { event in
                if interpreter.isTrigger(button: .left, clickCount: event.clickCount) {
                    Task { @MainActor in
                        onTrigger()
                    }
                }
                return event
            }
        ) else {
            NSEvent.removeMonitor(globalMonitor)
            Self.logger.error("Unable to register the local triple-click monitor")
            return false
        }

        globalEventMonitor = globalMonitor
        localEventMonitor = localMonitor
        Self.logger.info("Global triple-click monitoring started")
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
        Self.logger.info("Global triple-click monitoring stopped")
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
