import CoreGraphics

enum Permissions {
    static let hint =
        "System Settings > Privacy & Security > Screen Recording — enable for the host app (Cursor/Claude/Terminal)"

    static func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
