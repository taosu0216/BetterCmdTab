import Foundation
import Combine

enum SwitcherLayoutMode: String, CaseIterable {
    case list
    case iconDock

    var displayName: String {
        switch self {
        case .list: return "List"
        case .iconDock: return "Icon Dock"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Keys {
        static let switcherLayoutMode = "Switcher.layoutMode"
    }

    @Published var switcherLayoutMode: SwitcherLayoutMode {
        didSet {
            guard oldValue != switcherLayoutMode else { return }
            UserDefaults.standard.set(switcherLayoutMode.rawValue, forKey: Keys.switcherLayoutMode)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.switcherLayoutMode)
        self.switcherLayoutMode = raw.flatMap(SwitcherLayoutMode.init(rawValue:)) ?? .list
    }
}
