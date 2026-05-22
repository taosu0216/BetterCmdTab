import AppKit
import ApplicationServices

enum Activator {
    private static let finderBundleID = "com.apple.finder"

    static func activateApp(_ app: NSRunningApplication) {
        if app.isHidden {
            app.unhide()
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.1)
        var windowsValue: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
        let windows = (windowsValue as? [AXUIElement]) ?? []
        if windows.isEmpty {
            openFreshWindow(for: app)
            return
        }
        for window in windows {
            var minimizedValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            if (minimizedValue as? Bool) == true {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                break
            }
        }
        bringToFront(app)
    }

    static func activate(_ row: SwitcherRow) {
        let app = row.app

        if app.isHidden {
            app.unhide()
        }

        guard let window = row.window else {
            openFreshWindow(for: app)
            return
        }

        var minimizedValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
        if (minimizedValue as? Bool) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        if let tabRef = row.tabRef {
            focusTab(tabRef)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        bringToFront(app)
    }

    private static func bringToFront(_ app: NSRunningApplication) {
        if let url = app.bundleURL {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in }
            return
        }
        if #available(macOS 14.0, *) {
            _ = app.activate(from: NSRunningApplication.current, options: [])
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func openFreshWindow(for app: NSRunningApplication) {
        if app.bundleIdentifier == finderBundleID {
            openNewFinderWindow()
            bringToFront(app)
            return
        }
        guard let url = app.bundleURL else {
            bringToFront(app)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    }

    private static func openNewFinderWindow() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([home], withApplicationAt: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), configuration: config) { _, _ in }
    }

    static func closeWindow(_ row: SwitcherRow) {
        let window = row.window
        let tabRef = row.tabRef
        let pid = row.pid

        DispatchQueue.global(qos: .userInitiated).async {
            if let tabRef {
                focusTab(tabRef)
                waitForTabSelected(tabRef, timeout: 0.3)
                if let shortcut = closeTabShortcut(pid: pid) {
                    postKeyShortcut(pid: pid, keyCode: 13, axModifiers: shortcut)
                    return
                }
            }
            guard let window else { return }
            var buttonValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &buttonValue)
            guard CFGetTypeID(buttonValue as CFTypeRef) == AXUIElementGetTypeID() else { return }
            let button = buttonValue as! AXUIElement
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    static func minimizeWindow(_ row: SwitcherRow) {
        guard let window = row.window else { return }
        let tabRef = row.tabRef
        DispatchQueue.global(qos: .userInitiated).async {
            if let tabRef {
                focusTab(tabRef)
                waitForTabSelected(tabRef, timeout: 0.25)
            }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    private static func focusTab(_ tabRef: AXUIElement) {
        AXUIElementSetAttributeValue(tabRef, kAXValueAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(tabRef, kAXPressAction as CFString)
    }

    private static let tabTitleTokens: [String] = ["tab", "karta", "kart", "onglet", "reiter", "scheda", "pestaña", "pestana", "вкладк"]
    private static let windowTitleTokens: [String] = ["window", "okno", "fenster", "fenêtre", "fenetre", "finestra", "ventana", "окно"]

    private static func closeTabShortcut(pid: pid_t) -> Int? {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        var menuBarValue: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue)
        guard CFGetTypeID(menuBarValue as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        let menuBar = menuBarValue as! AXUIElement

        var candidates: [(title: String, mods: Int)] = []
        collectMenuItems(in: menuBar, cmdChar: "w", into: &candidates, depth: 0)
        if candidates.isEmpty { return nil }

        if let tabItem = candidates.first(where: { c in
            let t = c.title.lowercased()
            return tabTitleTokens.contains(where: { t.contains($0) })
        }) {
            return tabItem.mods
        }
        if let nonWindow = candidates.first(where: { c in
            let t = c.title.lowercased()
            return !windowTitleTokens.contains(where: { t.contains($0) })
        }) {
            return nonWindow.mods
        }
        if let plain = candidates.first(where: { $0.mods == 0 }) {
            return plain.mods
        }
        return candidates[0].mods
    }

    private static func collectMenuItems(in element: AXUIElement, cmdChar: String, into out: inout [(title: String, mods: Int)], depth: Int) {
        if depth > 6 { return }

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? ""

        if role == kAXMenuItemRole {
            var charValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &charValue)
            var modsValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &modsValue)
            if let c = charValue as? String,
               c.lowercased() == cmdChar.lowercased(),
               let m = (modsValue as? NSNumber)?.intValue {
                var titleValue: AnyObject?
                AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
                let title = (titleValue as? String) ?? ""
                out.append((title, m))
            }
        }

        var childrenValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        guard let children = childrenValue as? [AXUIElement] else { return }
        for child in children {
            collectMenuItems(in: child, cmdChar: cmdChar, into: &out, depth: depth + 1)
        }
    }

    private static func postKeyShortcut(pid: pid_t, keyCode: CGKeyCode, axModifiers: Int) {
        let src = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else { return }

        var flags: CGEventFlags = []
        if (axModifiers & 8) == 0 { flags.insert(.maskCommand) }
        if (axModifiers & 1) != 0 { flags.insert(.maskShift) }
        if (axModifiers & 2) != 0 { flags.insert(.maskAlternate) }
        if (axModifiers & 4) != 0 { flags.insert(.maskControl) }

        down.flags = flags
        up.flags = flags
        down.postToPid(pid)
        up.postToPid(pid)
    }

    private static func waitForTabSelected(_ tabRef: AXUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var v: AnyObject?
            AXUIElementCopyAttributeValue(tabRef, kAXValueAttribute as CFString, &v)
            if let b = v as? Bool, b { return }
            if let n = v as? NSNumber, n.boolValue { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    static func hideApp(_ row: SwitcherRow) {
        row.app.hide()
    }

    static func quitApp(_ row: SwitcherRow) {
        if row.app.bundleIdentifier == finderBundleID {
            return
        }
        row.app.terminate()
    }
}
