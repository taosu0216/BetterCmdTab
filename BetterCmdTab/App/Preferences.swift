import AppKit
import Combine
import Foundation

enum SwitcherLayoutMode: String, CaseIterable {
    case list
    case gridView = "iconDock"

    var displayName: String {
        switch self {
        case .list: return "List"
        case .gridView: return "Grid View"
        }
    }
}

/// What keeps the switcher open once fuzzy-search has been activated with `/`.
enum SearchDismissMode: String, CaseIterable {
    /// Keep holding the switcher modifier (⌘); releasing it commits the
    /// selection. Matches the non-search behavior. (Default.)
    case holdModifier
    /// After `/`, the switcher stays open even when ⌘ is released, until the
    /// user picks a row with Return or the mouse.
    case stayOpen

    var displayName: String {
        switch self {
        case .holdModifier: return "Hold ⌘"
        case .stayOpen: return "Stay open until I choose"
        }
    }
}

/// Overall size multiplier applied to the switcher panel (icons, text, spacing).
enum PanelSize: String, CaseIterable {
    case small
    case standard
    case large

    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .standard: return 1.0
        case .large: return 1.2
        }
    }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Default"
        case .large: return "Large"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    // Trigger keys are stored by the KeyboardShortcuts library
    // (see KeyboardShortcuts.Name.switchApps / .switchWindows), not here.

    static let defaultRevealDelayMs = 100
    static let revealDelayRange: ClosedRange<Int> = 40...500

    // Internal (not private): `CatalogFilter` reads the catalog-related keys
    // directly from `UserDefaults` off the main actor, so the key strings must
    // be shared rather than duplicated.
    enum Keys {
        static let switcherLayoutMode = "Switcher.layoutMode"
        static let revealDelayMs = "Switcher.revealDelayMs"
        static let panelSize = "Switcher.panelSize"
        static let gridMaxColumns = "Switcher.gridMaxColumns"
        static let excludedBundleIDs = "Switcher.excludedBundleIDs"
        static let pinnedBundleIDs = "Switcher.pinnedBundleIDs"
        static let showMinimizedWindows = "Switcher.showMinimizedWindows"
        static let showHiddenApps = "Switcher.showHiddenApps"
        static let showWindowlessApps = "Switcher.showWindowlessApps"
        static let fuzzySearchEnabled = "Switcher.fuzzySearchEnabled"
        static let searchDismissMode = "Switcher.searchDismissMode"
    }

    @Published var switcherLayoutMode: SwitcherLayoutMode {
        didSet {
            guard oldValue != switcherLayoutMode else { return }
            UserDefaults.standard.set(switcherLayoutMode.rawValue, forKey: Keys.switcherLayoutMode)
        }
    }

    @Published var revealDelayMs: Int {
        didSet {
            let clamped = Self.clampDelay(revealDelayMs)
            if clamped != revealDelayMs {
                revealDelayMs = clamped
                return
            }
            guard oldValue != revealDelayMs else { return }
            UserDefaults.standard.set(revealDelayMs, forKey: Keys.revealDelayMs)
        }
    }

    @Published var panelSize: PanelSize {
        didSet {
            guard oldValue != panelSize else { return }
            UserDefaults.standard.set(panelSize.rawValue, forKey: Keys.panelSize)
        }
    }

    /// Maximum columns in Grid layout. `0` = automatic (width-driven).
    @Published var gridMaxColumns: Int {
        didSet {
            guard oldValue != gridMaxColumns else { return }
            UserDefaults.standard.set(gridMaxColumns, forKey: Keys.gridMaxColumns)
        }
    }

    /// Bundle identifiers of apps hidden from the switcher entirely.
    @Published var excludedBundleIDs: Set<String> {
        didSet {
            guard oldValue != excludedBundleIDs else { return }
            UserDefaults.standard.set(Array(excludedBundleIDs), forKey: Keys.excludedBundleIDs)
        }
    }

    /// Bundle identifiers forced to the front of the switcher. Order is the
    /// pin order (first pinned shows first), independent of MRU.
    @Published var pinnedBundleIDs: [String] {
        didSet {
            guard oldValue != pinnedBundleIDs else { return }
            UserDefaults.standard.set(pinnedBundleIDs, forKey: Keys.pinnedBundleIDs)
        }
    }

    /// Include minimized windows in the switcher. Default `true` (matches the
    /// long-standing behavior of listing them, just sorted lower).
    @Published var showMinimizedWindows: Bool {
        didSet {
            guard oldValue != showMinimizedWindows else { return }
            UserDefaults.standard.set(showMinimizedWindows, forKey: Keys.showMinimizedWindows)
        }
    }

    /// Include hidden apps (Cmd+H) in the switcher. Default `true`.
    @Published var showHiddenApps: Bool {
        didSet {
            guard oldValue != showHiddenApps else { return }
            UserDefaults.standard.set(showHiddenApps, forKey: Keys.showHiddenApps)
        }
    }

    /// Include running apps that have no open windows. Default `true`.
    @Published var showWindowlessApps: Bool {
        didSet {
            guard oldValue != showWindowlessApps else { return }
            UserDefaults.standard.set(showWindowlessApps, forKey: Keys.showWindowlessApps)
        }
    }

    /// Enable the type-to-filter fuzzy search mode (entered with `/`).
    @Published var fuzzySearchEnabled: Bool {
        didSet {
            guard oldValue != fuzzySearchEnabled else { return }
            UserDefaults.standard.set(fuzzySearchEnabled, forKey: Keys.fuzzySearchEnabled)
        }
    }

    /// Whether activating search detaches the switcher from the held modifier.
    @Published var searchDismissMode: SearchDismissMode {
        didSet {
            guard oldValue != searchDismissMode else { return }
            UserDefaults.standard.set(searchDismissMode.rawValue, forKey: Keys.searchDismissMode)
        }
    }

    static func clampDelay(_ value: Int) -> Int {
        min(revealDelayRange.upperBound, max(revealDelayRange.lowerBound, value))
    }

    private init() {
        let defaults = UserDefaults.standard

        let layoutRaw = defaults.string(forKey: Keys.switcherLayoutMode)
        self.switcherLayoutMode = layoutRaw.flatMap(SwitcherLayoutMode.init(rawValue:)) ?? .gridView

        let delay = defaults.object(forKey: Keys.revealDelayMs) as? Int ?? Self.defaultRevealDelayMs
        self.revealDelayMs = Self.clampDelay(delay)

        let sizeRaw = defaults.string(forKey: Keys.panelSize)
        self.panelSize = sizeRaw.flatMap(PanelSize.init(rawValue:)) ?? .standard

        self.gridMaxColumns = defaults.object(forKey: Keys.gridMaxColumns) as? Int ?? 0

        self.excludedBundleIDs = Set(defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? [])
        self.pinnedBundleIDs = defaults.stringArray(forKey: Keys.pinnedBundleIDs) ?? []
        self.showMinimizedWindows = defaults.object(forKey: Keys.showMinimizedWindows) as? Bool ?? true
        self.showHiddenApps = defaults.object(forKey: Keys.showHiddenApps) as? Bool ?? true
        self.showWindowlessApps = defaults.object(forKey: Keys.showWindowlessApps) as? Bool ?? true
        self.fuzzySearchEnabled = defaults.object(forKey: Keys.fuzzySearchEnabled) as? Bool ?? true

        let dismissRaw = defaults.string(forKey: Keys.searchDismissMode)
        self.searchDismissMode = dismissRaw.flatMap(SearchDismissMode.init(rawValue:)) ?? .holdModifier
    }
}
