import CoreGraphics
import Foundation
import ScreenCaptureKit

struct WindowInfo: Sendable {
    let windowId: Int
    let title: String
    let appName: String
    let bundleId: String?
    let pid: Int
    let frame: CGRect
    let isOnScreen: Bool
    let layer: Int

    var area: Double { Double(frame.width * frame.height) }
}

enum WindowLister {
    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
    }

    static func windows(from content: SCShareableContent) -> [WindowInfo] {
        content.windows.map { w in
            WindowInfo(
                windowId: Int(w.windowID),
                title: w.title ?? "",
                appName: w.owningApplication?.applicationName ?? "",
                bundleId: w.owningApplication?.bundleIdentifier,
                pid: Int(w.owningApplication?.processID ?? 0),
                frame: w.frame,
                isOnScreen: w.isOnScreen,
                layer: Int(w.windowLayer)
            )
        }
    }

    /// Visible, capturable windows: layer 0 and non-zero frame by default.
    /// Optional filters: pid, or case-insensitive app name substring.
    static func list(
        pid: Int? = nil,
        appName: String? = nil
    ) async throws -> [WindowInfo] {
        let content = try await shareableContent()
        return windows(from: content)
            .filter { $0.layer == 0 && $0.frame.width > 0 && $0.frame.height > 0 }
            .filter { pid == nil || $0.pid == pid }
            .filter {
                guard let appName, !appName.isEmpty else { return true }
                return $0.appName.range(of: appName, options: .caseInsensitive) != nil
            }
    }
}
