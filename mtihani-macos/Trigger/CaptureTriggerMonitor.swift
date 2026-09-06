//
//  CaptureTriggerMonitor.swift
//  mtihani-macos
//

import Foundation

/// Owns the lifecycle of a global capture trigger.
@MainActor
protocol CaptureTriggerMonitor: AnyObject {
    var isMonitoring: Bool { get }

    /// Starts observing the configured trigger.
    ///
    /// - Returns: `true` when monitoring is active, including when it was
    ///   already active; otherwise `false` when registration fails.
    @discardableResult
    func start() -> Bool

    /// Stops observing and releases the underlying system monitor.
    func stop()
}
