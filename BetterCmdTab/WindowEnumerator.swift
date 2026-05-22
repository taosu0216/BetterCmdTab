import AppKit
import ApplicationServices

struct WindowInfo {
    let ref: AXUIElement
    let title: String
    let isMinimized: Bool
    let isFullscreen: Bool
    let tabRef: AXUIElement?

    init(
        ref: AXUIElement,
        title: String,
        isMinimized: Bool,
        isFullscreen: Bool = false,
        tabRef: AXUIElement? = nil
    ) {
        self.ref = ref
        self.title = title
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.tabRef = tabRef
    }
}

private struct AXRef: Hashable {
    let element: AXUIElement
    static func == (lhs: AXRef, rhs: AXRef) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

enum WindowEnumerator {
    /// Brute-force scan range. Long-lived apps (Finder, Mail) and apps that
    /// allocate many AX elements may have window IDs in the hundreds. We run
    /// synchronously per refresh, so cap to keep latency bounded.
    private static let bruteForceLimit: UInt64 = 256

    static func windows(forPid pid: pid_t, isRegularApp: Bool = true) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.2)

        var elements: [AXUIElement] = []
        var seenByElement = Set<AXRef>()
        var seenByWid = Set<CGWindowID>()

        func appendIfNew(_ e: AXUIElement) {
            let ref = AXRef(element: e)
            if seenByElement.contains(ref) { return }
            let wid = PrivateAPI.cgWindowId(of: e)
            if wid != 0 {
                if seenByWid.contains(wid) { return }
                seenByWid.insert(wid)
            }
            seenByElement.insert(ref)
            elements.append(e)
        }

        var windowsValue: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            for w in axWindows { appendIfNew(w) }
        }

        // Brute-force scan only for regular (Dock-visible) apps. Accessory apps
        // (menu-bar utilities like Clop, Bartender) often expose ghost AXWindow
        // refs for popovers that the remote-token API returns even when closed.
        if isRegularApp {
            let acceptedSubroles: Set<String> = [
                kAXStandardWindowSubrole as String,
                kAXDialogSubrole as String,
            ]
            for axId: UInt64 in 0..<bruteForceLimit {
                guard let e = PrivateAPI.axElement(pid: pid, axId: axId) else { continue }
                AXUIElementSetMessagingTimeout(e, 0.05)

                var elemPid: pid_t = 0
                guard AXUIElementGetPid(e, &elemPid) == .success, elemPid == pid else { continue }

                var roleValue: AnyObject?
                AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &roleValue)
                guard (roleValue as? String) == (kAXWindowRole as String) else { continue }

                var subroleValue: AnyObject?
                AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &subroleValue)
                guard let subrole = subroleValue as? String, acceptedSubroles.contains(subrole) else { continue }

                let wid = PrivateAPI.cgWindowId(of: e)
                guard wid != 0 else { continue }

                var sizeValue: AnyObject?
                AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sizeValue)
                if let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
                    var size = CGSize.zero
                    AXValueGetValue(sv as! AXValue, .cgSize, &size)
                    if size.width < 100 || size.height < 100 { continue }
                } else {
                    continue
                }

                appendIfNew(e)
            }
        }

        var infos: [WindowInfo] = []
        infos.reserveCapacity(elements.count)
        var seenTabs = Set<AXRef>()

        let acceptedSubroles: Set<String> = [
            kAXStandardWindowSubrole as String,
            kAXDialogSubrole as String,
        ]
        for window in elements {
            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = (subroleValue as? String) ?? ""
            // Reject popovers, status items, panels, floating UI etc — accept
            // only AXStandardWindow / AXDialog (real Dock-switchable windows).
            // This is what blocks menu-bar utility "Untitled" ghost rows.
            guard acceptedSubroles.contains(subrole) else { continue }

            var minimizedValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            let minimized = (minimizedValue as? Bool) ?? false

            var fullscreenValue: AnyObject?
            AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue)
            let fullscreen = (fullscreenValue as? Bool) ?? false

            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let windowTitle = (titleValue as? String) ?? ""

            var tabsValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTabsAttribute as CFString, &tabsValue)
            var tabs = (tabsValue as? [AXUIElement]) ?? []
            if tabs.count <= 1 {
                tabs = findTabRadioButtons(in: window)
            }

            if tabs.count > 1 {
                let unseen = tabs.filter { !seenTabs.contains(AXRef(element: $0)) }
                if unseen.isEmpty { continue }
                for tab in unseen {
                    seenTabs.insert(AXRef(element: tab))
                    var tabTitleValue: AnyObject?
                    AXUIElementCopyAttributeValue(tab, kAXTitleAttribute as CFString, &tabTitleValue)
                    let tabTitle = (tabTitleValue as? String) ?? ""
                    let resolvedTitle = tabTitle.isEmpty ? windowTitle : tabTitle
                    infos.append(WindowInfo(
                        ref: window,
                        title: resolvedTitle,
                        isMinimized: minimized,
                        isFullscreen: fullscreen,
                        tabRef: tab
                    ))
                }
            } else {
                infos.append(WindowInfo(
                    ref: window,
                    title: windowTitle,
                    isMinimized: minimized,
                    isFullscreen: fullscreen,
                    tabRef: nil
                ))
            }
        }

        return infos
    }

    private static func findTabRadioButtons(in window: AXUIElement) -> [AXUIElement] {
        var childrenValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenValue)
        guard let children = childrenValue as? [AXUIElement] else { return [] }

        for child in children {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            guard (roleValue as? String) == (kAXTabGroupRole as String) else { continue }

            var tabsValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXTabsAttribute as CFString, &tabsValue)
            if let tabs = tabsValue as? [AXUIElement], tabs.count > 1 {
                return tabs
            }

            var tabChildrenValue: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &tabChildrenValue)
            guard let tabChildren = tabChildrenValue as? [AXUIElement] else { return [] }

            var radios: [AXUIElement] = []
            for elem in tabChildren {
                var rv: AnyObject?
                AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &rv)
                if (rv as? String) == "AXRadioButton" {
                    radios.append(elem)
                }
            }
            return radios
        }
        return []
    }
}
