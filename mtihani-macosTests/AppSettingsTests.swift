import XCTest

@testable import mtihani_macos

@MainActor
final class AppSettingsTests: XCTestCase {
    private let apiBaseURL = "http://localhost:5173/api"
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsAreSuitableForLocalDevelopment() {
        let settings = AppSettings(defaults: defaults, apiBaseURL: apiBaseURL)

        XCTAssertEqual(settings.apiBaseURL, apiBaseURL)
        XCTAssertEqual(settings.sessionID, "")
        XCTAssertEqual(settings.accessToken, "")
        XCTAssertEqual(settings.preferredLanguage, .automatic)
        XCTAssertTrue(settings.isTripleClickEnabled)
        XCTAssertEqual(settings.requiredClickCount, 3)
        XCTAssertEqual(settings.bufferWindowSeconds, 10)
    }

    func testValuesPersistAcrossInstances() {
        var settings: AppSettings? = AppSettings(defaults: defaults, apiBaseURL: apiBaseURL)
        settings?.useAccount("account-a")
        settings?.sessionID = " 67df49c6-c3bf-40d5-ab0b-cd91bbad0f32 "
        settings?.accessToken = " secret-api-key "
        settings?.preferredLanguage = .python
        settings?.isTripleClickEnabled = false
        settings?.requiredClickCount = 4
        settings?.bufferWindowSeconds = 20
        settings = nil

        let restored = AppSettings(defaults: defaults, apiBaseURL: apiBaseURL)
        restored.useAccount("account-a")

        XCTAssertEqual(restored.apiBaseURL, apiBaseURL)
        XCTAssertEqual(
            restored.trimmedSessionID,
            "67df49c6-c3bf-40d5-ab0b-cd91bbad0f32"
        )
        XCTAssertEqual(restored.preferredLanguage, .python)
        XCTAssertEqual(restored.trimmedAccessToken, "")
        restored.useAccount("account-b")
        XCTAssertEqual(restored.sessionID, "")
        XCTAssertFalse(restored.isTripleClickEnabled)
        XCTAssertEqual(restored.requiredClickCount, 4)
        XCTAssertEqual(restored.bufferWindowSeconds, 20)
    }

    func testPersistedClickCountIsClampedToSupportedRange() {
        defaults.set(99, forKey: "settings.requiredClickCount")

        XCTAssertEqual(
            AppSettings(defaults: defaults, apiBaseURL: apiBaseURL).requiredClickCount,
            6
        )
    }

    func testRuntimeClickCountIsClampedAndSecretsAreRemovedFromDefaults() {
        defaults.set("legacy-secret", forKey: "settings.apiKey")
        let settings = AppSettings(defaults: defaults, apiBaseURL: apiBaseURL)
        settings.requiredClickCount = 2
        XCTAssertEqual(settings.requiredClickCount, 3)
        settings.requiredClickCount = 10
        XCTAssertEqual(settings.requiredClickCount, 6)
        settings.accessToken = "memory-only"
        XCTAssertNil(defaults.object(forKey: "settings.apiKey"))
        XCTAssertNil(defaults.object(forKey: "settings.accessToken"))
    }

    func testPersistedBufferWindowIsClampedToSupportedRange() {
        defaults.set(999, forKey: "settings.bufferWindowSeconds")

        XCTAssertEqual(
            AppSettings(defaults: defaults, apiBaseURL: apiBaseURL).bufferWindowSeconds,
            60
        )
    }

    func testRuntimeBufferWindowIsClamped() {
        let settings = AppSettings(defaults: defaults, apiBaseURL: apiBaseURL)
        settings.bufferWindowSeconds = 1
        XCTAssertEqual(settings.bufferWindowSeconds, 5)
        settings.bufferWindowSeconds = 999
        XCTAssertEqual(settings.bufferWindowSeconds, 60)
    }

    func testConfigurationNormalizesTrailingSlash() throws {
        let configuration = try AppConfiguration(
            apiBaseURL: " https://api.example.com/api/// ",
            accessToken: "test-api-key"
        )

        XCTAssertEqual(
            configuration.apiBaseURL.absoluteString,
            "https://api.example.com/api"
        )
    }

    func testConfigurationRejectsCredentialsAndUnsupportedSchemes() {
        XCTAssertThrowsError(
            try AppConfiguration(apiBaseURL: "ftp://api.example.com/api", accessToken: "key")
        )
        XCTAssertThrowsError(
            try AppConfiguration(
                apiBaseURL: "https://user:secret@example.com/api",
                accessToken: "key"
            )
        )
    }

    func testConfigurationAllowsHTTPOnlyForLoopbackDevelopmentHosts() throws {
        XCTAssertNoThrow(
            try AppConfiguration(apiBaseURL: "http://localhost:5173/api", accessToken: "key")
        )
        XCTAssertNoThrow(
            try AppConfiguration(apiBaseURL: "http://127.0.0.1:5173/api", accessToken: "key")
        )
        XCTAssertNoThrow(
            try AppConfiguration(apiBaseURL: "http://[::1]:5173/api", accessToken: "key")
        )

        XCTAssertThrowsError(
            try AppConfiguration(apiBaseURL: "http://api.example.com/api", accessToken: "key")
        ) { error in
            XCTAssertEqual(
                error as? AppConfigurationError,
                .insecureRemoteBackend
            )
        }
    }
}
