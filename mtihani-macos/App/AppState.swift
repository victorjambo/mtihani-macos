import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let settings: AppSettings
    let permissions: PermissionsService
    let captureCoordinator: CaptureCoordinator
    let authentication: DesktopAuthentication?
    @Published private(set) var triggerIsMonitoring = false
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var activeSession: Session?
    @Published private(set) var isSessionOperationInProgress = false
    @Published private(set) var sessionOperationError: String?
    @Published private(set) var connectionTitle = "Not checked"
    @Published private(set) var checkingConnection = false
    private let triggerMonitor: any CaptureTriggerMonitor
    private let apiClientFactory: MtihaniAPIClientFactory
    private var cancellables = Set<AnyCancellable>()
    private var generation = UUID()
    private var selectionGeneration = UUID()
    private var isStarted = false

    var isAuthenticated: Bool {
        authentication.map { $0.account != nil && $0.state != .reauthenticationRequired }
            ?? !settings.accessToken.isEmpty
    }
    var readiness: String {
        if authentication?.state == .restoring { return "Restoring sign-in…" }
        if !isAuthenticated { return "Sign in required" }
        if permissions.screenRecordingState != .granted {
            return "Screen recording permission required"
        }
        if activeSession == nil { return "Select or create a session" }
        if captureCoordinator.connectionState == .sessionClosed
            || captureCoordinator.connectionState == .invalidSession
        {
            return "Session unavailable. Select or create a session."
        }
        if connectionTitle == "Cannot reach server"
            || captureCoordinator.connectionState == .serverUnavailable
        {
            return "Cannot reach server"
        }
        if captureCoordinator.connectionState != .connected { return "Validating session…" }
        return captureCoordinator.state.title
    }
    var canCapture: Bool {
        isAuthenticated && activeSession?.status == .active
            && connectionTitle != "Cannot reach server"
            && permissions.screenRecordingState == .granted
            && captureCoordinator.connectionState == .connected && captureCoordinator.canCapture
    }
    var triggerStatusTitle: String {
        !settings.isTripleClickEnabled
            ? "Disabled" : triggerIsMonitoring ? "Active" : "Paused · \(readiness)"
    }

    init(
        settings: AppSettings, permissions: PermissionsService,
        captureCoordinator: CaptureCoordinator,
        triggerMonitor: any CaptureTriggerMonitor,
        apiClientFactory: @escaping MtihaniAPIClientFactory,
        settingsValidationDelayNanoseconds: UInt64 = 500_000_000,
        authentication: DesktopAuthentication? = nil
    ) {
        self.settings = settings
        self.permissions = permissions
        self.captureCoordinator = captureCoordinator
        self.triggerMonitor = triggerMonitor
        self.apiClientFactory = apiClientFactory
        self.authentication = authentication
        bindState()
        authentication?.didChangeAccount = { [weak self] in self?.accountChanged() }
    }

    static func live() -> AppState {
        let settings = AppSettings()
        let permissions = PermissionsService()
        let apiURL = URL(string: settings.apiBaseURL)!
        let frontend = URL(
            string: Bundle.main.object(forInfoDictionaryKey: "FrontendBaseURL") as? String ?? "")!
        let environment =
            Bundle.main.object(forInfoDictionaryKey: "DesktopEnvironment") as? String
            ?? "development"
        let auth = DesktopAuthentication(
            apiURL: apiURL, frontendURL: frontend, environment: environment)
        let factory: MtihaniAPIClientFactory = { configuration in
            let accountGeneration = auth.generation
            var lastToken = configuration.accessToken
            let client = URLSessionMtihaniAPIClient(
                baseURL: configuration.apiBaseURL, accessToken: configuration.accessToken)
            client.tokenProvider = { force in
                guard auth.generation == accountGeneration else { throw CancellationError() }
                let needsRefresh = force && auth.credential?.accessToken == lastToken
                let token = try await auth.accessToken(forceRefresh: needsRefresh)
                lastToken = token
                return token
            }
            return client
        }
        let coordinator = CaptureCoordinator(
            settings: settings,
            screenCapturer: ScreenCaptureService(permissionService: permissions),
            permissionService: permissions,
            apiClientFactory: factory)
        let monitor = GlobalClickMonitor(
            requiredClickCount: { settings.requiredClickCount },
            onTrigger: {
                Task { await coordinator.captureAndUpload() }
            })
        let app = AppState(
            settings: settings, permissions: permissions, captureCoordinator: coordinator,
            triggerMonitor: monitor, apiClientFactory: factory, authentication: auth)
        coordinator.captureAllowed = { [weak app] in app?.canCapture ?? false }
        return app
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        permissions.refreshScreenRecordingPermission()
        if let authentication {
            Task { await authentication.restore() }
        } else {
            Task { await refreshSessions() }
        }
        updateTriggerMonitoring()
    }
    func stop() {
        isStarted = false
        triggerMonitor.stop()
        triggerIsMonitoring = false
    }
    func quit() {
        stop()
        NSApplication.shared.terminate(nil)
    }
    func requestScreenRecordingPermission() {
        permissions.requestScreenRecordingPermissionIfNeeded()
        updateTriggerMonitoring()
    }

    private func accountChanged() {
        generation = UUID()
        selectionGeneration = UUID()
        sessions = []
        activeSession = nil
        sessionOperationError = nil
        isSessionOperationInProgress = false
        settings.accessToken =
            authentication?.account == nil ? "" : authentication?.credential?.accessToken ?? ""
        settings.useAccount(authentication?.account?.id)
        captureCoordinator.resetForAccount()
        updateTriggerMonitoring()
        if isAuthenticated { Task { await refreshSessions() } }
    }

    func refreshSessions() async {
        guard isAuthenticated, !isSessionOperationInProgress, let client = makeAPIClient() else {
            return
        }
        let current = generation
        let choice = selectionGeneration
        isSessionOperationInProgress = true
        sessionOperationError = nil
        defer {
            if generation == current {
                isSessionOperationInProgress = false
                updateTriggerMonitoring()
            }
        }
        do {
            let list = try await client.listSessions()
            guard generation == current else { return }
            sessions = list.sorted {
                let a = $0.updatedAt ?? $0.createdAt ?? ""
                let b = $1.updatedAt ?? $1.createdAt ?? ""
                return a == b ? $0.id > $1.id : a > b
            }
            guard selectionGeneration == choice else { return }
            let remembered = settings.trimmedSessionID
            let candidate =
                remembered.isEmpty
                ? sessions.first(where: { $0.status == .active })?.id : remembered
            if let candidate { await selectSession(candidate) }
        } catch {
            guard generation == current else { return }
            sessionOperationError = "Unable to refresh sessions. Check your connection and retry."
        }
    }

    func selectSession(_ rawID: String) async {
        guard isAuthenticated, let client = makeAPIClient() else { return }
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let current = generation
        let choice = UUID()
        selectionGeneration = choice
        sessionOperationError = nil
        do {
            let session = try await client.getSession(id: id)
            guard generation == current, selectionGeneration == choice else { return }
            guard session.status == .active else { throw APIError.sessionClosed }
            activeSession = session
            settings.sessionID = session.id
            sessions.removeAll { $0.id == session.id }
            sessions.insert(session, at: 0)
            captureCoordinator.markSessionValidated()
        } catch {
            guard generation == current, selectionGeneration == choice else { return }
            sessionOperationError = "Session not found or unavailable to this account."
            if error as? APIError != .invalidSession && error as? APIError != .sessionClosed
                && error as? APIError != .badRequest
            {
                sessionOperationError =
                    "Unable to validate the session. Check your connection and retry."
            } else if settings.trimmedSessionID == id {
                activeSession = nil
                captureCoordinator.settingsDidChange(
                    sessionID: "", accessToken: settings.accessToken)
                sessionOperationError =
                    "Your previous session is unavailable. Select or create a session."
            }
        }
        updateTriggerMonitoring()
    }

    func startNewSession() async {
        guard isAuthenticated, !isSessionOperationInProgress, let client = makeAPIClient() else {
            return
        }
        let current = generation
        let choice = UUID()
        selectionGeneration = choice
        isSessionOperationInProgress = true
        sessionOperationError = nil
        defer {
            if generation == current {
                isSessionOperationInProgress = false
                updateTriggerMonitoring()
            }
        }
        do {
            let session = try await client.createSession()
            guard generation == current, selectionGeneration == choice else { return }
            activeSession = session
            settings.sessionID = session.id
            sessions.insert(session, at: 0)
            captureCoordinator.markSessionValidated()
            Task { await refreshSessions() }
        } catch {
            guard generation == current else { return }
            sessionOperationError =
                "Unable to create a session. Refresh sessions before retrying if the connection was interrupted."
        }
    }

    func testConnection() async {
        guard !checkingConnection,
            let url = URL(string: settings.apiBaseURL)?.appendingPathComponent("health")
        else { return }
        checkingConnection = true
        connectionTitle = "Checking…"
        defer {
            checkingConnection = false
            updateTriggerMonitoring()
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            connectionTitle =
                (response as? HTTPURLResponse)?.statusCode == 200
                ? "Server reachable" : "Cannot reach server"
        } catch { connectionTitle = "Cannot reach server" }
    }
    private func makeAPIClient() -> (any MtihaniAPIClient)? {
        guard case .success(let configuration) = settings.configuration else { return nil }
        return apiClientFactory(configuration)
    }
    private func bindState() {
        for publisher in [
            settings.objectWillChange.eraseToAnyPublisher(),
            permissions.objectWillChange.eraseToAnyPublisher(),
            captureCoordinator.objectWillChange.eraseToAnyPublisher(),
        ] {
            publisher.sink { [weak self] _ in
                self?.objectWillChange.send()
                Task { @MainActor [weak self] in self?.updateTriggerMonitoring() }
            }.store(in: &cancellables)
        }
        authentication?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            Task { @MainActor [weak self] in self?.updateTriggerMonitoring() }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.permissions.refreshScreenRecordingPermission()
                self?.updateTriggerMonitoring()
            }.store(in: &cancellables)
    }
    private func updateTriggerMonitoring() {
        guard isStarted, settings.isTripleClickEnabled, canCapture else {
            triggerMonitor.stop()
            triggerIsMonitoring = false
            return
        }
        if !triggerIsMonitoring { triggerIsMonitoring = triggerMonitor.start() }
    }
}
