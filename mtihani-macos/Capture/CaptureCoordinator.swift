import Combine
import Foundation
import OSLog

typealias MtihaniAPIClientFactory = @MainActor (AppConfiguration) -> any MtihaniAPIClient

@MainActor
final class CaptureCoordinator: ObservableObject {
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

    init(
        settings: AppSettings,
        screenCapturer: any ScreenCapturing,
        permissionService: any PermissionsServicing,
        terminalStateResetNanoseconds: UInt64? = 2_000_000_000,
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
        self.apiClientFactory = apiClientFactory
        self.logger = logger
        connectionState = settings.trimmedSessionID.isEmpty
            ? .notConfigured
            : .disconnected
    }

    var canCapture: Bool {
        !state.isProcessing
            && closedSessionID != settings.trimmedSessionID
    }

    func captureAndUpload() async {
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
                with: "Screen Recording permission is required. Open System Settings to grant access."
            )
            return
        }

        state = .capturing

        do {
            let image = try await screenCapturer.capture()
            try Task.checkCancellation()

            guard image.mimeType == CapturedImage.pngMimeType else {
                throw ScreenCaptureError.pngEncodingFailed
            }

            state = .uploading
            let client = apiClientFactory(requestContext.configuration)
            let acceptedCapture = try await client.uploadCapture(
                sessionId: requestContext.sessionID,
                screenshot: image.data,
                language: requestContext.language
            )

            if isCurrent(requestContext) {
                connectionState = .connected
            }
            state = .success(captureID: acceptedCapture.captureId)
            logger.info(
                "Capture accepted by backend: captureID=\(acceptedCapture.captureId, privacy: .public)"
            )
            scheduleReturnToReady()
        } catch is CancellationError {
            state = .idle
        } catch {
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

    func settingsDidChange(sessionID: String, backendURL: String, apiKey: String) {
        closedSessionID = nil
        resetTask?.cancel()

        if sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            connectionState = .notConfigured
        } else {
            do {
                _ = try AppConfiguration(backendURL: backendURL, apiKey: apiKey)
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
        case let .success(value):
            configuration = value
        case let .failure(error):
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
        case APIError.invalidURL, APIError.unauthorized:
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

        guard case let .success(configuration) = settings.configuration else {
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
