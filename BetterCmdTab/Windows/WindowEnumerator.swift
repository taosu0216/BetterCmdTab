import AppKit
import ApplicationServices
import CoreGraphics

struct WindowInfo {
    let ref: AXUIElement
    let title: String
    let isMinimized: Bool
    let isFullscreen: Bool

    init(
        ref: AXUIElement,
        title: String,
        isMinimized: Bool,
        isFullscreen: Bool = false
    ) {
        self.ref = ref
        self.title = title
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
    }
}

private struct AXRef: Hashable {
    let element: AXUIElement
    static func == (lhs: AXRef, rhs: AXRef) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

/// Per-pid window inventory captured from `CGWindowListCopyWindowInfo`.
/// `ids` is the membership set used to confirm AX scan coverage; `zOrder`
/// preserves the front-to-back ordering returned by WindowServer so we can
/// surface windows in the switcher in the same order the user sees them
/// stacked on screen instead of whatever arbitrary order AX returns.
struct CGWindowSnapshot {
    let ids: [pid_t: Set<CGWindowID>]
    let zOrder: [pid_t: [CGWindowID]]

    static let empty = CGWindowSnapshot(ids: [:], zOrder: [:])

    func ids(for pid: pid_t) -> Set<CGWindowID> { ids[pid] ?? [] }
    func zOrder(for pid: pid_t) -> [CGWindowID] { zOrder[pid] ?? [] }
}

enum WindowEnumerator {
    /// 1024 covers fullscreen windows that get allocated late in the AX
    /// element id space. With CG hint + early-exit the scan typically stops
    /// well before this cap.
    private static let bruteForceLimit: UInt64 = 1024
    private static let preFilterTimeout: Float = 0.025
    private static let confirmedTimeout: Float = 0.2

    /// Snapshot of every window grouped by owner pid via the public
    /// `CGWindowListCopyWindowInfo` API. Uses `.optionAll` (not
    /// `.optionOnScreenOnly`) so fullscreen windows living on their own
    /// Spaces are included — they're invisible from the current Space and
    /// would otherwise drop out of the hint set, causing the brute scan to
    /// miss them entirely.
    ///
    /// The returned snapshot preserves WindowServer z-order per pid so
    /// callers can sort their AX results by what the user actually sees,
    /// rather than the arbitrary order `kAXWindowsAttribute` exposes.
    static func snapshotCGWindowMap() -> CGWindowSnapshot {
        let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let cfArray = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return .empty
        }
        var ids: [pid_t: Set<CGWindowID>] = [:]
        var zOrder: [pid_t: [CGWindowID]] = [:]
        for entry in cfArray {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
            if layer != 0 { continue }
            let alpha = (entry[kCGWindowAlpha as String] as? Double) ?? 1.0
            if alpha <= 0 { continue }
            guard let widNum = entry[kCGWindowNumber as String] as? Int else { continue }
            let wid = CGWindowID(widNum)
            if let bounds = entry[kCGWindowBounds as String] as? [String: Any] {
                let w = (bounds["Width"] as? Double) ?? 0
                let h = (bounds["Height"] as? Double) ?? 0
                if w < 100 || h < 100 { continue }
            }
            if ids[ownerPID, default: []].insert(wid).inserted {
                zOrder[ownerPID, default: []].append(wid)
            }
        }
        return CGWindowSnapshot(ids: ids, zOrder: zOrder)
    }

