import Foundation

nonisolated enum SessionStatus: String, Decodable, Sendable {
    case active
    case closed
}

nonisolated struct Session: Decodable, Equatable, Sendable {
    let id: String
    let status: SessionStatus
}

nonisolated enum CaptureAcceptanceStatus: String, Decodable, Sendable {
    case received
}

nonisolated struct AcceptedCapture: Decodable, Equatable, Sendable {
    let captureId: String
    let sessionId: String
    let status: CaptureAcceptanceStatus
}

nonisolated enum APIError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case badRequest
    case invalidSession
    case sessionClosed
    case captureTooLarge
    case serverError
    case transport
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The backend URL is invalid."
        case .badRequest:
            "The backend rejected the request."
        case .invalidSession:
            "The session does not exist."
        case .sessionClosed:
            "The session is closed."
        case .captureTooLarge:
            "The screenshot exceeds the backend's configured upload limit."
        case .serverError:
            "The backend encountered an error. Please try again."
        case .transport:
            "The backend could not be reached."
        case .invalidResponse:
            "The backend returned an invalid response."
        }
    }

    static func fromHTTPStatus(_ statusCode: Int) -> APIError {
        switch statusCode {
        case 400:
            .badRequest
        case 404:
            .invalidSession
        case 409:
            .sessionClosed
        case 413:
            .captureTooLarge
        case 500 ... 599:
            .serverError
        default:
            .invalidResponse
        }
    }
}
