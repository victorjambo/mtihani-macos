import XCTest
@testable import mtihani_macos

final class APIClientTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com/api/")!

    func testSessionRequestUsesExpectedMethodAndURL() throws {
        let request = try APIRequestBuilder(baseURL: baseURL)
            .getSessionRequest(id: "session/id")

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.example.com/api/sessions/session%2Fid"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            "application/json"
        )
    }

    func testListAndCreateSessionRequestsUseCollectionURL() throws {
        let builder = APIRequestBuilder(baseURL: baseURL)
        let listRequest = try builder.listSessionsRequest()
        let createRequest = try builder.createSessionRequest()

        XCTAssertEqual(listRequest.httpMethod, "GET")
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(
            listRequest.url?.absoluteString,
            "https://api.example.com/api/sessions"
        )
        XCTAssertEqual(createRequest.url, listRequest.url)
    }

    func testUploadRequestBuildsPNGMultipartBodyWithLanguage() throws {
        let request = try APIRequestBuilder(baseURL: baseURL)
            .uploadCaptureRequest(
                sessionId: "session-123",
                screenshot: Data("PNG-DATA".utf8),
                language: "typescript",
                boundary: "Boundary-123"
            )
        let body = try XCTUnwrap(request.httpBody)
        let bodyText = String(decoding: body, as: UTF8.self)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.example.com/api/sessions/session-123/captures"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=Boundary-123"
        )
        XCTAssertTrue(
            bodyText.contains(
                "name=\"screenshot\"; filename=\"capture.png\""
            )
        )
        XCTAssertTrue(bodyText.contains("Content-Type: image/png"))
        XCTAssertTrue(bodyText.contains("PNG-DATA"))
        XCTAssertTrue(bodyText.contains("name=\"language\""))
        XCTAssertTrue(bodyText.contains("typescript"))
        XCTAssertTrue(bodyText.hasSuffix("--Boundary-123--\r\n"))
    }

    func testUploadRequestOmitsAutomaticLanguageField() throws {
        let request = try APIRequestBuilder(baseURL: baseURL)
            .uploadCaptureRequest(
                sessionId: "session-123",
                screenshot: Data("PNG-DATA".utf8),
                language: nil,
                boundary: "Boundary-123"
            )
        let body = try XCTUnwrap(request.httpBody)
        let bodyText = String(decoding: body, as: UTF8.self)

        XCTAssertFalse(bodyText.contains("name=\"language\""))
    }

    func testHTTPStatusMapping() {
        XCTAssertEqual(APIError.fromHTTPStatus(400), .badRequest)
        XCTAssertEqual(APIError.fromHTTPStatus(404), .invalidSession)
        XCTAssertEqual(APIError.fromHTTPStatus(409), .sessionClosed)
        XCTAssertEqual(APIError.fromHTTPStatus(413), .captureTooLarge)
        XCTAssertEqual(APIError.fromHTTPStatus(500), .serverError)
        XCTAssertEqual(APIError.fromHTTPStatus(503), .serverError)
        XCTAssertEqual(APIError.fromHTTPStatus(418), .invalidResponse)
    }

    @MainActor
    func testClientDecodesSessionOnlyFromExact200Response() async throws {
        let transport = MockHTTPTransport()
        transport.statusCode = 200
        transport.responseData = Data(
            #"{"id":"session-123","status":"active"}"#.utf8
        )
        let client = URLSessionMtihaniAPIClient(
            baseURL: baseURL,
            transport: transport
        )

        let session = try await client.getSession(id: "session-123")

        XCTAssertEqual(session, Session(id: "session-123", status: .active))
        XCTAssertEqual(transport.lastRequest?.httpMethod, "GET")

        transport.statusCode = 202
        await assertAPIError(.invalidResponse) {
            try await client.getSession(id: "session-123")
        }
    }

    @MainActor
    func testClientListsAndCreatesSessions() async throws {
        let transport = MockHTTPTransport()
        let client = URLSessionMtihaniAPIClient(
            baseURL: baseURL,
            transport: transport
        )

        transport.statusCode = 200
        transport.responseData = Data(
            #"[{"id":"session-2","status":"closed"},{"id":"session-1","status":"active"}]"#.utf8
        )
        let sessions = try await client.listSessions()
        XCTAssertEqual(sessions.map(\.id), ["session-2", "session-1"])

        transport.statusCode = 201
        transport.responseData = Data(
            #"{"id":"session-3","status":"active"}"#.utf8
        )
        let created = try await client.createSession()
        XCTAssertEqual(created, Session(id: "session-3", status: .active))
    }

    @MainActor
    func testClientEnforcesSessionIdentity() async {
        let transport = MockHTTPTransport()
        transport.statusCode = 200
        transport.responseData = Data(
            #"{"id":"different-session","status":"active"}"#.utf8
        )
        let client = URLSessionMtihaniAPIClient(
            baseURL: baseURL,
            transport: transport
        )

        await assertAPIError(.invalidResponse) {
            try await client.getSession(id: "session-123")
        }
    }

    @MainActor
    func testClientDecodesAcceptedCaptureOnlyFromExact202Response() async throws {
        let transport = MockHTTPTransport()
        transport.statusCode = 202
        transport.responseData = Data(
            #"{"captureId":"capture-123","sessionId":"session-123","status":"received"}"#.utf8
        )
        let client = URLSessionMtihaniAPIClient(
            baseURL: baseURL,
            transport: transport
        )

        let capture = try await client.uploadCapture(
            sessionId: "session-123",
            screenshot: Data([0x89, 0x50, 0x4E, 0x47]),
            language: nil
        )

        XCTAssertEqual(capture.captureId, "capture-123")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")

        transport.statusCode = 200
        await assertAPIError(.invalidResponse) {
            try await client.uploadCapture(
                sessionId: "session-123",
                screenshot: Data([0x89, 0x50, 0x4E, 0x47]),
                language: nil
            )
        }
    }

    @MainActor
    func testClientMapsConflictAndTransportFailures() async {
        let transport = MockHTTPTransport()
        transport.statusCode = 409
        let client = URLSessionMtihaniAPIClient(
            baseURL: baseURL,
            transport: transport
        )

        await assertAPIError(.sessionClosed) {
            try await client.uploadCapture(
                sessionId: "session-123",
                screenshot: Data([0x89, 0x50, 0x4E, 0x47]),
                language: nil
            )
        }

        transport.error = URLError(.cannotConnectToHost)
        await assertAPIError(.transport) {
            try await client.getSession(id: "session-123")
        }
    }

    @MainActor
    private func assertAPIError<T>(
        _ expected: APIError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected APIError.\(expected)")
        } catch {
            XCTAssertEqual(error as? APIError, expected)
        }
    }
}

@MainActor
private final class MockHTTPTransport: HTTPTransport {
    var statusCode = 200
    var responseData = Data()
    var error: Error?
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (responseData, response)
    }
}
