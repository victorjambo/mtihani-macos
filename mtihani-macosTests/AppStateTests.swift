import XCTest
@testable import mtihani_macos

@MainActor
final class AppStateTests: XCTestCase {
    func testTriggerPreferenceImmediatelyStartsAndStopsMonitor() {
        let context = makeContext()
        defer { context.cleanUp() }
        context.appState.start()

        XCTAssertTrue(context.monitor.isMonitoring)
        XCTAssertEqual(context.monitor.startCount, 1)

        context.settings.isTripleClickEnabled = false

        XCTAssertFalse(context.monitor.isMonitoring)
        XCTAssertEqual(context.monitor.stopCount, 1)

        context.settings.isTripleClickEnabled = true

        XCTAssertTrue(context.monitor.isMonitoring)
        XCTAssertEqual(context.monitor.startCount, 2)
        context.appState.stop()
    }

    func testChangingSessionSchedulesValidationForNewValue() async {
        let context = makeContext()
        defer { context.cleanUp() }
        let validated = expectation(description: "new session validated")
        context.apiClient.onGetSession = { sessionID in
            if sessionID == "new-session" {
                validated.fulfill()
            }
        }
        context.appState.start()

        context.settings.sessionID = "new-session"
        await fulfillment(of: [validated])

        XCTAssertEqual(context.apiClient.requestedSessionIDs, ["new-session"])
        XCTAssertEqual(context.coordinator.connectionState, .connected)
        context.appState.stop()
    }

    private func makeContext() -> AppStateTestContext {
        let suiteName = "AppStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        let permissions = PermissionsService(
            checkScreenRecordingAccess: { true },
            requestScreenRecordingAccess: { true },
            openSettingsURL: { _ in true }
        )
        let apiClient = AppStateMockAPIClient()
        let coordinator = CaptureCoordinator(
            settings: settings,
            screenCapturer: AppStateMockScreenCapturer(),
            permissionService: permissions,
            terminalStateResetNanoseconds: nil,
            apiClientFactory: { _ in apiClient }
        )
        let monitor = MockCaptureTriggerMonitor()
        let appState = AppState(
            settings: settings,
            permissions: permissions,
            captureCoordinator: coordinator,
            triggerMonitor: monitor,
            settingsValidationDelayNanoseconds: 0
        )

        return AppStateTestContext(
            defaultsSuiteName: suiteName,
            settings: settings,
            coordinator: coordinator,
            apiClient: apiClient,
            monitor: monitor,
            appState: appState
        )
    }
}

@MainActor
private struct AppStateTestContext {
    let defaultsSuiteName: String
    let settings: AppSettings
    let coordinator: CaptureCoordinator
    let apiClient: AppStateMockAPIClient
    let monitor: MockCaptureTriggerMonitor
    let appState: AppState

    func cleanUp() {
        UserDefaults(suiteName: defaultsSuiteName)?
            .removePersistentDomain(forName: defaultsSuiteName)
    }
}

@MainActor
private final class MockCaptureTriggerMonitor: CaptureTriggerMonitor {
    private(set) var isMonitoring = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() -> Bool {
        startCount += 1
        isMonitoring = true
        return true
    }

    func stop() {
        guard isMonitoring else { return }
        stopCount += 1
        isMonitoring = false
    }
}

@MainActor
private final class AppStateMockScreenCapturer: ScreenCapturing {
    func capture() async throws -> CapturedImage {
        CapturedImage(data: Data([0x89, 0x50, 0x4E, 0x47]), width: 1, height: 1)
    }
}

@MainActor
private final class AppStateMockAPIClient: MtihaniAPIClient {
    var onGetSession: ((String) -> Void)?
    private(set) var requestedSessionIDs: [String] = []

    func getSession(id: String) async throws -> Session {
        requestedSessionIDs.append(id)
        onGetSession?(id)
        return Session(id: id, status: .active)
    }

    func uploadCapture(
        sessionId: String,
        screenshot: Data,
        language: String?
    ) async throws -> AcceptedCapture {
        AcceptedCapture(
            captureId: "capture",
            sessionId: sessionId,
            status: .received
        )
    }
}
