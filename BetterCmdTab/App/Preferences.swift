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

    private enum Keys {
        static let switcherLayoutMode = "Switcher.layoutMode"
        static let revealDelayMs = "Switcher.revealDelayMs"
        static let panelSize = "Switcher.panelSize"
        static let gridMaxColumns = "Switcher.gridMaxColumns"
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
    }
}
