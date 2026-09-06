import XCTest
@testable import mtihani_macos

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CaptureCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSuccessfulCaptureTransitionsThroughCaptureAndUpload() async {
        let settings = configuredSettings()
        settings.preferredLanguage = .typeScript
        let screenCapturer = MockScreenCapturer()
        let apiClient = MockAPIClient()
        let permissions = MockPermissionsService(state: .granted)
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            apiClient: apiClient,
            permissions: permissions
        )
        var observedStates: [CaptureState] = []
        screenCapturer.onCapture = {
            observedStates.append(coordinator.state)
        }
        apiClient.onUpload = {
            observedStates.append(coordinator.state)
        }

        await coordinator.captureAndUpload()

        XCTAssertEqual(observedStates, [.capturing, .uploading])
        XCTAssertEqual(coordinator.state, .success(captureID: "capture-123"))
        XCTAssertEqual(coordinator.connectionState, .connected)
        XCTAssertEqual(apiClient.lastLanguage, "typescript")
        XCTAssertEqual(apiClient.lastScreenshot, screenCapturer.image.data)
    }

    func testCaptureFailureDoesNotAttemptUpload() async {
        let settings = configuredSettings()
        let screenCapturer = MockScreenCapturer()
        screenCapturer.error = ScreenCaptureError.captureFailed
        let apiClient = MockAPIClient()
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            apiClient: apiClient,
            permissions: MockPermissionsService(state: .granted)
        )

        await coordinator.captureAndUpload()

        XCTAssertEqual(
            coordinator.state,
            .failed(message: "The screen could not be captured. Please try again.")
        )
        XCTAssertEqual(screenCapturer.captureCount, 1)
        XCTAssertEqual(apiClient.uploadCount, 0)
    }

    func testUploadFailureReturnsARecoverableSafeState() async {
        let settings = configuredSettings()
        let screenCapturer = MockScreenCapturer()
        let apiClient = MockAPIClient()
        apiClient.uploadError = APIError.transport
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            apiClient: apiClient,
            permissions: MockPermissionsService(state: .granted)
        )

        await coordinator.captureAndUpload()

        XCTAssertEqual(
            coordinator.state,
            .failed(message: "The backend could not be reached.")
        )
        XCTAssertEqual(coordinator.connectionState, .serverUnavailable)
        XCTAssertTrue(coordinator.canCapture)
    }

    func testSecondTriggerIsIgnoredWhileCaptureIsRunning() async {
        let settings = configuredSettings()
        let screenCapturer = MockScreenCapturer()
        screenCapturer.shouldSuspend = true
        let started = expectation(description: "capture started")
        screenCapturer.onCapture = {
            started.fulfill()
        }
        let apiClient = MockAPIClient()
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            apiClient: apiClient,
            permissions: MockPermissionsService(state: .granted)
        )

        let firstCapture = Task {
            await coordinator.captureAndUpload()
        }
        await fulfillment(of: [started])

        await coordinator.captureAndUpload()
        XCTAssertEqual(screenCapturer.captureCount, 1)

        screenCapturer.resumeCapture()
        await firstCapture.value

        XCTAssertEqual(screenCapturer.captureCount, 1)
        XCTAssertEqual(apiClient.uploadCount, 1)
    }

    func testMissingSessionFailsBeforePermissionOrCapture() async {
        let settings = AppSettings(defaults: defaults)
        let screenCapturer = MockScreenCapturer()
        let permissions = MockPermissionsService(state: .granted)
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            apiClient: MockAPIClient(),
            permissions: permissions
        )

        await coordinator.captureAndUpload()

        XCTAssertEqual(
            coordinator.state,
            .failed(message: "Enter a session ID in Settings before capturing.")
        )
        XCTAssertEqual(coordinator.connectionState, .notConfigured)
        XCTAssertEqual(permissions.requestCount, 0)
        XCTAssertEqual(screenCapturer.captureCount, 0)
    }

    func testClosedSessionBlocksSubsequentCaptureAttempts() async {
        let settings = configuredSettings()
        let screenCapturer = MockScreenCapturer()
        let apiClient = MockAPIClient()
        apiClient.session = Session(id: settings.trimmedSessionID, status: .closed)
        let permissions = MockPermissionsService(state: .granted)
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            apiClient: apiClient,
            permissions: permissions
        )

        await coordinator.validateSession()
        await coordinator.captureAndUpload()

        XCTAssertEqual(coordinator.connectionState, .sessionClosed)
        XCTAssertFalse(coordinator.canCapture)
        XCTAssertEqual(permissions.requestCount, 0)
        XCTAssertEqual(screenCapturer.captureCount, 0)
    }

    func testBadRequestWhileValidatingIsReportedAsInvalidSession() async {
        let settings = configuredSettings()
        let apiClient = MockAPIClient()
        apiClient.sessionError = APIError.badRequest
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: MockScreenCapturer(),
            apiClient: apiClient,
            permissions: MockPermissionsService(state: .granted)
        )

        await coordinator.validateSession()

        XCTAssertEqual(coordinator.connectionState, .invalidSession)
    }

    func testCaptureTooLargeDoesNotDiscardConnectedSession() async {
        let settings = configuredSettings()
        let apiClient = MockAPIClient()
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: MockScreenCapturer(),
            apiClient: apiClient,
            permissions: MockPermissionsService(state: .granted)
        )
        await coordinator.validateSession()
        apiClient.uploadError = APIError.captureTooLarge

        await coordinator.captureAndUpload()

        XCTAssertEqual(coordinator.connectionState, .connected)
        XCTAssertEqual(
            coordinator.state,
            .failed(message: "The screenshot exceeds the backend's configured upload limit.")
        )
    }

    func testUploadConflictBlocksFurtherCapturesForSameSession() async {
        let settings = configuredSettings()
        let screenCapturer = MockScreenCapturer()
        let apiClient = MockAPIClient()
        apiClient.uploadError = APIError.sessionClosed
        let permissions = MockPermissionsService(state: .granted)
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            apiClient: apiClient,
            permissions: permissions
        )

        await coordinator.captureAndUpload()
        await coordinator.captureAndUpload()

        XCTAssertEqual(coordinator.connectionState, .sessionClosed)
        XCTAssertFalse(coordinator.canCapture)
        XCTAssertEqual(screenCapturer.captureCount, 1)
        XCTAssertEqual(apiClient.uploadCount, 1)
    }

    func testOldUploadCompletionDoesNotConnectNewSession() async {
        let settings = configuredSettings()
        let screenCapturer = MockScreenCapturer()
        let apiClient = MockAPIClient()
        apiClient.shouldSuspendUpload = true
        let uploadStarted = expectation(description: "upload started")
        apiClient.onUpload = {
            uploadStarted.fulfill()
        }
        let coordinator = makeCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            apiClient: apiClient,
            permissions: MockPermissionsService(state: .granted)
        )

        let capture = Task {
            await coordinator.captureAndUpload()
        }
        await fulfillment(of: [uploadStarted])

        settings.sessionID = "new-session"
        coordinator.settingsDidChange(
            sessionID: "new-session",
            backendURL: settings.backendURL
        )
        apiClient.resumeUpload()
        await capture.value

        XCTAssertEqual(coordinator.connectionState, .disconnected)
        XCTAssertEqual(coordinator.state, .success(captureID: "capture-123"))
    }

    private func configuredSettings() -> AppSettings {
        let settings = AppSettings(defaults: defaults)
        settings.sessionID = "session-123"
        return settings
    }

    private func makeCoordinator(
        settings: AppSettings,
        screenCapturer: MockScreenCapturer,
        apiClient: MockAPIClient,
        permissions: MockPermissionsService
    ) -> CaptureCoordinator {
        CaptureCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            permissionService: permissions,
            terminalStateResetNanoseconds: nil,
            apiClientFactory: { _ in apiClient }
        )
    }
}

