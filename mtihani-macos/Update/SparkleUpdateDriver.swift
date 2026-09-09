import Combine
import Foundation
import OSLog
import Sparkle

/// The only owner of a Sparkle controller. Sparkle owns checking, downloading,
/// verification, installation, scheduling, normal error UI, and preferences.
@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriving, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    private let changes = CurrentValueSubject<UpdateState, Never>(UpdateState())
    private var observations = Set<AnyCancellable>()
    private var updateAvailable = false
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.victorjambo.mtihani-macos",
        category: "updates"
    )

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        let updater = controller.updater
        Publishers.MergeMany(
            updater.publisher(for: \.canCheckForUpdates).map { _ in () }.eraseToAnyPublisher(),
            updater.publisher(for: \.automaticallyChecksForUpdates).map { _ in () }.eraseToAnyPublisher(),
            updater.publisher(for: \.automaticallyDownloadsUpdates).map { _ in () }.eraseToAnyPublisher(),
            updater.publisher(for: \.allowsAutomaticUpdates).map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in self?.publishState() }
        .store(in: &observations)
    }

    var state: UpdateState { changes.value }
    var stateChanges: AnyPublisher<UpdateState, Never> { changes.eraseToAnyPublisher() }

    func start() throws {
        try UpdateConfiguration.validate(bundle: .main)
        // Calling the throwing API lets incomplete development configuration be
        // reported in Settings without showing a launch-time modal alert.
        try controller.updater.start()
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    // A dockless app needs a noticeable reminder for alerts that Sparkle shows
    // behind other apps. The status item and popover expose this reminder;
    // Sparkle still presents and focuses all update dialogs itself.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        updateAvailable = !state.userInitiated
        publishState()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = false
        publishState()
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
        publishState()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // Avoid logging URLs, response bodies, or any credentials in userInfo.
        let error = error as NSError
        logger.error("Update session ended: \(error.domain, privacy: .public) (\(error.code))")
    }

    private func publishState() {
        let updater = controller.updater
        changes.send(
            UpdateState(
                canCheckForUpdates: updater.canCheckForUpdates,
                automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
                automaticallyDownloadsUpdates: updater.automaticallyDownloadsUpdates,
                allowsAutomaticUpdates: updater.allowsAutomaticUpdates,
                updateAvailable: updateAvailable
            ))
    }
}

enum UpdateConfiguration {
    static func validate(bundle: Bundle) throws {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        guard let url = URL(string: feed), url.scheme == "https", url.host?.isEmpty == false else {
            throw ConfigurationError.insecureFeed
        }
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard Data(base64Encoded: publicKey)?.count == 32 else {
            throw ConfigurationError.missingPublicKey
        }
    }

    enum ConfigurationError: LocalizedError {
        case insecureFeed
        case missingPublicKey

        var errorDescription: String? {
            switch self {
            case .insecureFeed: "SUFeedURL must be a valid HTTPS URL."
            case .missingPublicKey: "Configure SUPublicEDKey with the public key from Sparkle generate_keys."
            }
        }
    }
}
