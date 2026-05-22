import AppKit
import ApplicationServices

struct WindowInfo {
    let ref: AXUIElement
    let title: String
    let isMinimized: Bool
    let tabRef: AXUIElement?

    init(ref: AXUIElement, title: String, isMinimized: Bool, tabRef: AXUIElement? = nil) {
        self.ref = ref
        self.title = title
        self.isMinimized = isMinimized
        self.tabRef = tabRef
    }
}

private struct AXRef: Hashable {
    let element: AXUIElement
    static func == (lhs: AXRef, rhs: AXRef) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

enum WindowEnumerator {
    static func windows(forPid pid: pid_t) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.2)

        var windowsValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let axWindows = windowsValue as? [AXUIElement] else {
            return []
        }

        var infos: [WindowInfo] = []
        infos.reserveCapacity(axWindows.count)
        var seenTabs = Set<AXRef>()

        for window in axWindows {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
            let role = (roleValue as? String) ?? ""
            if !role.isEmpty && role != kAXWindowRole {
                continue
            }

            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = (subroleValue as? String) ?? ""

            let skippedSubroles: Set<String> = [
                kAXSystemDialogSubrole,
                kAXSystemFloatingWindowSubrole,
            ]
            if skippedSubroles.contains(subrole) {
                continue
            }

            var minimizedValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            let minimized = (minimizedValue as? Bool) ?? false

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
                if unseen.isEmpty {
                    continue
                }
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
                        tabRef: tab
                    ))
                }
            } else {
                infos.append(WindowInfo(
                    ref: window,
                    title: windowTitle,
                    isMinimized: minimized,
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
