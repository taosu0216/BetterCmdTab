import AppKit
import Testing
@testable import BetterCmdTab

@Suite("Preferences enums")
struct PreferencesEnumTests {

    @Test("PanelSize scale ordering: small < standard < large")
    func panelSizeOrdering() {
        #expect(PanelSize.small.scale < PanelSize.standard.scale)
        #expect(PanelSize.standard.scale == 1.0)
        #expect(PanelSize.standard.scale < PanelSize.large.scale)
    }

    @MainActor
    @Test("clampDelay keeps values inside the allowed range")
    func clampDelay() {
        #expect(Preferences.clampDelay(10) == Preferences.revealDelayRange.lowerBound)
        #expect(Preferences.clampDelay(9999) == Preferences.revealDelayRange.upperBound)
        #expect(Preferences.clampDelay(150) == 150)
    }
}

@Suite("KeyboardShortcuts integration")
struct KeyboardShortcutsIntegrationTests {

    @MainActor
    @Test("switcher Names default to Command + Tab / Command + backtick")
    func defaultShortcuts() {
        let apps = KeyboardShortcuts.Name.switchApps.defaultShortcut
        #expect(apps?.carbonKeyCode == 48) // Tab
        #expect(apps?.modifiers.contains(.command) == true)

        let windows = KeyboardShortcuts.Name.switchWindows.defaultShortcut
        #expect(windows?.carbonKeyCode == 50) // `
        #expect(windows?.modifiers.contains(.command) == true)
    }

    @MainActor
    @Test("allCases lists exactly the two switcher triggers")
    func allCases() {
        #expect(KeyboardShortcuts.Name.allCases.count == 2)
        #expect(KeyboardShortcuts.Name.allCases.contains(.switchApps))
        #expect(KeyboardShortcuts.Name.allCases.contains(.switchWindows))
    }
}