@MainActor
private final class MockScreenCapturer: ScreenCapturing {
    var image = CapturedImage(
        data: Data([0x89, 0x50, 0x4E, 0x47]),
        width: 100,
        height: 80
    )
    var error: Error?
    var shouldSuspend = false
    var onCapture: (() -> Void)?
    private(set) var captureCount = 0

    private var continuation: CheckedContinuation<CapturedImage, Error>?

    func capture() async throws -> CapturedImage {
        captureCount += 1
        onCapture?()

        if let error {
            throw error
        }

        if shouldSuspend {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        return image
    }

    func resumeCapture() {
        continuation?.resume(returning: image)
        continuation = nil
    }
}

@MainActor
private final class MockAPIClient: MtihaniAPIClient {
    var session = Session(id: "session-123", status: .active)
    var uploadResult = AcceptedCapture(
        captureId: "capture-123",
        sessionId: "session-123",
        status: .received
    )
    var sessionError: Error?
    var uploadError: Error?
    var shouldSuspendUpload = false
    var onUpload: (() -> Void)?
    private(set) var uploadCount = 0
    private(set) var lastScreenshot: Data?
    private(set) var lastLanguage: String?
    private var uploadContinuation: CheckedContinuation<AcceptedCapture, Error>?

    func listSessions() async throws -> [Session] {
        [session]
    }

    func createSession() async throws -> Session {
        session
    }

    func getSession(id: String) async throws -> Session {
        if let sessionError {
            throw sessionError
        }
        return session
    }

    func uploadCapture(
        sessionId: String,
        screenshot: Data,
        language: String?
    ) async throws -> AcceptedCapture {
        uploadCount += 1
        lastScreenshot = screenshot
        lastLanguage = language
        onUpload?()

        if shouldSuspendUpload {
            return try await withCheckedThrowingContinuation { continuation in
                uploadContinuation = continuation
            }
        }

        if let uploadError {
            throw uploadError
        }
        return uploadResult
    }

    func resumeUpload() {
        uploadContinuation?.resume(returning: uploadResult)
        uploadContinuation = nil
    }
}

@MainActor
private final class MockPermissionsService: PermissionsServicing {
    var screenRecordingState: ScreenRecordingPermissionState
    private(set) var requestCount = 0

    init(state: ScreenRecordingPermissionState) {
        screenRecordingState = state
    }

    func refreshScreenRecordingPermission() -> ScreenRecordingPermissionState {
        screenRecordingState
    }

    func requestScreenRecordingPermissionIfNeeded() -> ScreenRecordingPermissionState {
        requestCount += 1
        return screenRecordingState
    }

    func openScreenRecordingSettings() {}
}
