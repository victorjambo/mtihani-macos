import XCTest

@testable import mtihani_macos

@MainActor
final class DesktopAuthenticationTests: XCTestCase {
    private let callback = "com.mtihani.desktop.dev://auth/callback"
    func testCallbackRequiresExactRouteStateAndSingleCode() throws {
        let code = String(repeating: "c", count: 43)
        let good = URL(string: "\(callback)?code=\(code)&state=expected")!
        XCTAssertEqual(
            try DesktopAuthentication.validateCallback(good, callback: callback, state: "expected"),
            code)
        for raw in [
            "com.mtihani.desktop.dev://other/callback?code=\(code)&state=expected",
            "com.mtihani.desktop.dev://auth/other?code=\(code)&state=expected",
            "\(callback)?code=\(code)&state=wrong",
            "\(callback)?code=\(code)&state=expected&code=\(code)",
            "\(callback)?code=\(code)&state=expected#fragment",
        ] {
            XCTAssertThrowsError(
                try DesktopAuthentication.validateCallback(
                    URL(string: raw)!, callback: callback, state: "expected"))
        }
    }
    func testRestorationAndConcurrentRefreshAreCoalesced() async throws {
        let transport = AuthTransport()
        var saved = credential()
        let auth = makeAuth(transport, read: { saved }, write: { saved = $0 })
        await auth.restore()
        XCTAssertEqual(auth.state, .signedIn)
        XCTAssertEqual(auth.account?.id, "user-a")
        transport.requests = 0
        async let first = auth.accessToken(forceRefresh: true)
        async let second = auth.accessToken(forceRefresh: true)
        let values = try await [first, second]
        XCTAssertEqual(values, ["new-access", "new-access"])
        XCTAssertEqual(transport.requests, 1)
        XCTAssertEqual(saved.refreshToken, "new-refresh")
        auth.cancelSignIn()
        XCTAssertEqual(auth.account?.id, "user-a")
    }
    func testOfflineRestorationRetainsCredentialAndDefinitiveRejectionRequiresSignIn() async {
        let transport = AuthTransport()
        transport.offline = true
        let saved = credential()
        var writes = 0
        let auth = makeAuth(transport, read: { saved }, write: { _ in writes += 1 })
        await auth.restore()
        XCTAssertEqual(auth.account?.id, "user-a")
        XCTAssertEqual(auth.state, .signedIn)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(auth.credential?.refreshToken, saved.refreshToken)
        transport.offline = false
        transport.status = 401
        do {
            _ = try await auth.accessToken(forceRefresh: true)
            XCTFail("Expected rejection")
        } catch {}
        XCTAssertEqual(auth.state, .reauthenticationRequired)
    }
    func testOfflineSignOutAlwaysDeletesLocalCredential() async {
        let transport = AuthTransport()
        var deleted = false
        let saved = credential()
        let auth = makeAuth(
            transport, read: { saved },
            delete: {
                deleted = true
                return 0
            })
        await auth.restore()
        transport.offline = true
        await auth.signOut()
        XCTAssertTrue(deleted)
        XCTAssertNil(auth.account)
        XCTAssertNil(auth.credential)
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertTrue(auth.message?.contains("could not be confirmed") == true)
    }
    private func credential() -> DeviceCredential {
        DeviceCredential(
            accessToken: "old", refreshToken: "old-refresh", expiresAt: "2000-01-01T00:00:00Z",
            user: DesktopAccount(id: "user-a", name: "A", email: "a@example.com", avatarUrl: nil))
    }
    private func makeAuth(
        _ transport: AuthTransport, read: @escaping () throws -> DeviceCredential?,
        write: @escaping (DeviceCredential) throws -> Void = { _ in },
        delete: @escaping () -> OSStatus = { 0 }
    ) -> DesktopAuthentication {
        DesktopAuthentication(
            apiURL: URL(string: "https://api.example.com/api")!,
            frontendURL: URL(string: "https://example.com")!,
            environment: "development", transport: transport, credentialReader: read,
            credentialWriter: write, credentialDeleter: delete)
    }
}

@MainActor
private final class AuthTransport: HTTPTransport {
    var requests = 0
    var status = 200
    var offline = false
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests += 1
        try await Task.sleep(for: .milliseconds(20))
        if offline { throw URLError(.notConnectedToInternet) }
        let data = Data(
            #"{"accessToken":"new-access","refreshToken":"new-refresh","expiresAt":"2099-01-01T00:00:00Z","user":{"id":"user-a","name":"A","email":"a@example.com","avatarUrl":null}}"#
                .utf8)
        return (
            data,
            HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}
