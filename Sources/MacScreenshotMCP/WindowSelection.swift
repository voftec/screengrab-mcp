import CoreGraphics
import Foundation

enum WindowSelection {
    /// Pick the "main" window for an app's capture:
    /// only layer-0, non-empty windows; prefer on-screen; if `titleContains`
    /// is given and matches, those candidates win; then largest area.
    static func pickMainWindow(
        from windows: [WindowInfo],
        titleContains: String? = nil
    ) -> WindowInfo? {
        var candidates = windows.filter {
            $0.layer == 0 && $0.frame.width > 0 && $0.frame.height > 0
        }

        if let query = titleContains, !query.isEmpty {
            let matching = candidates.filter {
                $0.title.range(of: query, options: .caseInsensitive) != nil
            }
            if !matching.isEmpty { candidates = matching }
        }

        let onScreen = candidates.filter(\.isOnScreen)
        if !onScreen.isEmpty { candidates = onScreen }

        return candidates.max(by: { $0.area < $1.area })
    }

    /// Match an app by pid (numeric query), exact bundleId (case-insensitive),
    /// exact name (case-insensitive), then name substring (case-insensitive).
    static func matchApp(query: String, apps: [AppInfo]) -> AppInfo? {
        if let pid = Int(query), let app = apps.first(where: { $0.pid == pid }) {
            return app
        }
        if let app = apps.first(where: {
            $0.bundleId?.caseInsensitiveCompare(query) == .orderedSame
        }) {
            return app
        }
        if let app = apps.first(where: {
            $0.name.caseInsensitiveCompare(query) == .orderedSame
        }) {
            return app
        }
        return apps.first {
            $0.name.range(of: query, options: .caseInsensitive) != nil
        }
    }
}
