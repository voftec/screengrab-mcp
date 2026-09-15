import CoreGraphics
import Foundation
import ImageIO
import MCP

/// Files under ~/Pictures/mcp-captures/ exposed as MCP resources.
enum CaptureStore {
    static let directory =
        ("~/Pictures/mcp-captures" as NSString).expandingTildeInPath

    /// Captures (png/jpg), newest first, capped at 200.
    static func list() -> [Resource] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            atPath: directory) else { return [] }
        var items: [(String, Date)] = []
        for f in files {
            let ext = (f as NSString).pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            let path = "\(directory)/\(f)"
            let date =
                (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate]
                as? Date ?? .distantPast
            items.append((f, date))
        }
        return items
            .sorted { $0.1 > $1.1 }
            .prefix(200)
            .map { name, date in
                let path = "\(directory)/\(name)"
                let ext = (name as NSString).pathExtension.lowercased()
                let mime = ext == "png" ? "image/png" : "image/jpeg"
                var desc = ISO8601DateFormatter().string(from: date)
                if let dims = dimensions(path: path) {
                    desc = "\(dims.0)x\(dims.1), \(desc)"
                }
                return Resource(
                    name: name,
                    uri: "file://\(path)",
                    description: desc,
                    mimeType: mime)
            }
    }

    /// Read a file:// URI, restricted to the captures directory.
    static func read(uri: String) throws -> Resource.Content {
        guard uri.hasPrefix("file://") else {
            throw CaptureError.encodeFailed("unsupported URI scheme")
        }
        let rawPath = String(uri.dropFirst("file://".count))
        let resolved = (rawPath as NSString).resolvingSymlinksInPath
        let base = (directory as NSString).resolvingSymlinksInPath
        guard resolved.hasPrefix(base + "/") || resolved == base else {
            throw CaptureError.encodeFailed("URI outside captures directory")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: resolved))
        let ext = (resolved as NSString).pathExtension.lowercased()
        let mime = ext == "png" ? "image/png" : "image/jpeg"
        return .binary(data, uri: uri, mimeType: mime)
    }

    private static func dimensions(path: String) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
            let w = props[kCGImagePropertyPixelWidth as String] as? Int,
            let h = props[kCGImagePropertyPixelHeight as String] as? Int
        else { return nil }
        return (w, h)
    }
}
