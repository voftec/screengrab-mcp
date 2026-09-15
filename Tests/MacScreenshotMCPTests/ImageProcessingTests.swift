import CoreGraphics
import XCTest
@testable import MacScreenshotMCP

private func solidImage(
    w: Int, h: Int, r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0
) -> CGImage {
    var px = Data(count: w * h * 4)
    for i in 0..<(w * h) {
        px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 255
    }
    return ImageDiff.image(fromRGBA8: px, width: w, height: h)!
}

final class ImageEncoderTests: XCTestCase {
    func testResizeToMaxWidth() {
        let img = solidImage(w: 400, h: 200, r: 128)
        let out = ImageEncoder.resized(img, maxWidth: 100)
        XCTAssertEqual(out.width, 100)
        XCTAssertEqual(out.height, 50)
    }

    func testNoResizeWhenFits() {
        let img = solidImage(w: 50, h: 50)
        let out = ImageEncoder.resized(img, maxWidth: 100)
        XCTAssertEqual(out.width, 50)
    }

    func testEncodePngAndJpeg() throws {
        let img = solidImage(w: 20, h: 20, r: 255)
        let png = try ImageEncoder.encode(img, format: .png)
        XCTAssertGreaterThan(png.count, 0)
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))  // PNG magic
        let jpg = try ImageEncoder.encode(img, format: .jpeg, jpegQuality: 0.6)
        XCTAssertEqual(jpg.prefix(2), Data([0xFF, 0xD8]))  // JPEG SOI
    }
}

final class ImageDiffTests: XCTestCase {
    func testIdenticalImagesZeroChange() {
        let a = solidImage(w: 10, h: 10, r: 100, g: 100, b: 100)
        let b = solidImage(w: 10, h: 10, r: 100, g: 100, b: 100)
        let result = ImageDiff.compare(old: a, new: b)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.stats.changedPixels, 0)
        XCTAssertEqual(result?.stats.changedPercent, 0)
        XCTAssertNil(result?.stats.boundingBox)
    }

    func testOnePixelChange() {
        var px = Data(count: 10 * 10 * 4)
        for i in 0..<100 {
            px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; px[i * 4 + 3] = 255
        }
        // Change pixel at (4, 3) to pure white.
        let idx = (3 * 10 + 4) * 4
        px[idx] = 255; px[idx + 1] = 255; px[idx + 2] = 255
        let new = ImageDiff.image(fromRGBA8: px, width: 10, height: 10)!
        let old = solidImage(w: 10, h: 10)
        let result = ImageDiff.compare(old: old, new: new)
        XCTAssertEqual(result?.stats.changedPixels, 1)
        XCTAssertEqual(result?.stats.totalPixels, 100)
        XCTAssertEqual(result?.stats.changedPercent ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(result?.stats.boundingBox, CGRect(x: 4, y: 3, width: 1, height: 1))
    }

    func testDiffWithinToleranceNotCounted() {
        let a = solidImage(w: 4, h: 4, r: 100, g: 100, b: 100)
        // 110 vs 100 → diff 10, within tolerance 16.
        let b = solidImage(w: 4, h: 4, r: 110, g: 100, b: 100)
        let result = ImageDiff.compare(old: a, new: b, tolerance: 16)
        XCTAssertEqual(result?.stats.changedPixels, 0)
    }
}
