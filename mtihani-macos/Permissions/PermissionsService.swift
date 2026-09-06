import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog

enum ScreenRecordingPermissionState: String, Equatable, Sendable {
    case unknown
    case granted
    case denied
}

@MainActor
protocol PermissionsServicing: AnyObject {
    var screenRecordingState: ScreenRecordingPermissionState { get }

    @discardableResult
    func refreshScreenRecordingPermission() -> ScreenRecordingPermissionState

    @discardableResult
    func requestScreenRecordingPermissionIfNeeded() -> ScreenRecordingPermissionState

    func openScreenRecordingSettings()
}

@MainActor
final class PermissionsService: ObservableObject, PermissionsServicing {
    typealias PermissionCheck = () -> Bool
    typealias PermissionRequest = () -> Bool
    typealias SettingsOpener = (URL) -> Bool

    @Published private(set) var screenRecordingState: ScreenRecordingPermissionState
    @Published private(set) var hasRequestedScreenRecordingThisLaunch = false

    private let checkScreenRecordingAccess: PermissionCheck
    private let requestScreenRecordingAccess: PermissionRequest
    private let openSettingsURL: SettingsOpener
    private let logger: Logger

    init(
        checkScreenRecordingAccess: @escaping PermissionCheck = {
            CGPreflightScreenCaptureAccess()
        },
        requestScreenRecordingAccess: @escaping PermissionRequest = {
            CGRequestScreenCaptureAccess()
        },
        openSettingsURL: @escaping SettingsOpener = { url in
            NSWorkspace.shared.open(url)
        },
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.victorjambo.mtihani-macos",
            category: "permissions"
        )
    ) {
        self.checkScreenRecordingAccess = checkScreenRecordingAccess
        self.requestScreenRecordingAccess = requestScreenRecordingAccess
        self.openSettingsURL = openSettingsURL
        self.logger = logger
        screenRecordingState = checkScreenRecordingAccess() ? .granted : .denied
    }

    @discardableResult
    func refreshScreenRecordingPermission() -> ScreenRecordingPermissionState {
        let refreshedState: ScreenRecordingPermissionState =
            checkScreenRecordingAccess() ? .granted : .denied

        if refreshedState != screenRecordingState {
            logger.info("Screen Recording permission state changed to \(refreshedState.rawValue, privacy: .public)")
            screenRecordingState = refreshedState
        }

        return screenRecordingState
    }

    @discardableResult
    func requestScreenRecordingPermissionIfNeeded() -> ScreenRecordingPermissionState {
        if refreshScreenRecordingPermission() == .granted {
            return .granted
        }

        guard !hasRequestedScreenRecordingThisLaunch else {
            logger.debug("Skipping a repeated Screen Recording permission request this launch")
            return screenRecordingState
        }

        hasRequestedScreenRecordingThisLaunch = true
        logger.notice("Requesting Screen Recording permission")

        screenRecordingState = requestScreenRecordingAccess() ? .granted : .denied
        logger.info("Screen Recording permission request completed with state \(self.screenRecordingState.rawValue, privacy: .public)")
        return screenRecordingState
    }

    func openScreenRecordingSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            logger.error("Could not construct the Screen Recording settings URL")
            return
        }

        if openSettingsURL(settingsURL) {
            logger.info("Opened Screen Recording settings")
        } else {
            logger.error("macOS could not open Screen Recording settings")
        }
    }
}
