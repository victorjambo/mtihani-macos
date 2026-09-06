import CoreGraphics
import Foundation
import ImageIO
import OSLog
import ScreenCaptureKit
import UniformTypeIdentifiers

struct CapturedImage: Equatable, Sendable {
    static let pngMimeType = "image/png"

    let data: Data
    let width: Int
    let height: Int
    let mimeType: String

    init(
        data: Data,
        width: Int,
        height: Int,
        mimeType: String = Self.pngMimeType
    ) {
        self.data = data
        self.width = width
        self.height = height
        self.mimeType = mimeType
    }
}

@MainActor
protocol ScreenCapturing: AnyObject {
    func capture() async throws -> CapturedImage
}

enum ScreenCaptureError: LocalizedError, Equatable {
    case permissionDenied
    case mainDisplayUnavailable
    case imageUnavailable
    case pngEncodingFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission is required to capture the screen."
        case .mainDisplayUnavailable:
            "The main display is not currently available for capture."
        case .imageUnavailable:
            "macOS did not return a screenshot image."
        case .pngEncodingFailed:
            "The screenshot could not be converted to PNG."
        case .captureFailed:
            "The screen could not be captured. Please try again."
        }
    }
}

@MainActor
final class ScreenCaptureService: ScreenCapturing {
    private let permissionService: any PermissionsServicing
    private let logger: Logger

    init(
        permissionService: any PermissionsServicing,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.victorjambo.mtihani-macos",
            category: "capture"
        )
    ) {
        self.permissionService = permissionService
        self.logger = logger
    }

    func capture() async throws -> CapturedImage {
        guard permissionService.refreshScreenRecordingPermission() == .granted else {
            logger.notice("Screen capture skipped because Screen Recording permission is unavailable")
            throw ScreenCaptureError.permissionDenied
        }

        logger.debug("Starting main-display screenshot capture")

        do {
            let shareableContent = try await SCShareableContent.current
            let mainDisplayID = CGMainDisplayID()

            guard let display = shareableContent.displays.first(where: { $0.displayID == mainDisplayID }) else {
                logger.error("The main display was absent from ScreenCaptureKit shareable content")
                throw ScreenCaptureError.mainDisplayUnavailable
            }

            let ownBundleIdentifier = Bundle.main.bundleIdentifier
            let excludedApplications = shareableContent.applications.filter {
                $0.bundleIdentifier == ownBundleIdentifier
            }
            let contentFilter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            let pixelScale = max(CGFloat(contentFilter.pointPixelScale), 1)

            configuration.width = Int(contentFilter.contentRect.width * pixelScale)
            configuration.height = Int(contentFilter.contentRect.height * pixelScale)
            configuration.captureResolution = .best
            configuration.capturesAudio = false
            configuration.showsCursor = true

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: configuration
            )
            let pngData = try await Task.detached(priority: .userInitiated) {
                try Self.encodePNG(image)
            }.value
            let capturedImage = CapturedImage(
                data: pngData,
                width: image.width,
                height: image.height
            )

            logger.info(
                "Captured main display as PNG: width=\(capturedImage.width), height=\(capturedImage.height), bytes=\(capturedImage.data.count)"
            )
            return capturedImage
        } catch let error as ScreenCaptureError {
            throw error
        } catch {
            let nsError = error as NSError
            logger.error(
                "ScreenCaptureKit failed: domain=\(nsError.domain, privacy: .public), code=\(nsError.code)"
            )

            if permissionService.refreshScreenRecordingPermission() != .granted {
                throw ScreenCaptureError.permissionDenied
            }
            throw ScreenCaptureError.captureFailed
        }
    }

    nonisolated private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureError.pngEncodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureError.pngEncodingFailed
        }

        guard data.length > 0 else {
            throw ScreenCaptureError.imageUnavailable
        }
        return data as Data
    }
}
