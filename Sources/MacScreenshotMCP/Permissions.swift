@preconcurrency import ApplicationServices
import CoreGraphics

enum Permissions {
    static let screenRecordingHint =
        "System Settings > Privacy & Security > Screen Recording — enable for the host app (Cursor/Claude/Terminal)"
    static let accessibilityHint =
        "System Settings > Privacy & Security > Accessibility — enable for the host app (Cursor/Claude/Terminal)"

    static func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }
}
