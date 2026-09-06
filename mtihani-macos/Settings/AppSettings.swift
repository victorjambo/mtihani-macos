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
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            "Enter a valid HTTP or HTTPS backend URL."
        case .insecureRemoteBackend:
            "Use HTTPS for remote backends. HTTP is allowed only for local development."
        case .missingAPIKey:
            "Enter the backend API key."
        }
    }
}

struct AppConfiguration: Equatable, Sendable {
    let apiBaseURL: URL
    let apiKey: String

    init(backendURL: String, apiKey: String) throws {
        let value = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw AppConfigurationError.missingAPIKey
        }

        apiBaseURL = url
        self.apiKey = trimmedAPIKey
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let developmentBackendURL = "http://localhost:5173/api"
    static let defaultRequiredClickCount = 3
    static let requiredClickCountRange = 2 ... 5

    @Published var backendURL: String {
        didSet { defaults.set(backendURL, forKey: Keys.backendURL) }
    }

    @Published var sessionID: String {
        didSet { defaults.set(sessionID, forKey: Keys.sessionID) }
    }

    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
    }

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
            defaults.set(requiredClickCount, forKey: Keys.requiredClickCount)
        }
    }

    var trimmedSessionID: String {
        sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var configuration: Result<AppConfiguration, AppConfigurationError> {
        do {
            return .success(
                try AppConfiguration(backendURL: backendURL, apiKey: apiKey)
            )
        } catch let error as AppConfigurationError {
            return .failure(error)
        } catch {
            return .failure(.invalidBackendURL)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        backendURL = defaults.string(forKey: Keys.backendURL)
            ?? Self.developmentBackendURL
        sessionID = defaults.string(forKey: Keys.sessionID) ?? ""
        apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        preferredLanguage = defaults
            .string(forKey: Keys.preferredLanguage)
            .flatMap(PreferredLanguage.init(rawValue:))
            ?? .automatic

        if defaults.object(forKey: Keys.isTripleClickEnabled) == nil {
            isTripleClickEnabled = true
        } else {
            isTripleClickEnabled = defaults.bool(forKey: Keys.isTripleClickEnabled)
        }

        let savedClickCount = defaults.object(forKey: Keys.requiredClickCount)
            .flatMap { $0 as? NSNumber }?
            .intValue ?? Self.defaultRequiredClickCount
        requiredClickCount = min(
            max(savedClickCount, Self.requiredClickCountRange.lowerBound),
            Self.requiredClickCountRange.upperBound
        )
    }

    private enum Keys {
        static let backendURL = "settings.backendURL"
        static let sessionID = "settings.sessionID"
        static let apiKey = "settings.apiKey"
        static let preferredLanguage = "settings.preferredLanguage"
        static let isTripleClickEnabled = "settings.tripleClickEnabled"
        static let requiredClickCount = "settings.requiredClickCount"
    }
}
