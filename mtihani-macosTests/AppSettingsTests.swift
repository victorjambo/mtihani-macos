import XCTest
@testable import mtihani_macos

@MainActor
final class AppSettingsTests: XCTestCase {
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
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.backendURL, "http://localhost:5173/api")
        XCTAssertEqual(settings.sessionID, "")
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertEqual(settings.preferredLanguage, .automatic)
        XCTAssertTrue(settings.isTripleClickEnabled)
        XCTAssertEqual(settings.requiredClickCount, 3)
    }

    func testValuesPersistAcrossInstances() {
        var settings: AppSettings? = AppSettings(defaults: defaults)
        settings?.backendURL = "https://api.example.com/api/"
        settings?.sessionID = " 67df49c6-c3bf-40d5-ab0b-cd91bbad0f32 "
        settings?.apiKey = " secret-api-key "
        settings?.preferredLanguage = .python
        settings?.isTripleClickEnabled = false
        settings?.requiredClickCount = 4
        settings = nil

        let restored = AppSettings(defaults: defaults)

        XCTAssertEqual(restored.backendURL, "https://api.example.com/api/")
        XCTAssertEqual(
            restored.trimmedSessionID,
            "67df49c6-c3bf-40d5-ab0b-cd91bbad0f32"
        )
        XCTAssertEqual(restored.preferredLanguage, .python)
        XCTAssertEqual(restored.trimmedAPIKey, "secret-api-key")
        XCTAssertFalse(restored.isTripleClickEnabled)
        XCTAssertEqual(restored.requiredClickCount, 4)
    }

    func testPersistedClickCountIsClampedToSupportedRange() {
        defaults.set(99, forKey: "settings.requiredClickCount")

        XCTAssertEqual(AppSettings(defaults: defaults).requiredClickCount, 5)
    }

    func testConfigurationNormalizesTrailingSlash() throws {
        let configuration = try AppConfiguration(
            backendURL: " https://api.example.com/api/// ",
            apiKey: "test-api-key"
        )

        XCTAssertEqual(
            configuration.apiBaseURL.absoluteString,
            "https://api.example.com/api"
        )
    }

    func testConfigurationRejectsCredentialsAndUnsupportedSchemes() {
        XCTAssertThrowsError(
            try AppConfiguration(backendURL: "ftp://api.example.com/api", apiKey: "key")
        )
        XCTAssertThrowsError(
            try AppConfiguration(
                backendURL: "https://user:secret@example.com/api",
                apiKey: "key"
            )
        )
    }

    func testConfigurationAllowsHTTPOnlyForLoopbackDevelopmentHosts() throws {
        XCTAssertNoThrow(
            try AppConfiguration(backendURL: "http://localhost:5173/api", apiKey: "key")
        )
        XCTAssertNoThrow(
            try AppConfiguration(backendURL: "http://127.0.0.1:5173/api", apiKey: "key")
        )
        XCTAssertNoThrow(
            try AppConfiguration(backendURL: "http://[::1]:5173/api", apiKey: "key")
        )

        XCTAssertThrowsError(
            try AppConfiguration(backendURL: "http://api.example.com/api", apiKey: "key")
        ) { error in
            XCTAssertEqual(
                error as? AppConfigurationError,
                .insecureRemoteBackend
            )
        }
    }
}
