import CoreGraphics
import Foundation
import MCP
import ScreenCaptureKit

enum Tools {
    static let all: [Tool] = [
        Tool(
            name: "list_apps",
            description: "List running macOS applications with a UI (instant; no screen recording permission needed).",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ])
        ),
        Tool(
            name: "list_windows",
            description: "List capturable windows (layer 0, non-zero size). Optionally filter by pid or app name.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "pid": .object([
                        "type": "integer",
                        "description": "Filter by process ID",
                    ]),
                    "app_name": .object([
                        "type": "string",
                        "description": "Filter by app name (case-insensitive substring)",
                    ]),
                ]),
            ])
        ),
        Tool(
            name: "capture_app",
            description: "Capture the main window of an app by name, bundle id, or pid. Returns a PNG image plus metadata.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
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
                    "save_path": .object([
                        "type": "string",
                        "description": "Where to save the PNG (default: ~/Pictures/mcp-captures/)",
                    ]),
                    "return_image": .object([
                        "type": "boolean",
                        "description": "Include base64 PNG image content in the response",
                        "default": true,
                    ]),
                ]),
                "required": .array(["app"]),
            ])
        ),
        Tool(
            name: "capture_window",
            description: "Capture a specific window by its window_id (from list_windows).",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "window_id": .object([
                        "type": "integer",
                        "description": "Window ID from list_windows",
                    ]),
                    "save_path": .object([
                        "type": "string",
                        "description": "Where to save the PNG (default: ~/Pictures/mcp-captures/)",
                    ]),
                    "return_image": .object([
                        "type": "boolean",
                        "description": "Include base64 PNG image content in the response",
                        "default": true,
                    ]),
                ]),
                "required": .array(["window_id"]),
            ])
        ),
        Tool(
            name: "capture_screen",
            description: "Capture the full screen or a region {x,y,w,h} in display points.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
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
                    "save_path": .object([
                        "type": "string",
                        "description": "Where to save the PNG (default: ~/Pictures/mcp-captures/)",
                    ]),
                    "return_image": .object([
                        "type": "boolean",
                        "description": "Include base64 PNG image content in the response",
                        "default": true,
                    ]),
                ]),
            ])
        ),
        Tool(
            name: "check_permissions",
            description: "Check whether the host process has macOS Screen Recording permission.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "request": .object([
                        "type": "boolean",
                        "description": "Trigger the system permission prompt if not granted",
                        "default": false,
                    ]),
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
        let apps = AppLister.listApps()
        guard let app = WindowSelection.matchApp(query: query, apps: apps) else {
            let names = apps.map(\.name).sorted().joined(separator: ", ")
            return fail("App not found for '\(query)'. Running apps: \(names)")
        }
        if args["bring_to_front"]?.boolValue == true {
            AppLister.activate(pid: app.pid)
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        let content = try await WindowLister.shareableContent()
        let candidates = WindowLister.windows(from: content)
            .filter { $0.pid == app.pid }
        guard let pick = WindowSelection.pickMainWindow(
            from: candidates,
            titleContains: args["window_title"]?.stringValue
        ) else {
            return fail("No capturable window found for app '\(app.name)' (pid \(app.pid)).")
        }
        guard let scWindow = content.windows.first(where: {
            $0.windowID == CGWindowID(pick.windowId)
        }) else {
            return fail("Window \(pick.windowId) no longer available.")
        }
        let returnImage = args["return_image"]?.boolValue ?? true
        let image = try await Capturer.captureWindow(scWindow)
        let png = try Capturer.pngData(from: image)
        let path = try Capturer.save(
            png: png, savePath: args["save_path"]?.stringValue, appName: app.name)
        let meta: [String: Any] = [
            "path": path,
            "width": image.width,
            "height": image.height,
            "app": app.name,
            "window_id": pick.windowId,
            "title": pick.title,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        return captureResult(png: png, meta: meta, returnImage: returnImage)
    }

    private static func captureWindowById(_ args: [String: Value]) async throws -> CallTool.Result {
        guard let windowId = args["window_id"]?.intValue else {
            return fail("capture_window requires 'window_id' (integer)")
        }
        let content = try await WindowLister.shareableContent()
        guard let scWindow = content.windows.first(where: {
            $0.windowID == CGWindowID(windowId)
        }) else {
            return fail("Window \(windowId) not found. Run list_windows to see available ids.")
        }
        let returnImage = args["return_image"]?.boolValue ?? true
        let image = try await Capturer.captureWindow(scWindow)
        let png = try Capturer.pngData(from: image)
        let appName = scWindow.owningApplication?.applicationName
        let path = try Capturer.save(
            png: png, savePath: args["save_path"]?.stringValue, appName: appName)
        let meta: [String: Any] = [
            "path": path,
            "width": image.width,
            "height": image.height,
            "app": appName ?? "",
            "window_id": windowId,
            "title": scWindow.title ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        return captureResult(png: png, meta: meta, returnImage: returnImage)
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
        let returnImage = args["return_image"]?.boolValue ?? true
        let image = try await Capturer.captureScreen(
            display: display, region: region)
        let png = try Capturer.pngData(from: image)
        let path = try Capturer.save(
            png: png, savePath: args["save_path"]?.stringValue, appName: "screen")
        let meta: [String: Any] = [
            "path": path,
            "width": image.width,
            "height": image.height,
            "app": "screen",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        return captureResult(png: png, meta: meta, returnImage: returnImage)
    }

    private static func checkPermissions(_ args: [String: Value]) -> CallTool.Result {
        var granted = Permissions.hasScreenRecording()
        if !granted, args["request"]?.boolValue == true {
            granted = Permissions.requestScreenRecording()
        }
        let obj: [String: Any] = [
            "screen_recording": granted,
            "hint": Permissions.hint,
        ]
        return .init(content: [.text(text: (try? json(obj)) ?? "{}", annotations: nil, _meta: nil)])
    }

    // MARK: - Helpers

    private static func captureResult(
        png: Data, meta: [String: Any], returnImage: Bool
    ) -> CallTool.Result {
        var content: [Tool.Content] = []
        if returnImage {
            content.append(.image(
                data: png.base64EncodedString(), mimeType: "image/png",
                annotations: nil, _meta: nil))
        }
        content.append(.text(
            text: (try? json(meta)) ?? "{}", annotations: nil, _meta: nil))
        return .init(content: content)
    }

    private static func fail(_ message: String) -> CallTool.Result {
        .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    private static func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func isPermissionError(_ e: NSError) -> Bool {
        // ScreenCaptureKit surfaces missing TCC permission as stream errors
        // in the ScreenCaptureKit/CoreMedia domains.
        e.domain.contains("ScreenCaptureKit") || e.domain.contains("CoreMedia")
            || e.code == -3801 || e.code == -3802
    }
}
