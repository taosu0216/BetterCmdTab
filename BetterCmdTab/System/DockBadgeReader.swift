import AppKit
import ApplicationServices

/// Reads app badge labels (e.g. Mail's unread count) straight out of the Dock's
/// Accessibility tree. There is no public API for another app's badge, so this
/// walks the Dock process's AX elements and pulls the undocumented
/// `AXStatusLabel` attribute off each dock item. Because the attribute and the
/// Dock tree shape are undocumented they could change between macOS releases, so
/// every read is best-effort: a miss just yields no badge rather than failing.
///
/// The map is recomputed on demand (`snapshot()` at reveal time, throttled via
/// `shouldRefresh()`) and read by the item views via `badge(forBundleID:)`.
/// Gated by the `showUnreadBadges` preference (on by default).
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

    /// Whether enough time has elapsed since the last scan to warrant another.
    /// Back-to-back reveals shouldn't each hammer the Dock's AX server.
    func shouldRefresh() -> Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) >= throttle
    }

    /// Walk the Dock's AX tree and pull badge labels. Undocumented but read-only
    /// AX traffic against another process — safe off the main thread, which is
    /// where the reveal path runs it (each call is timeout-bounded). Pair with
    /// `apply` on the main actor.
    nonisolated static func snapshot() -> [String: String] {
        readDockBadges()
    }

    func apply(_ badges: [String: String]) {
        badgesByBundleID = badges
        lastRefresh = Date()
    }

    nonisolated private static let statusLabelAttribute = "AXStatusLabel"

    nonisolated private static func readDockBadges() -> [String: String] {
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
    nonisolated private static func firstAXList(of element: AXUIElement) -> AXUIElement? {
        for child in children(of: element) {
            if string(child, attribute: kAXRoleAttribute as CFString) == (kAXListRole as String) {
                return child
            }
        }
        return nil
    }

    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    nonisolated private static func string(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
