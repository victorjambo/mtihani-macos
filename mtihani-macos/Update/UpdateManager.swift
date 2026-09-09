import Combine
import Foundation
import OSLog

/// A snapshot for SwiftUI, not a second preference store. Sparkle owns persistence.
struct UpdateState: Equatable {
    var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var allowsAutomaticUpdates = false
    var updateAvailable = false
}

@MainActor
protocol UpdateDriving: AnyObject {
    var state: UpdateState { get }
    var stateChanges: AnyPublisher<UpdateState, Never> { get }
    func start() throws
    func checkForUpdates()
    func setAutomaticallyChecksForUpdates(_ enabled: Bool)
    func setAutomaticallyDownloadsUpdates(_ enabled: Bool)
}

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var state: UpdateState
    @Published private(set) var startupError: String?

    private let driver: any UpdateDriving
    private let logger: Logger
    private var observation: AnyCancellable?
    private var isStarted = false

    convenience init() {
        self.init(driver: SparkleUpdateDriver())
    }

    init(
        driver: any UpdateDriving,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.victorjambo.mtihani-macos",
            category: "updates"
        )
    ) {
        self.driver = driver
        self.logger = logger
        state = driver.state
        observation = driver.stateChanges.sink { [weak self] state in
            self?.state = state
        }
    }

    /// Called once at application launch, never from a view or capture request.
    func start() {
        guard !isStarted else { return }
        do {
            try driver.start()
            isStarted = true
            startupError = nil
        } catch {
            startupError = "Updates are unavailable for this build. Check the update configuration."
            logger.error("Updater could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkForUpdates() {
        guard state.canCheckForUpdates else { return }
        driver.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { state.automaticallyChecksForUpdates }
        set { driver.setAutomaticallyChecksForUpdates(newValue) }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { state.automaticallyDownloadsUpdates }
        set {
            guard state.allowsAutomaticUpdates else { return }
            driver.setAutomaticallyDownloadsUpdates(newValue)
        }
    }
}
