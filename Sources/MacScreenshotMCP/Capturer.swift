import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum CaptureError: Error, LocalizedError {
    case windowNotFound(String)
    case appNotFound(String)
    case noPermission

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let m): return m
        case .appNotFound(let m): return m
        case .noPermission:
            return "No Screen Recording permission. System Settings > Privacy & Security > Screen Recording — enable for the host app (Cursor/Claude/Terminal), then retry."
        }
    }
}

struct CaptureResult: Sendable {
    let pngData: Data
    let path: String?
    let width: Int
    let height: Int
    let app: String?
    let windowId: Int?
    let title: String?
}

enum Capturer {
    /// Capture a single window (even if occluded). Scale 1 or 2 (default 2 = Retina).
    static func captureWindow(_ window: SCWindow, scale: Int = 2) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * scale
        config.height = Int(window.frame.height) * scale
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
    }

    /// Capture a full display or a region of it (points, display coordinates).
    static func captureScreen(
        display: SCDisplay, region: CGRect?, scale: Int = 2
    ) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let rect = region ?? display.frame
        config.sourceRect = rect
        config.width = Int(rect.width) * scale
        config.height = Int(rect.height) * scale
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
    }

    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)
        else { throw CaptureError.windowNotFound("Failed to create PNG destination") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw CaptureError.windowNotFound("Failed to encode PNG")
        }
        return data as Data
    }

    /// Save PNG to savePath if given, else ~/Pictures/mcp-captures/<app>-<timestamp>.png.
    @discardableResult
    static func save(png: Data, savePath: String?, appName: String?) throws -> String {
        let path: String
        if let savePath {
            path = (savePath as NSString).expandingTildeInPath
        } else {
            let dir = ("~/Pictures/mcp-captures" as NSString).expandingTildeInPath
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter.fileStamp.string(from: Date())
            let app = (appName ?? "screen")
                .replacingOccurrences(of: " ", with: "-")
            path = "\(dir)/\(app)-\(stamp).png"
        }
        try png.write(to: URL(fileURLWithPath: path))
        return path
    }
}

extension ISO8601DateFormatter {
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
