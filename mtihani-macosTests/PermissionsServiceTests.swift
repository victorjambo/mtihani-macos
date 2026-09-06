import XCTest
@testable import mtihani_macos

@MainActor
final class PermissionsServiceTests: XCTestCase {
    func testPermissionRequestOccursOnlyOncePerServiceInstance() {
        var requestCount = 0
        let service = PermissionsService(
            checkScreenRecordingAccess: { false },
            requestScreenRecordingAccess: {
                requestCount += 1
                return false
            },
            openSettingsURL: { _ in true }
        )

        XCTAssertEqual(service.requestScreenRecordingPermissionIfNeeded(), .denied)
        XCTAssertEqual(service.requestScreenRecordingPermissionIfNeeded(), .denied)
        XCTAssertEqual(requestCount, 1)
    }

    func testRefreshDetectsPermissionGrantedInSystemSettings() {
        var hasPermission = false
        let service = PermissionsService(
            checkScreenRecordingAccess: { hasPermission },
            requestScreenRecordingAccess: { false },
            openSettingsURL: { _ in true }
        )

        hasPermission = true

        XCTAssertEqual(service.refreshScreenRecordingPermission(), .granted)
        XCTAssertEqual(service.screenRecordingState, .granted)
    }

    func testOpenSettingsUsesScreenRecordingPrivacyPane() {
        var openedURL: URL?
        let service = PermissionsService(
            checkScreenRecordingAccess: { false },
            requestScreenRecordingAccess: { false },
            openSettingsURL: { url in
                openedURL = url
                return true
            }
        )

        service.openScreenRecordingSettings()

        XCTAssertEqual(
            openedURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }
}
