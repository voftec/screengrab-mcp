@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

enum AccessibilityReader {
    static let hint =
        "System Settings > Privacy & Security > Accessibility — enable for the host app (Cursor/Claude/Terminal)"

    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    static func requestPrompt() -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    static func copyAttribute(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success
        else { return nil }
        return value
    }

    static func windows(app: AXUIElement) -> [AXUIElement] {
        (copyAttribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// Pick a window element by title substring, else the main/focused window,
    /// else the first window.
    static func pickWindow(
        app: AXUIElement, titleContains: String?
    ) -> AXUIElement? {
        let wins = windows(app: app)
        if let q = titleContains, !q.isEmpty {
            if let w = wins.first(where: {
                ((copyAttribute($0, kAXTitleAttribute) as? String) ?? "")
                    .range(of: q, options: .caseInsensitive) != nil
            }) {
                return w
            }
        }
        if let main = copyAttribute(app, kAXMainWindowAttribute) {
            return (main as! AXUIElement)
        }
        if let focused = copyAttribute(app, kAXFocusedWindowAttribute) {
            return (focused as! AXUIElement)
        }
        return wins.first
    }

    private static func stringValue(_ v: CFTypeRef?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    private static func truncated(_ s: String?, _ limit: Int = 200) -> String? {
        guard let s else { return nil }
        return s.count > limit ? String(s.prefix(limit)) + "…" : s
    }

    private static func frame(of element: AXUIElement) -> [String: Any]? {
        var frame: [String: Any] = [:]
        if let posRef = copyAttribute(element, kAXPositionAttribute),
           CFGetTypeID(posRef) == AXValueGetTypeID() {
            var p = CGPoint.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &p)
            frame["x"] = p.x; frame["y"] = p.y
        }
        if let sizeRef = copyAttribute(element, kAXSizeAttribute),
           CFGetTypeID(sizeRef) == AXValueGetTypeID() {
            var s = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &s)
            frame["w"] = s.width; frame["h"] = s.height
        }
        return frame.isEmpty ? nil : frame
    }

    /// Depth-first walk producing the node JSON tree.
    static func readUI(
        pid: Int32, windowTitle: String?, maxDepth: Int, maxNodes: Int
    ) throws -> [String: Any] {
        let app = AXUIElementCreateApplication(pid)
        guard let window = pickWindow(app: app, titleContains: windowTitle) else {
            throw CaptureError.windowNotFound(
                "No accessibility window found for pid \(pid).")
        }
        depthCapHit = false
        var budget = maxNodes
        let tree = walk(element: window, depth: 0, maxDepth: maxDepth, budget: &budget)
        return [
            "pid": Int(pid),
            "node_count": maxNodes - budget,
            "truncated": budget == 0 || depthCapHit,
            "window": tree ?? NSNull(),
        ]
    }

    private static var depthCapHit = false

    private static func walk(
        element: AXUIElement, depth: Int, maxDepth: Int, budget: inout Int
    ) -> [String: Any]? {
        guard budget > 0 else { return nil }
        budget -= 1
        var node: [String: Any] = [:]
        node["role"] = copyAttribute(element, kAXRoleAttribute) as? String
        if let s = copyAttribute(element, kAXSubroleAttribute) as? String { node["subrole"] = s }
        if let s = truncated(stringValue(copyAttribute(element, kAXTitleAttribute))) {
            node["title"] = s
        }
        if let s = truncated(stringValue(copyAttribute(element, kAXValueAttribute))) {
            node["value"] = s
        }
        if let s = truncated(stringValue(copyAttribute(element, kAXDescriptionAttribute))) {
            node["description"] = s
        }
        if let s = copyAttribute(element, kAXIdentifierAttribute) as? String {
            node["identifier"] = s
        }
        if let b = copyAttribute(element, kAXEnabledAttribute) as? Bool { node["enabled"] = b }
        if let b = copyAttribute(element, kAXFocusedAttribute) as? Bool { node["focused"] = b }
        if let f = frame(of: element) { node["frame"] = f }

        if depth < maxDepth, budget > 0,
           let children = copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            var kids: [[String: Any]] = []
            for child in children {
                guard budget > 0 else { break }
                if let c = walk(element: child, depth: depth + 1, maxDepth: maxDepth, budget: &budget) {
                    kids.append(c)
                }
            }
            if !kids.isEmpty { node["children"] = kids }
        } else if depth >= maxDepth {
            depthCapHit = true
        }
        return node
    }
}
