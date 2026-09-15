import CoreGraphics
import Foundation

struct DiffStats: Sendable {
    var changedPixels: Int
    var totalPixels: Int
    var changedPercent: Double
    var boundingBox: CGRect?
}

enum ImageDiff {
    /// Render a CGImage into RGBA8 pixels at the given size (scaling as needed).
    static func rgba8(_ image: CGImage, width: Int, height: Int) -> Data? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.data.map { Data(bytes: $0, count: width * height * 4) }
    }

    /// Compare `old` (scaled to `new`'s size) against `new`, per pixel, any
    /// channel diff > tolerance counts as changed. Returns stats plus the
    /// diff-image pixels (gray 30% base, changed pixels solid red).
    static func compare(
        old: CGImage, new: CGImage, tolerance: Int = 16
    ) -> (stats: DiffStats, diffPixels: Data)? {
        let w = new.width, h = new.height
        guard let newPx = rgba8(new, width: w, height: h),
              let oldPx = rgba8(old, width: w, height: h)
        else { return nil }

        var stats = DiffStats(
            changedPixels: 0, totalPixels: w * h, changedPercent: 0,
            boundingBox: nil)
        var minX = w, minY = h, maxX = -1, maxY = -1
        var diff = Data(count: w * h * 4)

        newPx.withUnsafeBytes { n in
            oldPx.withUnsafeBytes { o in
                diff.withUnsafeMutableBytes { d in
                    let np = n.bindMemory(to: UInt8.self)
                    let op = o.bindMemory(to: UInt8.self)
                    let dp = d.bindMemory(to: UInt8.self)
                    for i in 0..<(w * h) {
                        let b = i * 4
                        let dr = abs(Int(np[b]) - Int(op[b]))
                        let dg = abs(Int(np[b + 1]) - Int(op[b + 1]))
                        let db = abs(Int(np[b + 2]) - Int(op[b + 2]))
                        let changed = dr > tolerance || dg > tolerance || db > tolerance
                        if changed {
                            stats.changedPixels += 1
                            let x = i % w, y = i / w
                            if x < minX { minX = x }
                            if y < minY { minY = y }
                            if x > maxX { maxX = x }
                            if y > maxY { maxY = y }
                            dp[b] = 255; dp[b + 1] = 0; dp[b + 2] = 0; dp[b + 3] = 255
                        } else {
                            let lum = Double(np[b]) * 0.299
                                + Double(np[b + 1]) * 0.587
                                + Double(np[b + 2]) * 0.114
                            let g = UInt8(lum * 0.3)
                            dp[b] = g; dp[b + 1] = g; dp[b + 2] = g; dp[b + 3] = 255
                        }
                    }
                }
            }
        }

        stats.changedPercent =
            stats.totalPixels == 0
            ? 0 : Double(stats.changedPixels) / Double(stats.totalPixels) * 100
        if maxX >= 0 {
            stats.boundingBox = CGRect(
                x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        return (stats, diff)
    }

    /// Build a CGImage from raw RGBA8 pixels.
    static func image(fromRGBA8 data: Data, width: Int, height: Int) -> CGImage? {
        var data = data
        return data.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(
                data: ptr.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }
}
