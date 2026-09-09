import XCTest

@testable import mtihani_macos

@MainActor
final class UpdateConfigurationTests: XCTestCase {
    func testVersionReadsBundleMetadata() throws {
        try withBundle([
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
        ]) { bundle in
            let version = AppVersion(bundle: bundle)
            XCTAssertEqual(version.marketingVersion, "1.2.3")
            XCTAssertEqual(version.buildNumber, "42")
            XCTAssertEqual(version.displayString, "1.2.3 (42)")
        }
    }

    func testMissingVersionHasReadableFallback() throws {
        try withBundle([:]) { bundle in
            XCTAssertEqual(AppVersion(bundle: bundle).displayString, "Unknown (Unknown)")
        }
    }

    func testHTTPSFeedAndPublicKeyAreRequired() throws {
        // Synthetic public bytes; this fixture has no private signing key.
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        try withBundle(["SUFeedURL": "https://updates.example.test/appcast.xml", "SUPublicEDKey": key]) {
            XCTAssertNoThrow(try UpdateConfiguration.validate(bundle: $0))
        }
        for feed in [
            "http://updates.example.test/appcast.xml", "file:///appcast.xml", "", "$(SPARKLE_FEED_URL)",
        ] {
            try withBundle(["SUFeedURL": feed, "SUPublicEDKey": key]) {
                XCTAssertThrowsError(try UpdateConfiguration.validate(bundle: $0))
            }
        }
        for invalidKey in [
            "", "$(SPARKLE_PUBLIC_ED_KEY)", "not-a-key", Data(repeating: 1, count: 31).base64EncodedString(),
        ] {
            try withBundle([
                "SUFeedURL": "https://updates.example.test/appcast.xml", "SUPublicEDKey": invalidKey,
            ]) {
                XCTAssertThrowsError(try UpdateConfiguration.validate(bundle: $0))
            }
        }
    }

    func testBundledUpdatePolicyAndSandboxIntegration() {
        let bundle = Bundle.main
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool, true)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool, false)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? Int, 86_400)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUEnableInstallerLauncherService") as? Bool, true)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool, true)
        XCTAssertNil(bundle.object(forInfoDictionaryKey: "SUEnableDownloaderService"))
        XCTAssertTrue(
            (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.hasPrefix("https://") == true)
    }

    private func withBundle(_ metadata: [String: Any], assertions: (Bundle) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "UpdateTests-\(UUID()).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var info = metadata
        info["CFBundleIdentifier"] = "test.mtihani.\(UUID().uuidString)"
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: directory.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: directory))
        try assertions(bundle)
    }
}
