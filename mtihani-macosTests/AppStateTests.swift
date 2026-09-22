import XCTest

@testable import mtihani_macos

@MainActor
final class AppStateTests: XCTestCase {
    func testTriggerPreferenceImmediatelyStartsAndStopsMonitor() async {
        let context = makeContext()
        defer { context.cleanUp() }
        context.appState.start()
        await context.appState.selectSession("ready-session")

        XCTAssertTrue(context.monitor.isMonitoring)
        XCTAssertEqual(context.monitor.startCount, 1)

        context.settings.isTripleClickEnabled = false
        await Task.yield()

        XCTAssertFalse(context.monitor.isMonitoring)
        XCTAssertEqual(context.monitor.stopCount, 1)

        context.settings.isTripleClickEnabled = true
        await Task.yield()

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
        await context.appState.selectSession("new-session")
        await fulfillment(of: [validated])

        XCTAssertEqual(context.apiClient.requestedSessionIDs, ["new-session"])
        XCTAssertEqual(context.coordinator.connectionState, .connected)
        context.appState.stop()
    }

    func testRefreshingSessionsLoadsBackendSessions() async {
        let context = makeContext()
        defer { context.cleanUp() }

        await context.appState.refreshSessions()

        XCTAssertEqual(
            context.appState.sessions,
            [Session(id: "listed-session", status: .active)]
        )
    }

    func testStartingSessionSelectsNewSession() async {
        let context = makeContext()
        defer { context.cleanUp() }

        await context.appState.startNewSession()

        XCTAssertEqual(context.settings.sessionID, "created-session")
        XCTAssertEqual(context.appState.sessions.first?.id, "created-session")
    }

    func testSignedOutActionsDoNotReachAPI() async {
        let context = makeContext()
        defer { context.cleanUp() }
        context.settings.accessToken = ""
        await context.appState.refreshSessions()
        await context.appState.startNewSession()
        await context.appState.selectSession("private")
        XCTAssertEqual(context.apiClient.listCalls, 0)
        XCTAssertEqual(context.apiClient.createCalls, 0)
        XCTAssertTrue(context.apiClient.requestedSessionIDs.isEmpty)
    }

    func testNewestEligibleSessionIsSelectedOnlyWithoutRememberedSelection() async {
        let context = makeContext()
        defer { context.cleanUp() }
        context.apiClient.list = [
            Session(id: "old", status: .active, updatedAt: "2026-01-01"),
            Session(id: "closed", status: .closed, updatedAt: "2026-03-01"),
            Session(id: "new", status: .active, updatedAt: "2026-02-01"),
        ]
        await context.appState.refreshSessions()
        XCTAssertEqual(context.appState.activeSession?.id, "new")
        await context.appState.selectSession("old")
        await context.appState.refreshSessions()
        XCTAssertEqual(context.appState.activeSession?.id, "old")
    }

    func testInvalidManualSelectionAndNetworkFailurePreserveDestination() async {
        let context = makeContext()
        defer { context.cleanUp() }
        await context.appState.selectSession("original")
        context.apiClient.sessionError = .invalidSession
        await context.appState.selectSession("other-account")
        XCTAssertEqual(context.appState.activeSession?.id, "original")
        context.apiClient.sessionError = .transport
        await context.appState.refreshSessions()
        XCTAssertEqual(context.appState.activeSession?.id, "original")
        context.apiClient.sessionError = .invalidSession
        await context.appState.refreshSessions()
        XCTAssertNil(context.appState.activeSession)
        XCTAssertEqual(context.settings.sessionID, "original")
        XCTAssertFalse(context.appState.canCapture)
    }

    func testSlowValidationCannotOverrideNewerSelection() async {
        let context = makeContext()
        defer { context.cleanUp() }
        context.apiClient.delayedID = "slow"
        let slow = Task { await context.appState.selectSession("slow") }
        while !context.apiClient.requestedSessionIDs.contains("slow") { await Task.yield() }
        await context.appState.selectSession("newer")
        await slow.value
        XCTAssertEqual(context.appState.activeSession?.id, "newer")
    }

    private func makeContext() -> AppStateTestContext {
        let suiteName = "AppStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(
            defaults: defaults,
            apiBaseURL: "http://localhost:5173/api"
        )
        settings.accessToken = "test-api-key"
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
            apiClientFactory: { _ in apiClient },
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
    var list = [Session(id: "listed-session", status: .active)]
    var sessionError: APIError?
    var delayedID: String?
    var listCalls = 0
    var createCalls = 0
    var onGetSession: ((String) -> Void)?
    private(set) var requestedSessionIDs: [String] = []

    func listSessions() async throws -> [Session] {
        listCalls += 1
        return list
    }

    func createSession() async throws -> Session {
        createCalls += 1
        return Session(id: "created-session", status: .active)
    }

    func getSession(id: String) async throws -> Session {
        requestedSessionIDs.append(id)
        onGetSession?(id)
        if id == delayedID { try await Task.sleep(for: .milliseconds(30)) }
        if let sessionError { throw sessionError }
        return Session(id: id, status: .active)
    }

    func uploadCapture(
        sessionId: String,
        screenshots: [Data],
        language: String?
    ) async throws -> AcceptedCapture {
        AcceptedCapture(
            captureId: "capture",
            sessionId: sessionId,
            status: .received
        )
    }
}
