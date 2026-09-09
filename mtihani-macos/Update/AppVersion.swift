import Foundation

struct AppVersion: Equatable {
    let marketingVersion: String
    let buildNumber: String

    init(bundle: Bundle = .main) {
        marketingVersion =
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var displayString: String {
        "\(marketingVersion) (\(buildNumber))"
    }
}
