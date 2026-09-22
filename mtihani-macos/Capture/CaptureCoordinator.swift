import Combine
import Foundation
import OSLog

typealias MtihaniAPIClientFactory = @MainActor (AppConfiguration) -> any MtihaniAPIClient

/// How long the capture buffer waits for another shot before uploading.
enum CaptureBufferWindow: Equatable, Sendable {
    /// Finalizes a buffered shot immediately — no waiting for more. Used by
    /// tests to keep single-trigger-uploads-at-once behavior deterministic.
    case disabled
    /// A fixed duration, independent of user Settings — used by tests that
    /// exercise real buffering without waiting on `AppSettings.bufferWindowSeconds`.
    case fixed(nanoseconds: UInt64)
    /// Reads `AppSettings.bufferWindowSeconds` fresh on every trigger, so a
    /// change in Settings applies immediately. The production default.
    case settingsDriven
}

@MainActor
final class CaptureCoordinator: ObservableObject {
    var captureAllowed: (() -> Bool)?
    private var accountGeneration = UUID()

    func resetForAccount() {
        accountGeneration = UUID()
        closedSessionID = nil
        resetTask?.cancel()
        bufferTask?.cancel()
        bufferedImages = []
        bufferedContext = nil
        state = .idle
        connectionState = .notConfigured
    }

    func markSessionValidated() {
        closedSessionID = nil
        connectionState = .connected
    }
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var connectionState: SessionConnectionState

    private let settings: AppSettings
    private let screenCapturer: any ScreenCapturing
    private let permissionService: any PermissionsServicing
    private let apiClientFactory: MtihaniAPIClientFactory
    private let terminalStateResetNanoseconds: UInt64?
    private let logger: Logger

    private var closedSessionID: String?
    private var resetTask: Task<Void, Never>?

    // Multi-image buffering: a trigger while idle/buffering captures another
    // shot into the same pending upload instead of starting a new one. A
    // finalize timer (reset on every new shot) flushes the buffer as one
    // capture once triggering goes quiet — purely timer-driven, no count cap.
    private var bufferedImages: [CapturedImage] = []
    private var bufferedContext: RequestContext?
    private var bufferTask: Task<Void, Never>?
    private let bufferWindow: CaptureBufferWindow