    static func windows(
        forPid pid: pid_t,
        isRegularApp: Bool = true,
        expectedCGWindowIDs: Set<CGWindowID> = [],
        cgZOrder: [CGWindowID] = []
    ) -> [WindowInfo] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, Self.confirmedTimeout)

        var elements: [AXUIElement] = []
        var seenByElement = Set<AXRef>()
        var seenByWid = Set<CGWindowID>()

        func appendIfNew(_ e: AXUIElement) {
            let ref = AXRef(element: e)
            if seenByElement.contains(ref) { return }
            let wid = PrivateAPI.cgWindowId(of: e)
            // Drop AX elements without a WindowServer id. Two cases produce
            // this and neither belongs in the switcher: (1) a window mid-
            // destruction — after `kAXCloseAction` / pressing the close
            // button, `kAXWindowsAttribute` still lists the dying element
            // for ~100–300ms while `_AXUIElementGetWindow` already returns 0.
            // Letting these through caused the just-closed row to flash back
            // on the next cache refresh. (2) Pre-registered windows that have
            // not yet been promoted to a real CG window — also not user-
            // actionable. The brute-force scan already enforced this; the
            // AX-windows-list path silently didn't, which is the asymmetry
            // that allowed the flicker. Keep both paths consistent.
            guard wid != 0 else { return }
            if seenByWid.contains(wid) { return }
            seenByWid.insert(wid)
            seenByElement.insert(ref)
            elements.append(e)
        }

        var windowsValue: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            for w in axWindows { appendIfNew(w) }
        }

        // Skip brute-force AX scan when the CG window list says AX already has
        // every on-screen window covered. Apps with no CG-AX gap (the common
        // case) pay zero brute-scan cost.
        let needBruteScan: Bool
        if expectedCGWindowIDs.isEmpty {
            needBruteScan = isRegularApp
        } else {
            needBruteScan = isRegularApp && !expectedCGWindowIDs.isSubset(of: seenByWid)
        }

        if needBruteScan {
            let acceptedSubroles: Set<String> = [
                kAXStandardWindowSubrole as String,
                kAXDialogSubrole as String,
            ]
            for axId: UInt64 in 0..<bruteForceLimit {
                // Early exit once CG hint fully covered.
                if !expectedCGWindowIDs.isEmpty, expectedCGWindowIDs.isSubset(of: seenByWid) {
                    break
                }
                guard let e = PrivateAPI.axElement(pid: pid, axId: axId) else { continue }
                AXUIElementSetMessagingTimeout(e, Self.preFilterTimeout)

                var elemPid: pid_t = 0
                guard AXUIElementGetPid(e, &elemPid) == .success, elemPid == pid else { continue }

                var roleValue: AnyObject?
                AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &roleValue)
                guard (roleValue as? String) == (kAXWindowRole as String) else { continue }

                AXUIElementSetMessagingTimeout(e, Self.confirmedTimeout)

                var subroleValue: AnyObject?
                AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &subroleValue)
                guard let subrole = subroleValue as? String, acceptedSubroles.contains(subrole) else { continue }

                let wid = PrivateAPI.cgWindowId(of: e)
                guard wid != 0 else { continue }

                if !expectedCGWindowIDs.isEmpty {
                    // CG hint mode: only accept windows the CG list confirmed.
                    if !expectedCGWindowIDs.contains(wid) { continue }
                } else {
                    // Legacy size filter when no CG hint available.
                    var sizeValue: AnyObject?
                    AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sizeValue)
                    if let sv = sizeValue, CFGetTypeID(sv) == AXValueGetTypeID() {
                        var size = CGSize.zero
                        AXValueGetValue(sv as! AXValue, .cgSize, &size)
                        if size.width < 100 || size.height < 100 { continue }
                    } else {
                        continue
                    }
                }

                appendIfNew(e)
            }
        }

        var infos: [WindowInfo] = []
        infos.reserveCapacity(elements.count)

        let acceptedSubroles: Set<String> = [
            kAXStandardWindowSubrole as String,
            kAXDialogSubrole as String,
        ]
        var seenTabGroups: Set<[AXRef]> = []
        for window in elements {
            AXUIElementSetMessagingTimeout(window, Self.confirmedTimeout)
            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = (subroleValue as? String) ?? ""
            guard acceptedSubroles.contains(subrole) else { continue }

            var tabsValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTabsAttribute as CFString, &tabsValue)
            if let tabs = tabsValue as? [AXUIElement], tabs.count > 1 {
                let key = tabs.map { AXRef(element: $0) }
                if seenTabGroups.contains(key) { continue }
                seenTabGroups.insert(key)
            }

            var minimizedValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            let minimized = (minimizedValue as? Bool) ?? false

            var fullscreenValue: AnyObject?
            AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreenValue)
            let fullscreen = (fullscreenValue as? Bool) ?? false

            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let windowTitle = (titleValue as? String) ?? ""

            infos.append(WindowInfo(
                ref: window,
                title: windowTitle,
                isMinimized: minimized,
                isFullscreen: fullscreen
            ))
        }

        return sortedByZOrder(infos, cgZOrder: cgZOrder)
    }

    /// Re-orders the AX-derived window list to match the WindowServer
    /// z-order returned by `CGWindowListCopyWindowInfo` (front-to-back).
    /// Windows missing a CG id, or absent from the snapshot (e.g. on a
    /// hidden Space when CG omits them) keep their original AX-relative
    /// order at the tail — that's the same fallback behavior as before
    /// the z-order pass, just applied to a smaller subset.
    private static func sortedByZOrder(_ infos: [WindowInfo], cgZOrder: [CGWindowID]) -> [WindowInfo] {
        guard !cgZOrder.isEmpty, infos.count > 1 else { return infos }
        var rank: [CGWindowID: Int] = [:]
        rank.reserveCapacity(cgZOrder.count)
        for (i, wid) in cgZOrder.enumerated() { rank[wid] = i }

        let indexed = infos.enumerated().map { (offset, info) -> (rank: Int, fallback: Int, info: WindowInfo) in
            let wid = PrivateAPI.cgWindowId(of: info.ref)
            let r = (wid != 0 ? rank[wid] : nil) ?? Int.max
            return (r, offset, info)
        }
        return indexed.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.fallback < rhs.fallback
        }.map { $0.info }
    }
}
