import Foundation

@MainActor
protocol MtihaniAPIClient {
    func listSessions() async throws -> [Session]
    func createSession() async throws -> Session
    func getSession(id: String) async throws -> Session

    func uploadCapture(
        sessionId: String,
        screenshot: Data,
        language: String?
    ) async throws -> AcceptedCapture
}

@MainActor
protocol HTTPTransport: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

@MainActor
final class URLSessionHTTPTransport: HTTPTransport {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await urlSession.data(for: request)
    }
}

nonisolated struct APIRequestBuilder: Sendable {
    private static let pathComponentAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    let baseURL: URL
    let apiKey: String

    func listSessionsRequest() throws -> URLRequest {
        var request = URLRequest(url: try endpointURL(pathComponents: ["sessions"]))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        return request
    }

    func createSessionRequest() throws -> URLRequest {
        var request = URLRequest(url: try endpointURL(pathComponents: ["sessions"]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        return request
    }

    func getSessionRequest(id: String) throws -> URLRequest {
        var request = URLRequest(url: try endpointURL(pathComponents: ["sessions", id]))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        return request
    }

    func uploadCaptureRequest(
        sessionId: String,
        screenshot: Data,
        language: String?,
        boundary: String = "Mtihani-\(UUID().uuidString)"
    ) throws -> URLRequest {
        var form = MultipartFormData(boundary: boundary)
        form.appendPNG(screenshot)

        if let language {
            form.appendLanguage(language)
        }

        var request = URLRequest(
            url: try endpointURL(pathComponents: ["sessions", sessionId, "captures"])
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        authorize(&request)
        request.httpBody = form.finalize()
        return request
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    }

    private func endpointURL(pathComponents: [String]) throws -> URL {
        guard
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false,
            components.query == nil,
            components.fragment == nil
        else {
            throw APIError.invalidURL
        }

        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        if path == "/" {
            path = ""
        }

        for component in pathComponents {
            guard
                !component.isEmpty,
                let encodedComponent = component.addingPercentEncoding(
                    withAllowedCharacters: Self.pathComponentAllowedCharacters
                )
            else {
                throw APIError.invalidURL
            }

            path += "/\(encodedComponent)"
        }

        components.percentEncodedPath = path

        guard let endpointURL = components.url else {
            throw APIError.invalidURL
        }

        return endpointURL
    }
}

@MainActor
final class URLSessionMtihaniAPIClient: MtihaniAPIClient {
    private let requestBuilder: APIRequestBuilder
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        apiKey: String,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        requestBuilder = APIRequestBuilder(baseURL: baseURL, apiKey: apiKey)
        transport = URLSessionHTTPTransport(urlSession: urlSession)
        self.decoder = decoder
    }

    init(
        baseURL: URL,
        apiKey: String,
        transport: any HTTPTransport,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        requestBuilder = APIRequestBuilder(baseURL: baseURL, apiKey: apiKey)
        self.transport = transport
        self.decoder = decoder
    }

    func listSessions() async throws -> [Session] {
        try await send(requestBuilder.listSessionsRequest(), expectedStatusCode: 200)
    }

    func createSession() async throws -> Session {
        try await send(requestBuilder.createSessionRequest(), expectedStatusCode: 201)
    }

    func getSession(id: String) async throws -> Session {
        let request = try requestBuilder.getSessionRequest(id: id)
        let session: Session = try await send(request, expectedStatusCode: 200)

        guard session.id == id else {
            throw APIError.invalidResponse
        }

        return session
    }

    func uploadCapture(
        sessionId: String,
        screenshot: Data,
        language: String?
    ) async throws -> AcceptedCapture {
        let requestBuilder = requestBuilder
        let request = try await Task.detached(priority: .userInitiated) {
            try requestBuilder.uploadCaptureRequest(
                sessionId: sessionId,
                screenshot: screenshot,
                language: language
            )
        }.value
        let capture: AcceptedCapture = try await send(request, expectedStatusCode: 202)

        guard capture.sessionId == sessionId, capture.status == .received else {
            throw APIError.invalidResponse
        }

        return capture
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        expectedStatusCode: Int
    ) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.transport
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == expectedStatusCode else {
            throw APIError.fromHTTPStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

}
