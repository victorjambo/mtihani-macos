import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let settings: AppSettings
    let permissions: PermissionsService
    let captureCoordinator: CaptureCoordinator

    @Published private(set) var triggerIsMonitoring = false

    var triggerStatusTitle: String {
        if !settings.isTripleClickEnabled {
            return "Disabled"
        }
        return triggerIsMonitoring ? "Active" : "Unavailable"
    }

    private let triggerMonitor: any CaptureTriggerMonitor
    private let settingsValidationDelayNanoseconds: UInt64
    private var cancellables = Set<AnyCancellable>()
    private var startupValidationTask: Task<Void, Never>?
    private var settingsValidationTask: Task<Void, Never>?
    private var isStarted = false

    init(
        settings: AppSettings,
        permissions: PermissionsService,
        captureCoordinator: CaptureCoordinator,
        triggerMonitor: any CaptureTriggerMonitor,
        settingsValidationDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.settings = settings
        self.permissions = permissions
        self.captureCoordinator = captureCoordinator
        self.triggerMonitor = triggerMonitor
        self.settingsValidationDelayNanoseconds = settingsValidationDelayNanoseconds
        bindState()
    }

    static func live() -> AppState {
        let settings = AppSettings()
        let permissions = PermissionsService()
        let screenCapturer = ScreenCaptureService(
            permissionService: permissions
        )
        let captureCoordinator = CaptureCoordinator(
            settings: settings,
            screenCapturer: screenCapturer,
            permissionService: permissions,
            apiClientFactory: { baseURL in
                URLSessionMtihaniAPIClient(baseURL: baseURL)
            }
        )
        let triggerMonitor = GlobalClickMonitor {
            Task {
                await captureCoordinator.captureAndUpload()
            }
        }

        return AppState(
            settings: settings,
            permissions: permissions,
            captureCoordinator: captureCoordinator,
            triggerMonitor: triggerMonitor
        )
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        permissions.refreshScreenRecordingPermission()
        updateTriggerMonitoring()

        if !settings.trimmedSessionID.isEmpty {
            startupValidationTask = Task { [weak self] in
                await self?.captureCoordinator.validateSession()
            }
        }
    }

    func stop() {
        startupValidationTask?.cancel()
        startupValidationTask = nil
        settingsValidationTask?.cancel()
        settingsValidationTask = nil
        triggerMonitor.stop()
        triggerIsMonitoring = false
        isStarted = false
    }

    func quit() {
        stop()
        NSApplication.shared.terminate(nil)
    }

    func requestScreenRecordingPermission() {
        permissions.requestScreenRecordingPermissionIfNeeded()
    }

    private func bindState() {
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        captureCoordinator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        permissions.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.$isTripleClickEnabled
            .dropFirst()
            .sink { [weak self] isEnabled in
                self?.updateTriggerMonitoring(isEnabled: isEnabled)
            }
            .store(in: &cancellables)

        settings.$sessionID
            .dropFirst()
            .sink { [weak self] sessionID in
                guard let self else { return }
                self.handleConnectionSettingsChange(
                    sessionID: sessionID,
                    backendURL: self.settings.backendURL
                )
            }
            .store(in: &cancellables)

        settings.$backendURL
            .dropFirst()
            .sink { [weak self] backendURL in
                guard let self else { return }
                self.handleConnectionSettingsChange(
                    sessionID: self.settings.sessionID,
                    backendURL: backendURL
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )
        .sink { [weak self] _ in
            self?.permissions.refreshScreenRecordingPermission()
            self?.updateTriggerMonitoring()
        }
        .store(in: &cancellables)
    }

    private func updateTriggerMonitoring(isEnabled: Bool? = nil) {
        guard isStarted, isEnabled ?? settings.isTripleClickEnabled else {
            triggerMonitor.stop()
            triggerIsMonitoring = false
            return
        }

        triggerIsMonitoring = triggerMonitor.start()
    }

    private func handleConnectionSettingsChange(
        sessionID: String,
        backendURL: String
    ) {
        startupValidationTask?.cancel()
        startupValidationTask = nil
        captureCoordinator.settingsDidChange(
            sessionID: sessionID,
            backendURL: backendURL
        )
        settingsValidationTask?.cancel()

        let trimmedSessionID = sessionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            isStarted,
            !trimmedSessionID.isEmpty,
            (try? AppConfiguration(backendURL: backendURL)) != nil
        else {
            return
        }

        settingsValidationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(
                nanoseconds: self.settingsValidationDelayNanoseconds
            )
            guard !Task.isCancelled else {
                return
            }
            await self.captureCoordinator.validateSession()
        }
    }
}