    init(
        settings: AppSettings,
        screenCapturer: any ScreenCapturing,
        permissionService: any PermissionsServicing,
        terminalStateResetNanoseconds: UInt64? = 2_000_000_000,
        bufferWindow: CaptureBufferWindow = .settingsDriven,
        apiClientFactory: @escaping MtihaniAPIClientFactory,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.victorjambo.mtihani-macos",
            category: "capture"
        )
    ) {
        self.settings = settings
        self.screenCapturer = screenCapturer
        self.permissionService = permissionService
        self.terminalStateResetNanoseconds = terminalStateResetNanoseconds
        self.bufferWindow = bufferWindow
        self.apiClientFactory = apiClientFactory
        self.logger = logger
        connectionState =
            settings.trimmedSessionID.isEmpty
            ? .notConfigured
            : .disconnected
    }

    var canCapture: Bool {
        !state.isProcessing
            && closedSessionID != settings.trimmedSessionID
    }

    func captureAndUpload() async {
        guard captureAllowed?() ?? true else { return }
        let currentAccount = accountGeneration
        guard !state.isProcessing else {
            logger.debug("Ignored a capture trigger while another capture is active")
            return
        }

        resetTask?.cancel()

        guard let requestContext = prepareRequestContext() else {
            return
        }

        guard closedSessionID != requestContext.sessionID else {
            connectionState = .sessionClosed
            fail(with: "This session is closed. Enter another session ID.")
            return
        }

        guard permissionService.requestScreenRecordingPermissionIfNeeded() == .granted else {
            fail(
                with:
                    "Screen Recording permission is required. Open System Settings to grant access."
            )
            return
        }

        state = .capturing

        do {
            let image = try await screenCapturer.capture()
            guard accountGeneration == currentAccount else { return }
            try Task.checkCancellation()

            guard image.mimeType == CapturedImage.pngMimeType else {
                throw ScreenCaptureError.pngEncodingFailed
            }

            bufferedImages.append(image)
            bufferedContext = requestContext
            state = .buffering(count: bufferedImages.count)

            let windowNanoseconds: UInt64?
            switch bufferWindow {
            case .disabled:
                windowNanoseconds = nil
            case .fixed(let nanoseconds):
                windowNanoseconds = nanoseconds
            case .settingsDriven:
                windowNanoseconds = UInt64(settings.bufferWindowSeconds) * 1_000_000_000
            }

            guard let windowNanoseconds else {
                await finalizeBufferedCapture(currentAccount: currentAccount)
                return
            }

            bufferTask?.cancel()
            bufferTask = Task { [weak self] in
                await self?.waitOutBufferWindow(
                    remainingNanoseconds: windowNanoseconds,
                    currentAccount: currentAccount
                )
            }
        } catch is CancellationError {
            guard accountGeneration == currentAccount else { return }
            state = bufferedImages.isEmpty ? .idle : .buffering(count: bufferedImages.count)
        } catch {
            guard accountGeneration == currentAccount else { return }
            handleCaptureError(error, context: requestContext)
        }
    }

    /// Sleeps out the coalescing window in ~1s steps, logging a countdown so
    /// it's visible when to expect the batch to upload — without changing the
    /// total wait, so a short test window still behaves exactly as before.
    private func waitOutBufferWindow(remainingNanoseconds: UInt64, currentAccount: UUID) async {
        let oneSecond: UInt64 = 1_000_000_000
        var remaining = remainingNanoseconds

        while remaining > 0 {
            let step = min(oneSecond, remaining)
            let secondsRemaining = (remaining + oneSecond - 1) / oneSecond
            logger.info("Buffer window: \(secondsRemaining, privacy: .public)s remaining before upload")

            try? await Task.sleep(nanoseconds: step)
            guard !Task.isCancelled else { return }
            remaining -= step
        }

        await finalizeBufferedCapture(currentAccount: currentAccount)
    }

    private func finalizeBufferedCapture(currentAccount: UUID) async {
        guard accountGeneration == currentAccount else { return }
        guard let requestContext = bufferedContext, !bufferedImages.isEmpty else { return }

        let images = bufferedImages
        bufferedImages = []
        bufferedContext = nil

        state = .uploading

        do {
            let client = apiClientFactory(requestContext.configuration)
            let acceptedCapture = try await client.uploadCapture(
                sessionId: requestContext.sessionID,
                screenshots: images.map(\.data),
                language: requestContext.language
            )
            guard accountGeneration == currentAccount else { return }

            if isCurrent(requestContext) {
                connectionState = .connected
            }
            state = .success(captureID: acceptedCapture.captureId)
            logger.info(
                "Capture accepted by backend: captureID=\(acceptedCapture.captureId, privacy: .public), imageCount=\(images.count)"
            )
            scheduleReturnToReady()
        } catch is CancellationError {
            guard accountGeneration == currentAccount else { return }
            state = .idle
        } catch {
            guard accountGeneration == currentAccount else { return }
            handleCaptureError(error, context: requestContext)
        }
    }

    func validateSession() async {
        guard let requestContext = prepareRequestContext(updateCaptureState: false) else {
            return
        }

        connectionState = .connecting

        do {
            let client = apiClientFactory(requestContext.configuration)
            let session = try await client.getSession(id: requestContext.sessionID)
            guard isCurrent(requestContext) else {
                return
            }

            switch session.status {
            case .active:
                closedSessionID = nil
                connectionState = .connected
                logger.info("Backend session validation succeeded")
            case .closed:
                closedSessionID = requestContext.sessionID
                connectionState = .sessionClosed
                logger.notice("Backend session validation found a closed session")
            }
        } catch is CancellationError {
            if isCurrent(requestContext) {
                connectionState = .disconnected
            }
        } catch {
            guard isCurrent(requestContext) else {
                return
            }
            mapValidationError(error, sessionID: requestContext.sessionID)
        }
    }

    func settingsDidChange(sessionID: String, accessToken: String) {
        closedSessionID = nil
        resetTask?.cancel()

        if sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            connectionState = .notConfigured
        } else {
            do {
                _ = try AppConfiguration(apiBaseURL: settings.apiBaseURL, accessToken: accessToken)
                connectionState = .disconnected
            } catch {
                connectionState = .invalidConfiguration
            }
        }
    }

    private func prepareRequestContext(
        updateCaptureState: Bool = true
    ) -> RequestContext? {
        let sessionID = settings.trimmedSessionID
        guard !sessionID.isEmpty else {
            connectionState = .notConfigured
            if updateCaptureState {
                fail(with: "Enter a session ID in Settings before capturing.")
            }
            return nil
        }

        let configuration: AppConfiguration
        switch settings.configuration {
        case .success(let value):
            configuration = value
        case .failure(let error):
            connectionState = .invalidConfiguration
            if updateCaptureState {
                fail(with: error.localizedDescription)
            }
            return nil
        }

        return RequestContext(
            configuration: configuration,
            sessionID: sessionID,
            language: settings.preferredLanguage.apiValue
        )
    }

    private func handleCaptureError(_ error: Error, context: RequestContext) {
        if isCurrent(context) {
            mapCaptureError(error, sessionID: context.sessionID)
        }

        let message: String
        if let localizedError = error as? LocalizedError,
            let description = localizedError.errorDescription
        {
            message = description
        } else {
            message = "The capture could not be sent. Please try again."
        }

        logger.error("Capture pipeline failed: \(message, privacy: .public)")
        fail(with: message)
    }

    private func mapValidationError(_ error: Error, sessionID: String) {
        switch error {
        case APIError.badRequest, APIError.invalidSession:
            connectionState = .invalidSession
        case APIError.unauthorized:
            connectionState = .invalidConfiguration
        case APIError.sessionClosed:
            closedSessionID = sessionID
            connectionState = .sessionClosed
        case APIError.transport, APIError.serverError:
            connectionState = .serverUnavailable
        case APIError.invalidURL:
            connectionState = .invalidConfiguration
        default:
            connectionState = .disconnected
        }
    }

    private func mapCaptureError(_ error: Error, sessionID: String) {
        switch error {
        case APIError.invalidSession:
            connectionState = .invalidSession
        case APIError.sessionClosed:
            closedSessionID = sessionID
            connectionState = .sessionClosed
        case APIError.transport, APIError.serverError:
            connectionState = .serverUnavailable
        case APIError.invalidURL:
            connectionState = .invalidConfiguration
        case APIError.badRequest, APIError.captureTooLarge, is ScreenCaptureError:
            break
        default:
            connectionState = .disconnected
        }
    }

    private func isCurrent(_ context: RequestContext) -> Bool {
        guard settings.trimmedSessionID == context.sessionID else {
            return false
        }

        guard case .success(let configuration) = settings.configuration else {
            return false
        }

        return configuration == context.configuration
    }

    private func fail(with message: String) {
        state = .failed(message: message)
        scheduleReturnToReady()
    }

    private func scheduleReturnToReady() {
        guard let terminalStateResetNanoseconds else {
            return
        }

        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: terminalStateResetNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            self?.state = .idle
        }
    }

    private struct RequestContext {
        let configuration: AppConfiguration
        let sessionID: String
        let language: String?
    }
}
