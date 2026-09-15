import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import MCP
import ScreenCaptureKit

enum Tools {
    // Shared output parameters for all capture tools.
    private static var outputProps: [String: Value] {
        [
            "quality": .object([
                "type": "string",
                "description": "'high' = PNG at native resolution; 'low' = JPEG q0.6 downscaled to max_width",
                "enum": .array(["high", "low"]),
                "default": "high",
            ]),
            "format": .object([
                "type": "string",
                "description": "Explicit output format, overrides quality default",
                "enum": .array(["png", "jpeg"]),
            ]),
            "jpeg_quality": .object([
                "type": "number",
                "description": "JPEG quality 0-1 (default 0.6 for low, 0.85 for high+jpeg)",
            ]),
            "max_width": .object([
                "type": "integer",
                "description": "Downscale so width <= this (default 1024 when quality=low)",
            ]),
            "save_path": .object([
                "type": "string",
                "description": "Where to save the capture (default: ~/Pictures/mcp-captures/)",
            ]),
            "return_image": .object([
                "type": "boolean",
                "description": "Include base64 image content in the response",
                "default": true,
            ]),
            "compare_with": .object([
                "type": "string",
                "description": "Path to a previous PNG/JPEG to diff against; writes <path>-diff.png",
            ]),
            "return_diff_image": .object([
                "type": "boolean",
                "description": "Also inline the diff image (requires return_image)",
                "default": false,
            ]),
        ]
    }

    private static func schema(
        _ props: [String: Value], required: [String] = []
    ) -> Value {
        var merged = outputProps
        for (k, v) in props { merged[k] = v }
        var s: [String: Value] = [
            "type": "object",
            "properties": .object(merged),
        ]
        if !required.isEmpty {
            s["required"] = .array(required.map { .string($0) })
        }
        return .object(s)
    }

    private static func plainSchema(
        _ props: [String: Value], required: [String] = []
    ) -> Value {
        var s: [String: Value] = [
            "type": "object",
            "properties": .object(props),
        ]
        if !required.isEmpty {
            s["required"] = .array(required.map { .string($0) })
        }
        return .object(s)
    }

    static let all: [Tool] = [
        Tool(
            name: "list_apps",
            description: "List running macOS applications with a UI (instant; no screen recording permission needed).",
            inputSchema: plainSchema([:])
        ),
        Tool(
            name: "list_windows",
            description: "List capturable windows (layer 0, non-zero size). Optionally filter by pid or app name.",
            inputSchema: plainSchema([
                "pid": .object([
                    "type": "integer",
                    "description": "Filter by process ID",
                ]),
                "app_name": .object([
                    "type": "string",
                    "description": "Filter by app name (case-insensitive substring)",
                ]),
            ])
        ),
        Tool(
            name: "capture_app",
            description: "Capture the main window of an app by name, bundle id, or pid. Returns an image plus metadata.",
            inputSchema: schema(
                [
                    "app": .object([
                        "type": "string",
                        "description": "App name, bundle identifier, or pid",
                    ]),
                    "window_title": .object([
                        "type": "string",
                        "description": "Only consider windows whose title contains this (case-insensitive)",
                    ]),
                    "bring_to_front": .object([
                        "type": "boolean",
                        "description": "Activate the app before capturing (restores minimized windows)",
                        "default": false,
                    ]),
                    "open": .object([
                        "type": "boolean",
                        "description": "Launch the app if not running, then wait up to 15s for a window",
                        "default": false,
                    ]),
                    "delay_seconds": .object([
                        "type": "number",
                        "description": "Wait this long before capturing (after open/bring_to_front), max 60",
                        "default": 0,
                    ]),
                ], required: ["app"])
        ),
        Tool(
            name: "capture_window",
            description: "Capture a specific window by its window_id (from list_windows).",
            inputSchema: schema(
                [
                    "window_id": .object([
                        "type": "integer",
                        "description": "Window ID from list_windows",
                    ]),
                    "delay_seconds": .object([
                        "type": "number",
                        "description": "Wait this long before capturing, max 60",
                        "default": 0,
                    ]),
                ], required: ["window_id"])
        ),
        Tool(
            name: "capture_screen",
            description: "Capture the full screen or a region {x,y,w,h} in display points.",
            inputSchema: schema([
                "region": .object([
                    "type": "object",
                    "description": "Region in points {x, y, w, h}; omit for full screen",
                    "properties": .object([
                        "x": .object(["type": "number"]),
                        "y": .object(["type": "number"]),
                        "w": .object(["type": "number"]),
                        "h": .object(["type": "number"]),
                    ]),
                ]),
            ])
        ),
        Tool(
            name: "read_ui",
            description: "Read the accessibility tree of an app's window: roles, titles, values, frames. Needs Accessibility permission.",
            inputSchema: plainSchema(
                [
                    "app": .object([
                        "type": "string",
                        "description": "App name, bundle identifier, or pid",
                    ]),
                    "window_title": .object([
                        "type": "string",
                        "description": "Window whose title contains this (default: main/focused window)",
                    ]),
                    "max_depth": .object([
                        "type": "integer",
                        "description": "Max tree depth",
                        "default": 12,
                    ]),
                    "max_nodes": .object([
                        "type": "integer",
                        "description": "Max nodes returned",
                        "default": 1500,
                    ]),
                ], required: ["app"])
        ),
        Tool(
            name: "event_driven_screengrab",
            description: "Watch an app for UI events (window created/moved, title/focus/value changes), then capture the window once an event fires (or on timeout). Needs Accessibility + Screen Recording.",
            inputSchema: schema(
                [
                    "app": .object([
                        "type": "string",
                        "description": "App name, bundle identifier, or pid",
                    ]),
                    "window_title": .object([
                        "type": "string",
                        "description": "Only consider windows whose title contains this (case-insensitive)",
                    ]),
                    "events": .object([
                        "type": "array",
                        "description": "Events to watch; default all",
                        "items": .object([
                            "type": "string",
                            "enum": .array([
                                "window_created", "window_moved_or_resized",
                                "title_changed", "focus_changed",
                                "value_changed", "ui_changed",
                            ]),
                        ]),
                    ]),
                    "timeout_seconds": .object([
                        "type": "integer",
                        "description": "Max wait for an event, max 300",
                        "default": 30,
                    ]),
                    "settle_ms": .object([
                        "type": "integer",
                        "description": "Delay after an event before capturing, so the UI settles",
                        "default": 300,
                    ]),
                ], required: ["app"])
        ),
        Tool(
            name: "check_permissions",
            description: "Check whether the host process has macOS Screen Recording and Accessibility permissions.",
            inputSchema: plainSchema([
                "request": .object([
                    "type": "boolean",
                    "description": "Trigger the system permission prompts if not granted",
                    "default": false,
                ]),
            ])
        ),
    ]

