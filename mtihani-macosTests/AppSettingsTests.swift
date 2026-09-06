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
        XCTAssertEqual(settings.preferredLanguage, .automatic)
        XCTAssertTrue(settings.isTripleClickEnabled)
    }

    func testValuesPersistAcrossInstances() {
        var settings: AppSettings? = AppSettings(defaults: defaults)
        settings?.backendURL = "https://api.example.com/api/"
        settings?.sessionID = " 67df49c6-c3bf-40d5-ab0b-cd91bbad0f32 "
        settings?.preferredLanguage = .python
        settings?.isTripleClickEnabled = false
        settings = nil

        let restored = AppSettings(defaults: defaults)

        XCTAssertEqual(restored.backendURL, "https://api.example.com/api/")
        XCTAssertEqual(
            restored.trimmedSessionID,
            "67df49c6-c3bf-40d5-ab0b-cd91bbad0f32"
        )
        XCTAssertEqual(restored.preferredLanguage, .python)
        XCTAssertFalse(restored.isTripleClickEnabled)
    }

    func testConfigurationNormalizesTrailingSlash() throws {
        let configuration = try AppConfiguration(
            backendURL: " https://api.example.com/api/// "
        )

        XCTAssertEqual(
            configuration.apiBaseURL.absoluteString,
            "https://api.example.com/api"
        )
    }

    func testConfigurationRejectsCredentialsAndUnsupportedSchemes() {
        XCTAssertThrowsError(
            try AppConfiguration(backendURL: "ftp://api.example.com/api")
        )
        XCTAssertThrowsError(
            try AppConfiguration(backendURL: "https://user:secret@example.com/api")
        )
    }

    func testConfigurationAllowsHTTPOnlyForLoopbackDevelopmentHosts() throws {
        XCTAssertNoThrow(
            try AppConfiguration(backendURL: "http://localhost:5173/api")
        )
        XCTAssertNoThrow(
            try AppConfiguration(backendURL: "http://127.0.0.1:5173/api")
        )
        XCTAssertNoThrow(
            try AppConfiguration(backendURL: "http://[::1]:5173/api")
        )

        XCTAssertThrowsError(
            try AppConfiguration(backendURL: "http://api.example.com/api")
        ) { error in
            XCTAssertEqual(
                error as? AppConfigurationError,
                .insecureRemoteBackend
            )
        }
    }
}
