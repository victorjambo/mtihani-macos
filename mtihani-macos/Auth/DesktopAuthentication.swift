import AppKit
import AuthenticationServices
import Combine
import CryptoKit
import Security

nonisolated struct DesktopAccount: Codable, Equatable, Sendable {
    let id: String
    let name: String?
    let email: String?
    let avatarUrl: String?
}

nonisolated struct DeviceCredential: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: String
    let user: DesktopAccount
}

enum AuthenticationState: Equatable {
    case restoring, signedOut, signingIn, signedIn, reauthenticationRequired
}

@MainActor
final class DesktopAuthentication: NSObject, ObservableObject,
    ASWebAuthenticationPresentationContextProviding
{
    @Published private(set) var state: AuthenticationState = .restoring
    @Published private(set) var account: DesktopAccount?
    @Published private(set) var message: String?
    private(set) var credential: DeviceCredential?
    private(set) var generation = UUID()
    private let apiURL: URL
    let frontendURL: URL
    let environment: String
    let callback: String
    private var attempt = UUID()
    private var webSession: ASWebAuthenticationSession?
    private var refreshTask: Task<DeviceCredential, Error>?
    private let keychainService: String
    private let transport: any HTTPTransport
    private let credentialReader: (() throws -> DeviceCredential?)?
    private let credentialWriter: ((DeviceCredential) throws -> Void)?
    private let credentialDeleter: (() -> OSStatus)?
    var didChangeAccount: (() -> Void)?

    init(
        apiURL: URL, frontendURL: URL, environment: String,
        transport: (any HTTPTransport)? = nil,
        credentialReader: (() throws -> DeviceCredential?)? = nil,
        credentialWriter: ((DeviceCredential) throws -> Void)? = nil,
        credentialDeleter: (() -> OSStatus)? = nil
    ) {
        self.transport = transport ?? URLSessionHTTPTransport()
        self.credentialReader = credentialReader
        self.credentialWriter = credentialWriter
        self.credentialDeleter = credentialDeleter
        self.apiURL = apiURL
        self.frontendURL = frontendURL
        self.environment = environment
        callback =
            environment == "production"
            ? "com.mtihani.desktop://auth/callback" : "com.mtihani.desktop.dev://auth/callback"
        keychainService = "com.mtihani.desktop.\(environment).\(apiURL.absoluteString)"
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }

    func restore() async {
        guard state == .restoring else { return }
        let current = generation
        let currentAttempt = attempt
        do {
            guard let saved = try readCredential() else {
                state = .signedOut
                return
            }
            credential = saved
            _ = try await accessToken(forceRefresh: true)
            guard generation == current, attempt == currentAttempt else { return }
            account = credential?.user
            state = .signedIn
            didChangeAccount?()
        } catch APIError.unauthorized {
            guard generation == current, attempt == currentAttempt else { return }
            state = .reauthenticationRequired
            message = "Your sign-in has expired. Sign in again."
        } catch {
            guard generation == current, attempt == currentAttempt else { return }
            account = credential?.user
            state = account == nil ? .signedOut : .signedIn
            message =
                "Could not restore sign-in. Check your connection and retry. Your saved credentials are retained."
            didChangeAccount?()
        }
    }

    func retryRestore() {
        state = .restoring
        Task { await restore() }
    }

    func signIn() {
        cancelSignIn()
        let current = UUID()
        attempt = current
        state = .signingIn
        message = nil
        Task { [self] in
            do {
                let verifier = try Self.randomSecret()
                let stateValue = try Self.randomSecret()
                let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
                let result: StartResponse = try await post(
                    "attempts",
                    [
                        "challenge": challenge, "state": stateValue, "clientId": "mtihani-macos",
                        "callback": callback, "environment": environment,
                    ])
                guard attempt == current else { return }
                guard let url = URL(string: result.authorizationUrl),
                    url.scheme == frontendURL.scheme,
                    url.host == frontendURL.host, url.port == frontendURL.port,
                    url.path == "/desktop-login"
                else { throw APIError.invalidResponse }
                var browserURL = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                if account != nil {
                    browserURL.queryItems =
                        (browserURL.queryItems ?? []) + [
                            URLQueryItem(name: "select_account", value: "1")
                        ]
                }
                let session = ASWebAuthenticationSession(
                    url: browserURL.url!, callbackURLScheme: URL(string: callback)!.scheme
                ) { [weak self] url, error in
                    Task { @MainActor in
                        await self?.complete(
                            url: url, error: error, verifier: verifier, expectedState: stateValue,
                            attempt: current)
                    }
                }
                session.presentationContextProvider = self
                webSession = session
                guard session.start() else { throw APIError.transport }
            } catch {
                guard attempt == current else { return }
                state = account == nil ? .signedOut : .signedIn
                message = "Unable to start sign-in. Check your connection and try again."
            }
        }
    }

    func cancelSignIn() {
        attempt = UUID()
        webSession?.cancel()
        webSession = nil
        if state == .signingIn { state = account == nil ? .signedOut : .signedIn }
    }

    nonisolated static func validateCallback(_ url: URL, callback: String, state: String) throws
        -> String
    {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let expected = URLComponents(string: callback), parts.scheme == expected.scheme,
            parts.host == expected.host, parts.path == expected.path, parts.port == nil,
            parts.user == nil, parts.password == nil, parts.fragment == nil
        else { throw APIError.invalidResponse }
        let items = parts.queryItems ?? []
        guard items.count == 2, items.filter({ $0.name == "state" }).count == 1,
            items.first(where: { $0.name == "state" })?.value == state,
            let code = items.first(where: { $0.name == "code" })?.value,
            code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
        else { throw APIError.invalidResponse }
        return code
    }

    private func complete(
        url: URL?, error: Error?, verifier: String, expectedState: String, attempt current: UUID
    ) async {
        guard attempt == current else { return }
        webSession = nil
        guard error == nil, let url else {
            state = account == nil ? .signedOut : .signedIn
            return
        }
        do {
            let code = try Self.validateCallback(url, callback: callback, state: expectedState)
            let next: DeviceCredential = try await post(
                "exchange",
                [
                    "code": code, "verifier": verifier, "clientId": "mtihani-macos",
                    "callback": callback, "environment": environment,
                ])
            guard attempt == current else {
                _ = await revoke(next)
                return
            }
            let old = credential
            try saveCredential(next)
            generation = UUID()
            refreshTask?.cancel()
            refreshTask = nil
            credential = next
            account = next.user
            state = .signedIn
            message = nil
            didChangeAccount?()
            if let old, !(await revoke(old)) {
                message =
                    "Signed in. Revocation of the previous device session could not be confirmed."
            }
        } catch {
            guard attempt == current else { return }
            state = account == nil ? .signedOut : .signedIn
            message = "Sign-in could not be completed. Please try again."
        }
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let saved = credential else { throw APIError.unauthorized }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expiry =
            formatter.date(from: saved.expiresAt)
            ?? ISO8601DateFormatter().date(from: saved.expiresAt)
        if !forceRefresh, let expiry, expiry > Date().addingTimeInterval(30) {
            return saved.accessToken
        }
        if let refreshTask {
            let current = generation
            let next = try await refreshTask.value
            guard generation == current else { throw CancellationError() }
            return next.accessToken
        }
        let current = generation
        let task = Task<DeviceCredential, Error> {
            try await self.post("refresh", ["refreshToken": saved.refreshToken])
        }
        refreshTask = task
        defer { if generation == current { refreshTask = nil } }
        do {
            let next = try await task.value
            guard generation == current else { throw CancellationError() }
            try saveCredential(next)
            credential = next
            return next.accessToken
        } catch APIError.unauthorized {
            if generation == current {
                state = .reauthenticationRequired
                message = "Sign in again to continue capturing."
                account = nil
                didChangeAccount?()
            }
            throw APIError.unauthorized
        }
    }

    func signOut() async {
        cancelSignIn()
        let old = credential
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        credential = nil
        account = nil
        state = .signedOut
        let result = credentialDeleter?() ?? SecItemDelete(keychainQuery() as CFDictionary)
        message =
            result == errSecSuccess || result == errSecItemNotFound
            ? nil : "Unable to remove the saved sign-in from Keychain. Try signing out again."
        didChangeAccount?()
        let current = generation
        if let old, !(await revoke(old)), generation == current {
            message =
                (message.map { $0 + " " } ?? "Local sign-out completed. ")
                + "Server revocation could not be confirmed; the device credential expires automatically."
        }
    }

    private func revoke(_ saved: DeviceCredential) async -> Bool {
        do {
            let _: EmptyResponse = try await post("revoke", ["refreshToken": saved.refreshToken])
            return true
        } catch { return false }
    }
    func manageAccount() { NSWorkspace.shared.open(frontendURL.appendingPathComponent("settings")) }

    private func post<T: Decodable>(_ path: String, _ body: [String: String]) async throws -> T {
        _ = try AppConfiguration(
            apiBaseURL: apiURL.absoluteString, accessToken: "configuration-check")
        _ = try AppConfiguration(
            apiBaseURL: frontendURL.absoluteString, accessToken: "configuration-check")
        guard
            environment != "production"
                || (apiURL.scheme == "https" && frontendURL.scheme == "https"
                    && apiURL.host != "localhost" && frontendURL.host != "localhost")
        else { throw APIError.invalidURL }
        var request = URLRequest(url: apiURL.appendingPathComponent("auth/desktop/\(path)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.fromHTTPStatus(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
    }
    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService, kSecAttrAccount as String: "active-device",
        ]
    }
    private func readCredential() throws -> DeviceCredential? {
        if let credentialReader { return try credentialReader() }
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw APIError.unauthorized
        }
        return try JSONDecoder().decode(DeviceCredential.self, from: data)
    }
    private func saveCredential(_ value: DeviceCredential) throws {
        if let credentialWriter {
            try credentialWriter(value)
            return
        }
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(
            keychainQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw APIError.invalidResponse }
        var query = keychainQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw APIError.invalidResponse
        }
    }
    nonisolated private static func randomSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw APIError.invalidResponse
        }
        return Data(bytes).base64URL
    }
    private struct StartResponse: Decodable { let authorizationUrl: String }
    private struct EmptyResponse: Decodable {}
}

nonisolated extension Data {
    fileprivate var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
            of: "/", with: "_"
        ).replacingOccurrences(of: "=", with: "")
    }
}
