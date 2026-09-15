import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageFormat: String {
    case png
    case jpeg

    var utType: CFString {
        (self == .png ? UTType.png.identifier : UTType.jpeg.identifier) as CFString
    }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var mimeType: String { self == .png ? "image/png" : "image/jpeg" }
}

enum ImageEncoder {
    /// Downscale so width <= maxWidth (aspect preserved). Returns input if
    /// maxWidth is nil or the image already fits.
    static func resized(_ image: CGImage, maxWidth: Int?) -> CGImage {
        guard let maxWidth, maxWidth > 0, image.width > maxWidth else { return image }
        let ratio = CGFloat(maxWidth) / CGFloat(image.width)
        let w = maxWidth
        let h = max(1, Int((CGFloat(image.height) * ratio).rounded()))
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Encode a CGImage to PNG or JPEG (quality 0...1 for JPEG).
    static func encode(
        _ image: CGImage, format: ImageFormat, jpegQuality: Double = 0.85
    ) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType, 1, nil)
        else { throw CaptureError.encodeFailed("create destination") }
        var props: [CFString: Any] = [:]
        if format == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw CaptureError.encodeFailed("finalize")
        }
        return data as Data
    }
}
