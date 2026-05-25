import AppKit
import ApplicationServices

/// Experimental: reads app badge labels (e.g. Mail's unread count) straight out
/// of the Dock's Accessibility tree. There is no public API for another app's
/// badge, so this walks the Dock process's AX elements and pulls the
/// undocumented `AXStatusLabel` attribute off each dock item.
///
/// Still behind an experimental flag because the attribute and the Dock tree
/// shape are undocumented and could change between macOS releases.
///
/// The map is recomputed on demand (`refresh()` at reveal time, throttled) and
/// read by the item views via `badge(forBundleID:)`.
@MainActor
final class DockBadgeReader {
    static let shared = DockBadgeReader()

    /// Bundle identifier → badge label (already non-empty).
    private var badgesByBundleID: [String: String] = [:]
    private var lastRefresh: Date?
    /// Skip rescanning the Dock tree if we did so very recently — back-to-back
    /// reveals shouldn't each hammer the AX server.
    private let throttle: TimeInterval = 1.0

    private init() {}

    func badge(forBundleID bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return badgesByBundleID[bundleID]
    }

    func clear() {
        badgesByBundleID = [:]
        lastRefresh = nil
    }

    func refresh() {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < throttle { return }
        badgesByBundleID = Self.readDockBadges()
        lastRefresh = Date()
    }

    private static let statusLabelAttribute = "AXStatusLabel"

    private static func readDockBadges() -> [String: String] {
        guard let dockPid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier else { return [:] }

        let axDock = AXUIElementCreateApplication(dockPid)
        // Bound any single AX call so a busy Dock can't stall the main thread.
        AXUIElementSetMessagingTimeout(axDock, 0.1)

        guard let list = firstAXList(of: axDock) else { return [:] }
        let items = children(of: list)

        let attributes = [
            kAXSubroleAttribute,
            kAXIsApplicationRunningAttribute,
            kAXURLAttribute,
            statusLabelAttribute,
        ] as CFArray

        var result: [String: String] = [:]
        for item in items {
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, attributes, AXCopyMultipleAttributeOptions(), &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 4 else { continue }

            // Order matches `attributes` above. A failed attribute comes back as
            // an AXValue error wrapper, so the casts below just yield nil.
            guard (values[0] as? String) == (kAXApplicationDockItemSubrole as String) else { continue }
            guard (values[1] as? Bool) == true else { continue }
            guard let badge = values[3] as? String, !badge.isEmpty else { continue }
            guard let url = values[2] as? URL,
                  let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            result[bundleID] = badge
        }
        return result
    }

    /// The Dock app's children include a single `AXList` holding the dock items.
    private static func firstAXList(of element: AXUIElement) -> AXUIElement? {
        for child in children(of: element) {
            if string(child, attribute: kAXRoleAttribute as CFString) == (kAXListRole as String) {
                return child
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private static func string(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
