import Combine
import XCTest

@testable import mtihani_macos

@MainActor
final class UpdateManagerTests: XCTestCase {
    func testStartsOneUpdaterAndDoesNotOverwriteUserPreferences() {
        let driver = MockUpdateDriver()
        driver.changes.value.automaticallyChecksForUpdates = false
        driver.changes.value.automaticallyDownloadsUpdates = true
        let manager = UpdateManager(driver: driver)

        manager.start()
        manager.start()

        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.preferenceWrites, 0)
        XCTAssertFalse(manager.automaticallyChecksForUpdates)
        XCTAssertTrue(manager.automaticallyDownloadsUpdates)
    }

    func testManualCheckHonorsAvailabilityAndRecoversAfterBusyState() {
        let driver = MockUpdateDriver()
        let manager = UpdateManager(driver: driver)
        manager.start()

        manager.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)

        driver.changes.value.canCheckForUpdates = false
        manager.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)

        driver.changes.value.canCheckForUpdates = true
        manager.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 2)
    }

    func testPreferencesWriteThroughAndExternalChangesReachSettings() {
        let driver = MockUpdateDriver()
        let manager = UpdateManager(driver: driver)
        manager.start()

        manager.automaticallyDownloadsUpdates = true
        XCTAssertTrue(driver.state.automaticallyDownloadsUpdates)
        manager.automaticallyChecksForUpdates = false
        XCTAssertFalse(driver.state.automaticallyChecksForUpdates)

        // Sparkle's own dialog can change preferences independently of Settings.
        driver.changes.value.automaticallyChecksForUpdates = true
        driver.changes.value.automaticallyDownloadsUpdates = false
        XCTAssertTrue(manager.automaticallyChecksForUpdates)
        XCTAssertFalse(manager.automaticallyDownloadsUpdates)
        XCTAssertEqual(driver.preferenceWrites, 2)

        let reopenedSettings = UpdateManager(driver: driver)
        XCTAssertEqual(reopenedSettings.state, manager.state)
        XCTAssertEqual(driver.preferenceWrites, 2)
    }

    func testAutomaticDownloadsCannotBeEnabledWhenUnsupported() {
        let driver = MockUpdateDriver()
        let manager = UpdateManager(driver: driver)
        driver.changes.value.allowsAutomaticUpdates = false

        manager.automaticallyDownloadsUpdates = true

        XCTAssertFalse(driver.state.automaticallyDownloadsUpdates)
        XCTAssertEqual(driver.preferenceWrites, 0)
    }

    func testStartupFailureDoesNotCrashAndManualCheckingStaysDisabled() {
        let driver = MockUpdateDriver()
        driver.startError = UpdateConfiguration.ConfigurationError.missingPublicKey
        let manager = UpdateManager(driver: driver)

        manager.start()
        manager.checkForUpdates()

        XCTAssertNotNil(manager.startupError)
        XCTAssertFalse(manager.state.canCheckForUpdates)
        XCTAssertEqual(driver.checkCount, 0)
    }

    func testBackgroundReminderUpdatesAndClears() {
        let driver = MockUpdateDriver()
        let manager = UpdateManager(driver: driver)
        driver.changes.value.updateAvailable = true
        XCTAssertTrue(manager.state.updateAvailable)
        driver.changes.value.updateAvailable = false
        XCTAssertFalse(manager.state.updateAvailable)
    }
}

@MainActor
private final class MockUpdateDriver: UpdateDriving {
    let changes = CurrentValueSubject<UpdateState, Never>(
        UpdateState(
            automaticallyChecksForUpdates: true, allowsAutomaticUpdates: true
        ))
    var state: UpdateState { changes.value }
    var stateChanges: AnyPublisher<UpdateState, Never> { changes.eraseToAnyPublisher() }
    var startError: Error?
    private(set) var startCount = 0
    private(set) var checkCount = 0
    private(set) var preferenceWrites = 0

    func start() throws {
        startCount += 1
        if let startError { throw startError }
        changes.value.canCheckForUpdates = true
    }

    func checkForUpdates() { checkCount += 1 }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        preferenceWrites += 1
        changes.value.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        preferenceWrites += 1
        changes.value.automaticallyDownloadsUpdates = enabled
    }
}