    static func call(_ params: CallTool.Parameters) async -> CallTool.Result {
        let args = params.arguments ?? [:]
        do {
            switch params.name {
            case "list_apps":
                return .init(content: [.text(text: try json(listAppsJSON()), annotations: nil, _meta: nil)])
            case "list_windows":
                return .init(content: [.text(text: try await json(listWindowsJSON(args)), annotations: nil, _meta: nil)])
            case "capture_app":
                return try await captureApp(args)
            case "capture_window":
                return try await captureWindowById(args)
            case "capture_screen":
                return try await captureScreen(args)
            case "read_ui":
                return try readUI(args)
            case "event_driven_screengrab":
                return try await eventDrivenCapture(args)
            case "check_permissions":
                return checkPermissions(args)
            default:
                return fail("Unknown tool: \(params.name)")
            }
        } catch let e as CaptureError {
            return fail(e.localizedDescription)
        } catch let e as NSError where isPermissionError(e) {
            return fail(CaptureError.noPermission.localizedDescription)
        } catch {
            return fail("\(params.name) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Handlers

    private static func listAppsJSON() -> [[String: Any]] {
        AppLister.listApps().map { app in
            [
                "pid": app.pid,
                "name": app.name,
                "bundle_id": app.bundleId ?? "",
                "is_active": app.isActive,
                "is_hidden": app.isHidden,
                "window_count": app.windowCount,
            ]
        }
    }

    private static func listWindowsJSON(_ args: [String: Value]) async throws -> [[String: Any]] {
        let windows = try await WindowLister.list(
            pid: args["pid"]?.intValue,
            appName: args["app_name"]?.stringValue
        )
        return windows.map { w in
            [
                "window_id": w.windowId,
                "title": w.title,
                "app": w.appName,
                "bundle_id": w.bundleId ?? "",
                "pid": w.pid,
                "frame": [
                    "x": w.frame.origin.x, "y": w.frame.origin.y,
                    "w": w.frame.width, "h": w.frame.height,
                ],
                "is_on_screen": w.isOnScreen,
                "layer": w.layer,
            ]
        }
    }

    private static func captureApp(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let query = args["app"]?.stringValue, !query.isEmpty else {
            return fail("capture_app requires 'app'")
        }
        let open = args["open"]?.boolValue ?? false
        var apps = AppLister.listApps()
        var app = WindowSelection.matchApp(query: query, apps: apps)
        if app == nil, open {
            app = try await openAndWait(query: query)
            apps = AppLister.listApps()
        }
        guard let app else {
            let names = apps.map(\.name).sorted().joined(separator: ", ")
            return fail("App not found for '\(query)'. Running apps: \(names)")
        }
        if args["bring_to_front"]?.boolValue == true {
            AppLister.activate(pid: app.pid)
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        try await delayIfRequested(args)

        let content = try await WindowLister.shareableContent()
        guard let scWindow = try pickSCWindow(
            content: content, pid: app.pid,
            titleContains: args["window_title"]?.stringValue)
        else {
            return fail("No capturable window found for app '\(app.name)' (pid \(app.pid)).")
        }
        let image = try await Capturer.captureWindow(scWindow)
        return try produceResult(
            image: image, args: args, appName: app.name,
            meta: [
                "app": app.name,
                "window_id": Int(scWindow.windowID),
                "title": scWindow.title ?? "",
            ])
    }

    private static func captureWindowById(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let windowId = args["window_id"]?.intValue else {
            return fail("capture_window requires 'window_id' (integer)")
        }
        try await delayIfRequested(args)
        let content = try await WindowLister.shareableContent()
        guard let scWindow = content.windows.first(where: {
            $0.windowID == CGWindowID(windowId)
        }) else {
            return fail("Window \(windowId) not found. Run list_windows to see available ids.")
        }
        let image = try await Capturer.captureWindow(scWindow)
        return try produceResult(
            image: image, args: args,
            appName: scWindow.owningApplication?.applicationName,
            meta: [
                "app": scWindow.owningApplication?.applicationName ?? "",
                "window_id": windowId,
                "title": scWindow.title ?? "",
            ])
    }

    private static func captureScreen(_ args: [String: Value]) async throws -> CallTool.Result {
        let content = try await WindowLister.shareableContent()
        guard let display = content.displays.first else {
            return fail("No display found.")
        }
        var region: CGRect? = nil
        if let r = args["region"]?.objectValue {
            let x = r["x"]?.doubleValue ?? 0
            let y = r["y"]?.doubleValue ?? 0
            let w = r["w"]?.doubleValue ?? 0
            let h = r["h"]?.doubleValue ?? 0
            if w > 0, h > 0 { region = CGRect(x: x, y: y, width: w, height: h) }
        }
        let image = try await Capturer.captureScreen(display: display, region: region)
        return try produceResult(
            image: image, args: args, appName: "screen", meta: ["app": "screen"])
    }

    private static func readUI(_ args: [String: Value]) throws -> CallTool.Result {
        guard let query = args["app"]?.stringValue, !query.isEmpty else {
            return fail("read_ui requires 'app'")
        }
        guard Permissions.hasAccessibility() else {
            return fail("No Accessibility permission. \(Permissions.accessibilityHint)")
        }
        let apps = AppLister.listApps()
        guard let app = WindowSelection.matchApp(query: query, apps: apps) else {
            let names = apps.map(\.name).sorted().joined(separator: ", ")
            return fail("App not found for '\(query)'. Running apps: \(names)")
        }
        let maxDepth = max(args["max_depth"]?.intValue ?? 12, 1)
        let maxNodes = max(args["max_nodes"]?.intValue ?? 1500, 1)
        let obj = try AccessibilityReader.readUI(
            pid: Int32(app.pid),
            windowTitle: args["window_title"]?.stringValue,
            maxDepth: maxDepth, maxNodes: maxNodes)
        return .init(content: [.text(text: try json(obj), annotations: nil, _meta: nil)])
    }

    private static func eventDrivenCapture(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let query = args["app"]?.stringValue, !query.isEmpty else {
            return fail("event_driven_screengrab requires 'app'")
        }
        guard Permissions.hasAccessibility() else {
            return fail("No Accessibility permission. \(Permissions.accessibilityHint)")
        }
        let apps = AppLister.listApps()
        guard let app = WindowSelection.matchApp(query: query, apps: apps) else {
            let names = apps.map(\.name).sorted().joined(separator: ", ")
            return fail("App not found for '\(query)'. Running apps: \(names)")
        }
        let windowTitle = args["window_title"]?.stringValue
        let axApp = AXUIElementCreateApplication(Int32(app.pid))
        let axWindow = AccessibilityReader.pickWindow(
            app: axApp, titleContains: windowTitle)
        var events: Set<String>? = nil
        if let arr = args["events"]?.arrayValue {
            events = Set(arr.compactMap(\.stringValue))
        }
        let watch = await EventWatcher.watch(
            pid: Int32(app.pid), window: axWindow, events: events,
            timeoutSeconds: args["timeout_seconds"]?.intValue ?? 30)
        if !watch.timedOut {
            let settle = max(args["settle_ms"]?.intValue ?? 300, 0)
            try await Task.sleep(nanoseconds: UInt64(settle) * 1_000_000)
        }

        let content = try await WindowLister.shareableContent()
        guard let scWindow = try pickSCWindow(
            content: content, pid: app.pid, titleContains: windowTitle)
        else {
            return fail("No capturable window found for app '\(app.name)' (pid \(app.pid)).")
        }
        let image = try await Capturer.captureWindow(scWindow)
        var meta: [String: Any] = [
            "app": app.name,
            "window_id": Int(scWindow.windowID),
            "title": scWindow.title ?? "",
            "timed_out": watch.timedOut,
            "waited_ms": watch.waitedMs,
        ]
        if let event = watch.event { meta["event"] = event }
        if watch.elementRole != nil || watch.elementTitle != nil {
            var el: [String: Any] = [:]
            if let r = watch.elementRole { el["role"] = r }
            if let t = watch.elementTitle { el["title"] = t }
            meta["element"] = el
        }
        return try produceResult(
            image: image, args: args, appName: app.name, meta: meta)
    }

    private static func checkPermissions(_ args: [String: Value]) -> CallTool.Result {
        var screen = Permissions.hasScreenRecording()
        var ax = Permissions.hasAccessibility()
        if args["request"]?.boolValue == true {
            if !screen { screen = Permissions.requestScreenRecording() }
            if !ax { ax = Permissions.requestAccessibility() }
        }
        let obj: [String: Any] = [
            "screen_recording": screen,
            "accessibility": ax,
            "hint": Permissions.screenRecordingHint,
            "accessibility_hint": Permissions.accessibilityHint,
        ]
        return .init(content: [.text(text: (try? json(obj)) ?? "{}", annotations: nil, _meta: nil)])
    }

    // MARK: - Shared capture pipeline

    private struct OutputOptions {
        var format: ImageFormat
        var jpegQuality: Double
        var maxWidth: Int?
        var returnImage: Bool
        var returnDiffImage: Bool
        var savePath: String?
        var compareWith: String?

        init(_ args: [String: Value]) {
            let quality = args["quality"]?.stringValue ?? "high"
            if let f = args["format"]?.stringValue, let fmt = ImageFormat(rawValue: f) {
                format = fmt
            } else {
                format = quality == "low" ? .jpeg : .png
            }
            let defaultJpeg = quality == "low" ? 0.6 : 0.85
            jpegQuality = min(max(args["jpeg_quality"]?.doubleValue ?? defaultJpeg, 0), 1)
            if let mw = args["max_width"]?.intValue, mw > 0 {
                maxWidth = mw
            } else {
                maxWidth = quality == "low" ? 1024 : nil
            }
            returnImage = args["return_image"]?.boolValue ?? true
            returnDiffImage = args["return_diff_image"]?.boolValue ?? false
            savePath = args["save_path"]?.stringValue
            compareWith = args["compare_with"]?.stringValue
        }
    }

    /// Encode (downscale/format), save, optionally diff, build the result.
    private static func produceResult(
        image: CGImage, args: [String: Value], appName: String?,
        meta: [String: Any]
    ) throws -> CallTool.Result {
        let opts = OutputOptions(args)
        let out = ImageEncoder.resized(image, maxWidth: opts.maxWidth)
        let data = try ImageEncoder.encode(
            out, format: opts.format, jpegQuality: opts.jpegQuality)
        let path = try Capturer.save(
            data: data, savePath: opts.savePath, appName: appName,
            ext: opts.format.fileExtension)

        var meta = meta
        meta["path"] = path
        meta["width"] = out.width
        meta["height"] = out.height
        meta["format"] = opts.format.rawValue
        meta["bytes"] = data.count
        meta["timestamp"] = ISO8601DateFormatter().string(from: Date())

        var diffImageData: Data? = nil
        if let comparePath = opts.compareWith {
            let prev = loadImage(path: comparePath)
            if let prev,
               let (stats, diffPixels) = ImageDiff.compare(old: prev, new: out),
               let diffImg = ImageDiff.image(
                fromRGBA8: diffPixels, width: out.width, height: out.height)
            {
                let diffData = try ImageEncoder.encode(diffImg, format: .png)
                let diffPath = "\(path)-diff.png"
                try diffData.write(to: URL(fileURLWithPath: diffPath))
                var diffMeta: [String: Any] = [
                    "compare_with": (comparePath as NSString).expandingTildeInPath,
                    "changed_pixels": stats.changedPixels,
                    "total_pixels": stats.totalPixels,
                    "changed_percent": stats.changedPercent,
                    "diff_path": diffPath,
                ]
                if let bb = stats.boundingBox {
                    diffMeta["bounding_box"] = [
                        "x": bb.origin.x, "y": bb.origin.y,
                        "w": bb.size.width, "h": bb.size.height,
                    ]
                }
                meta["diff"] = diffMeta
                diffImageData = diffData
            } else {
                meta["diff_error"] = "Could not load compare_with image"
            }
        }

        var content: [Tool.Content] = []
        if opts.returnImage {
            content.append(.image(
                data: data.base64EncodedString(), mimeType: opts.format.mimeType,
                annotations: nil, _meta: nil))
            if opts.returnDiffImage, let diffImageData {
                content.append(.image(
                    data: diffImageData.base64EncodedString(), mimeType: "image/png",
                    annotations: nil, _meta: nil))
            }
        }
        content.append(.text(
            text: (try? json(meta)) ?? "{}", annotations: nil, _meta: nil))
        return .init(content: content)
    }

    private static func pickSCWindow(
        content: SCShareableContent, pid: Int, titleContains: String?
    ) throws -> SCWindow? {
        let candidates = WindowLister.windows(from: content)
            .filter { $0.pid == pid }
        guard let pick = WindowSelection.pickMainWindow(
            from: candidates, titleContains: titleContains)
        else { return nil }
        return content.windows.first { $0.windowID == CGWindowID(pick.windowId) }
    }

    private static func delayIfRequested(_ args: [String: Value]) async throws {
        let delay = args["delay_seconds"]?.doubleValue
            ?? Double(args["delay_seconds"]?.intValue ?? 0)
        let clamped = min(max(delay, 0), 60)
        if clamped > 0 {
            try await Task.sleep(nanoseconds: UInt64(clamped * 1e9))
        }
    }

    /// Launch an app and poll up to 15s for a layer-0 window.
    private static func openAndWait(query: String) async throws -> AppInfo {
        guard let url = appURL(for: query) else {
            throw CaptureError.appNotFound(
                "App '\(query)' is not running and no .app bundle was found for it.")
        }
        let bundleId = Bundle(url: url)?.bundleIdentifier
        try await NSWorkspace.shared.openApplication(
            at: url, configuration: NSWorkspace.OpenConfiguration())

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 500_000_000)
            let apps = AppLister.listApps()
            let app = bundleId.flatMap {
                WindowSelection.matchApp(query: $0, apps: apps)
            } ?? WindowSelection.matchApp(query: query, apps: apps)
            if let app,
               let content = try? await WindowLister.shareableContent() {
                let wins = WindowLister.windows(from: content)
                let hasWindow = wins.contains {
                    $0.pid == app.pid && $0.layer == 0
                        && $0.frame.width > 0 && $0.frame.height > 0
                }
                if hasWindow { return app }
            }
        }
        throw CaptureError.windowNotFound(
            "App '\(query)' launched but no capturable window appeared within 15s.")
    }

    /// Resolve an app bundle URL by bundle id or by searching the Applications dirs.
    private static func appURL(for query: String) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: query) { return url }
        let dirs = [
            "/Applications",
            "/System/Applications",
            ("~/Applications" as NSString).expandingTildeInPath,
        ]
        for dir in dirs {
            let exact = "\(dir)/\(query).app"
            if FileManager.default.fileExists(atPath: exact) {
                return URL(fileURLWithPath: exact)
            }
            if let items = try? FileManager.default.contentsOfDirectory(atPath: dir),
               let match = items.first(where: {
                   $0.hasSuffix(".app")
                       && $0.range(of: query, options: .caseInsensitive) != nil
               }) {
                return URL(fileURLWithPath: "\(dir)/\(match)")
            }
        }
        return nil
    }

    private static func loadImage(path: String) -> CGImage? {
        let p = (path as NSString).expandingTildeInPath
        guard let src = CGImageSourceCreateWithURL(
            URL(fileURLWithPath: p) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: - Helpers

    private static func fail(_ message: String) -> CallTool.Result {
        .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    private static func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func isPermissionError(_ e: NSError) -> Bool {
        e.domain.contains("ScreenCaptureKit") || e.domain.contains("CoreMedia")
            || e.code == -3801 || e.code == -3802
    }
}
