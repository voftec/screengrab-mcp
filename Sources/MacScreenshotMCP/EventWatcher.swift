@preconcurrency import ApplicationServices
import Foundation

struct WatchResult: Sendable {
    var event: String?
    var elementRole: String?
    var elementTitle: String?
    var waitedMs: Int
    var timedOut: Bool
}

/// Maps notification names to the public event names.
private let notificationToEvent: [(CFString, String)] = [
    (kAXWindowCreatedNotification as CFString, "window_created"),
    (kAXWindowMovedNotification as CFString, "window_moved_or_resized"),
    (kAXWindowResizedNotification as CFString, "window_moved_or_resized"),
    (kAXTitleChangedNotification as CFString, "title_changed"),
    (kAXFocusedWindowChangedNotification as CFString, "focus_changed"),
    (kAXFocusedUIElementChangedNotification as CFString, "focus_changed"),
    (kAXValueChangedNotification as CFString, "value_changed"),
    (kAXUIElementDestroyedNotification as CFString, "ui_changed"),
    (kAXLayoutChangedNotification as CFString, "ui_changed"),
]

private let allEvents: Set<String> = Set(notificationToEvent.map(\.1))

private final class WatchBox: @unchecked Sendable {
    let lock = NSLock()
    var continuation: CheckedContinuation<WatchResult, Never>?
    var pendingResult: WatchResult?
    var timeoutTask: Task<Void, Never>?
    var done = false
    var start = Date()

    func isDone() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    func resolve(_ result: WatchResult) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        timeoutTask?.cancel()
        if let cont = continuation {
            cont.resume(returning: result)
        } else {
            pendingResult = result
        }
    }

    func eventResult(name: String, role: String?, title: String?) -> WatchResult {
        WatchResult(
            event: name, elementRole: role, elementTitle: title,
            waitedMs: Int(Date().timeIntervalSince(start) * 1000), timedOut: false)
    }
}

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let box = Unmanaged<WatchBox>.fromOpaque(refcon).takeUnretainedValue()
    let name = notificationToEvent.first(where: {
        CFEqual($0.0, notification)
    })?.1 ?? (notification as String)

    var role: String?
    var title: String?
    if let r = AccessibilityReader.copyAttribute(element, kAXRoleAttribute) as? String {
        role = r
    }
    if let t = AccessibilityReader.copyAttribute(element, kAXTitleAttribute) as? String {
        title = t
    }
    box.resolve(box.eventResult(name: name, role: role, title: title))
}

enum EventWatcher {
    /// Watch `pid` (optionally a specific window element) for the given events.
    /// Resolves on the first matching event or after `timeout` seconds.
    static func watch(
        pid: Int32,
        window: AXUIElement?,
        events: Set<String>?,
        timeoutSeconds: Int
    ) async -> WatchResult {
        let wanted = events ?? allEvents
        let box = WatchBox()
        let boxPtr = Unmanaged.passRetained(box).toOpaque()

        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success,
              let observer else {
            Unmanaged<WatchBox>.fromOpaque(boxPtr).release()
            return WatchResult(waitedMs: 0, timedOut: true)
        }

        let app = AXUIElementCreateApplication(pid)
        var attached: [(element: AXUIElement, notif: CFString)] = []
        for (notif, event) in notificationToEvent where wanted.contains(event) {
            if AXObserverAddNotification(observer, app, notif, boxPtr) == .success {
                attached.append((app, notif))
            }
            if let window,
               AXObserverAddNotification(observer, window, notif, boxPtr) == .success {
                attached.append((window, notif))
            }
        }

        // Run the observer's run-loop source on a dedicated thread until
        // the box is resolved, then remove notifications and the source.
        let boxForThread = box
        let boxAddr = UInt(bitPattern: boxPtr)
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            let thread = Thread {
                let rl = CFRunLoopGetCurrent()!
                let source = AXObserverGetRunLoopSource(observer)
                CFRunLoopAddSource(rl, source, .defaultMode)
                ready.resume()
                while !boxForThread.isDone() {
                    _ = CFRunLoopRunInMode(.defaultMode, 0.25, true)
                }
                for (element, notif) in attached {
                    AXObserverRemoveNotification(observer, element, notif)
                }
                CFRunLoopRemoveSource(rl, source, .defaultMode)
                Unmanaged<WatchBox>
                    .fromOpaque(UnsafeMutableRawPointer(bitPattern: boxAddr)!)
                    .release()
            }
            thread.name = "screengrab-mcp.eventwatcher"
            thread.start()
        }

        return await withCheckedContinuation { cont in
            box.lock.lock()
            if let pending = box.pendingResult {
                box.lock.unlock()
                cont.resume(returning: pending)
                return
            }
            box.continuation = cont
            box.lock.unlock()

            let timeout = TimeInterval(min(max(timeoutSeconds, 1), 300))
            let task = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
                box.resolve(
                    WatchResult(
                        waitedMs: Int(timeout * 1000), timedOut: true))
            }
            box.lock.lock()
            box.timeoutTask = task
            let alreadyDone = box.done
            box.lock.unlock()
            if alreadyDone { task.cancel() }
        }
    }
}
