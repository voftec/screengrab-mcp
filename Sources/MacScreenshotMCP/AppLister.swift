import AppKit
import CoreGraphics

struct AppInfo: Sendable {
    let pid: Int
    let name: String
    let bundleId: String?
    let isActive: Bool
    let isHidden: Bool
    let windowCount: Int
}

enum AppLister {
    /// Apps with UI (activationPolicy == .regular). Instant: only NSWorkspace + CGWindowListCopyWindowInfo.
    static func listApps() -> [AppInfo] {
        var windowCounts: [Int: Int] = [:]
        if let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] {
            for entry in list {
                guard let pid = entry[kCGWindowOwnerPID as String] as? Int,
                      let layer = entry[kCGWindowLayer as String] as? Int,
                      layer == 0 else { continue }
                windowCounts[pid, default: 0] += 1
            }
        }

        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { app in
                let pid = Int(app.processIdentifier)
                return AppInfo(
                    pid: pid,
                    name: app.localizedName ?? "",
                    bundleId: app.bundleIdentifier,
                    isActive: app.isActive,
                    isHidden: app.isHidden,
                    windowCount: windowCounts[pid] ?? 0
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func activate(pid: Int) {
        NSRunningApplication(processIdentifier: pid_t(pid))?.activate()
    }
}
