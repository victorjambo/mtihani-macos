import Foundation

enum CaptureState: Equatable, Sendable {
    case idle
    case capturing
    case uploading
    case success(captureID: String)
    case failed(message: String)

    var isProcessing: Bool {
        switch self {
        case .capturing, .uploading:
            true
        case .idle, .success, .failed:
            false
        }
    }

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .capturing:
            "Capturing…"
        case .uploading:
            "Uploading…"
        case .success:
            "Capture sent"
        case .failed:
            "Capture failed"
        }
    }

    var detail: String? {
        switch self {
        case let .success(captureID):
            "Capture \(captureID) was accepted."
        case let .failed(message):
            message
        case .idle, .capturing, .uploading:
            nil
        }
    }
}

enum SessionConnectionState: Equatable, Sendable {
    case notConfigured
    case disconnected
    case connecting
    case connected
    case invalidSession
    case sessionClosed
    case serverUnavailable
    case invalidConfiguration

    var title: String {
        switch self {
        case .notConfigured:
            "Not configured"
        case .disconnected:
            "Not tested"
        case .connecting:
            "Connecting…"
        case .connected:
            "Connected"
        case .invalidSession:
            "Invalid session"
        case .sessionClosed:
            "Session closed"
        case .serverUnavailable:
            "Server unavailable"
        case .invalidConfiguration:
            "Invalid backend URL"
        }
    }
}
