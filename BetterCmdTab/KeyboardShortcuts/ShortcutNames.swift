import AppKit

// Strongly-typed names for BetterCmdTab's two switcher triggers. The recorded
// shortcuts are stored by the KeyboardShortcuts library but are NOT registered
// as live Carbon hotkeys — no `onKeyDown`/`onKeyUp` handler is attached, so the
// library never steals the combo. The CGEvent tap in `HotkeyTap` remains the
// runtime engine; it reads the stored shortcut and decomposes it into a held
// modifier + tap key (see `SwitcherController.pushHotkeyConfig`).
extension KeyboardShortcuts.Name {
    static let switchApps = Self("switchApps", default: .init(.tab, modifiers: .command))
    static let switchWindows = Self("switchWindows", default: .init(.backtick, modifiers: .command))
}

extension KeyboardShortcuts.Name: CaseIterable {
    public static var allCases: [Self] { [.switchApps, .switchWindows] }

    /// Human-readable label used by the recorder's conflict alert.
    var displayName: String {
        switch self {
        case .switchApps: return "Switch apps"
        case .switchWindows: return "Switch windows"
        default: return rawValue
        }
    }
}
