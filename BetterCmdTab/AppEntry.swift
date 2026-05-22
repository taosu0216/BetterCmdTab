import AppKit
import ApplicationServices

struct SwitcherRow {
    let app: NSRunningApplication
    let window: AXUIElement?
    let tabRef: AXUIElement?
    let windowTitle: String
    let isMinimized: Bool
    let isPlaceholder: Bool

    init(
        app: NSRunningApplication,
        window: AXUIElement?,
        windowTitle: String,
        isMinimized: Bool,
        tabRef: AXUIElement? = nil,
        isPlaceholder: Bool = false
    ) {
        self.app = app
        self.window = window
        self.tabRef = tabRef
        self.windowTitle = windowTitle
        self.isMinimized = isMinimized
        self.isPlaceholder = isPlaceholder
    }

    var pid: pid_t { app.processIdentifier }
    var appName: String { app.localizedName ?? "" }
    var icon: NSImage? { app.icon }
    var displayTitle: String {
        if isPlaceholder { return appName }
        if window == nil { return appName }
        return windowTitle.isEmpty ? appName : windowTitle
    }
    var bundleIdentifier: String? { app.bundleIdentifier }
}
