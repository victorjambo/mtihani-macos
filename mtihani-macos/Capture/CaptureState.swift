import Foundation

enum CaptureState: Equatable, Sendable {
    case idle
    case capturing
    /// One or more screenshots captured for a long question; still open to
    /// more shots until the coalescing window elapses.
    case buffering(count: Int)
    case uploading
    case success(captureID: String)
    case failed(message: String)

    /// Only blocks a *new* trigger while a screenshot grab or upload is
    /// actively in flight. Buffering deliberately stays outside this so a
    /// repeat trigger can add another shot to the same capture.
    var isProcessing: Bool {
        switch self {
        case .capturing, .uploading:
            true
        case .idle, .buffering, .success, .failed:
            false
        }
    }

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .capturing:
            "Capturing…"
        case let .buffering(count):
            count == 1 ? "1 screenshot buffered" : "\(count) screenshots buffered"
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
        case .buffering:
            "Trigger again to add another screenshot, or wait to send."
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
