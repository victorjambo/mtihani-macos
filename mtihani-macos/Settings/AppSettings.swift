import Combine
import Foundation

enum PreferredLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case typeScript
    case javaScript
    case python
    case java
    case go
    case rust
    case cpp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            "Auto"
        case .typeScript:
            "TypeScript"
        case .javaScript:
            "JavaScript"
        case .python:
            "Python"
        case .java:
            "Java"
        case .go:
            "Go"
        case .rust:
            "Rust"
        case .cpp:
            "C++"
        }
    }

    var apiValue: String? {
        switch self {
        case .automatic:
            nil
        case .typeScript:
            "typescript"
        case .javaScript:
            "javascript"
        case .python:
            "python"
        case .java:
            "java"
        case .go:
            "go"
        case .rust:
            "rust"
        case .cpp:
            "cpp"
        }
    }
}

enum AppConfigurationError: LocalizedError, Equatable {
    case invalidBackendURL
    case insecureRemoteBackend
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            "Enter a valid HTTP or HTTPS backend URL."
        case .insecureRemoteBackend:
            "Use HTTPS for remote backends. HTTP is allowed only for local development."
        case .missingAccessToken:
            "Sign in to connect your account."
        }
    }
}

struct AppConfiguration: Equatable, Sendable {
    let apiBaseURL: URL
    let accessToken: String

    init(apiBaseURL: String, accessToken: String) throws {
        let value = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw AppConfigurationError.invalidBackendURL
        }

        if scheme == "http" {
            let host = components.host?.lowercased()
            // Foundation preserves the brackets around an IPv6 literal here.
            let loopbackHosts = ["localhost", "127.0.0.1", "::1", "[::1]"]
            guard let host, loopbackHosts.contains(host) else {
                throw AppConfigurationError.insecureRemoteBackend
            }
        }

        components.scheme = scheme
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        guard let url = components.url else {
            throw AppConfigurationError.invalidBackendURL
        }

        let trimmedAccessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccessToken.isEmpty else {
            throw AppConfigurationError.missingAccessToken
        }

        self.apiBaseURL = url
        self.accessToken = trimmedAccessToken
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let defaultRequiredClickCount = 3
    static let requiredClickCountRange = 3...6

    let apiBaseURL: String

    @Published var sessionID: String {
        didSet { if let accountID { defaults.set(sessionID, forKey: selectionKey(accountID)) } }
    }

    @Published var accessToken: String = ""
    private(set) var accountID: String?

    func useAccount(_ id: String?) {
        accountID = id
        sessionID = id.flatMap { defaults.string(forKey: selectionKey($0)) } ?? ""
    }

    private func selectionKey(_ id: String) -> String { "session.\(apiBaseURL).\(id)" }

    @Published var preferredLanguage: PreferredLanguage {
        didSet {
            defaults.set(preferredLanguage.rawValue, forKey: Keys.preferredLanguage)
        }
    }

    @Published var isTripleClickEnabled: Bool {
        didSet {
            defaults.set(isTripleClickEnabled, forKey: Keys.isTripleClickEnabled)
        }
    }

    @Published var requiredClickCount: Int {
        didSet {
            let bounded = min(max(requiredClickCount, 3), 6)
            if requiredClickCount != bounded { requiredClickCount = bounded }
            defaults.set(requiredClickCount, forKey: Keys.requiredClickCount)
        }
    }

    var trimmedSessionID: String {
        sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAccessToken: String {
        accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var configuration: Result<AppConfiguration, AppConfigurationError> {
        do {
            return .success(
                try AppConfiguration(apiBaseURL: apiBaseURL, accessToken: accessToken)
            )
        } catch let error as AppConfigurationError {
            return .failure(error)
        } catch {
            return .failure(.invalidBackendURL)
        }
    }

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        apiBaseURL: String = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
    ) {
        self.defaults = defaults
        self.apiBaseURL = apiBaseURL
        sessionID = ""
        defaults.removeObject(forKey: "settings.apiKey")
        defaults.removeObject(forKey: "settings.accessToken")
        preferredLanguage =
            defaults
            .string(forKey: Keys.preferredLanguage)
            .flatMap(PreferredLanguage.init(rawValue:))
            ?? .automatic

        if defaults.object(forKey: Keys.isTripleClickEnabled) == nil {
            isTripleClickEnabled = true
        } else {
            isTripleClickEnabled = defaults.bool(forKey: Keys.isTripleClickEnabled)
        }

        let savedClickCount =
            defaults.object(forKey: Keys.requiredClickCount)
            .flatMap { $0 as? NSNumber }?
            .intValue ?? Self.defaultRequiredClickCount
        requiredClickCount = min(
            max(savedClickCount, Self.requiredClickCountRange.lowerBound),
            Self.requiredClickCountRange.upperBound
        )
    }

    private enum Keys {
        static let preferredLanguage = "settings.preferredLanguage"
        static let isTripleClickEnabled = "settings.tripleClickEnabled"
        static let requiredClickCount = "settings.requiredClickCount"
    }
}
