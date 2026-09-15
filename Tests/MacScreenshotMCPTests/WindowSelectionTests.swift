import CoreGraphics
import XCTest
@testable import MacScreenshotMCP

final class WindowSelectionTests: XCTestCase {

    private func w(
        id: Int, title: String = "", area: CGSize = CGSize(width: 800, height: 600),
        onScreen: Bool = true, layer: Int = 0, pid: Int = 1
    ) -> WindowInfo {
        WindowInfo(
            windowId: id, title: title, appName: "App", bundleId: "com.test.app",
            pid: pid, frame: CGRect(origin: .zero, size: area),
            isOnScreen: onScreen, layer: layer)
    }

    private func app(pid: Int, name: String, bundleId: String? = nil) -> AppInfo {
        AppInfo(pid: pid, name: name, bundleId: bundleId,
                isActive: false, isHidden: false, windowCount: 1)
    }

    // MARK: pickMainWindow

    func testPickMainWindowPrefersTitleMatch() {
        let small = w(id: 1, title: "Settings — My Project", area: CGSize(width: 200, height: 100))
        let big = w(id: 2, title: "Other", area: CGSize(width: 2000, height: 2000))
        let picked = WindowSelection.pickMainWindow(from: [small, big], titleContains: "settings")
        XCTAssertEqual(picked?.windowId, 1)
    }

    func testPickMainWindowLargestAreaFallback() {
        let small = w(id: 1, title: "a", area: CGSize(width: 200, height: 100))
        let big = w(id: 2, title: "b", area: CGSize(width: 2000, height: 2000))
        let picked = WindowSelection.pickMainWindow(from: [small, big])
        XCTAssertEqual(picked?.windowId, 2)
    }

    func testPickMainWindowPrefersOnScreen() {
        let offScreenBig = w(id: 1, area: CGSize(width: 5000, height: 5000), onScreen: false)
        let onScreenSmall = w(id: 2, area: CGSize(width: 100, height: 100), onScreen: true)
        let picked = WindowSelection.pickMainWindow(from: [offScreenBig, onScreenSmall])
        XCTAssertEqual(picked?.windowId, 2)
    }

    func testPickMainWindowIgnoresNonZeroLayerAndEmpty() {
        let overlay = w(id: 1, layer: 5)
        let empty = w(id: 2, area: .zero)
        let real = w(id: 3, area: CGSize(width: 100, height: 100))
        XCTAssertEqual(
            WindowSelection.pickMainWindow(from: [overlay, empty, real])?.windowId, 3)
        XCTAssertNil(WindowSelection.pickMainWindow(from: [overlay, empty]))
        XCTAssertNil(WindowSelection.pickMainWindow(from: []))
    }

    // MARK: matchApp

    func testMatchAppByPid() {
        let apps = [app(pid: 123, name: "Finder"), app(pid: 456, name: "Safari")]
        XCTAssertEqual(WindowSelection.matchApp(query: "456", apps: apps)?.name, "Safari")
    }

    func testMatchAppByBundleId() {
        let apps = [app(pid: 1, name: "Safari", bundleId: "com.apple.Safari")]
        XCTAssertEqual(
            WindowSelection.matchApp(query: "COM.APPLE.SAFARI", apps: apps)?.name, "Safari")
    }

    func testMatchAppByExactName() {
        let apps = [app(pid: 1, name: "Visual Studio Code")]
        XCTAssertEqual(
            WindowSelection.matchApp(query: "visual studio code", apps: apps)?.pid, 1)
    }

    func testMatchAppBySubstring() {
        let apps = [app(pid: 1, name: "Google Chrome"), app(pid: 2, name: "Finder")]
        XCTAssertEqual(WindowSelection.matchApp(query: "chrome", apps: apps)?.pid, 1)
    }

    func testMatchAppExactBeatsSubstring() {
        let apps = [app(pid: 1, name: "Notes Helper"), app(pid: 2, name: "Notes")]
        XCTAssertEqual(WindowSelection.matchApp(query: "notes", apps: apps)?.pid, 2)
    }

    func testMatchAppNoMatch() {
        let apps = [app(pid: 1, name: "Finder")]
        XCTAssertNil(WindowSelection.matchApp(query: "nonexistent", apps: apps))
        XCTAssertNil(WindowSelection.matchApp(query: "x", apps: []))
    }
}
