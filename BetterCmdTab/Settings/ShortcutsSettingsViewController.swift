import AppKit
import BetterSettings
import BetterShortcuts

@MainActor
final class ShortcutsSettingsViewController: SettingsTabViewController {

    private let appRecorder = BetterShortcuts.RecorderCocoa(for: .switchApps)
    private let windowRecorder = BetterShortcuts.RecorderCocoa(for: .switchWindows)

    // Direct-activation slots: a "choose app" button + shortcut recorder per slot.
    private var directButtons: [NSButton] = []
    private var directSlotSheet: AppsPickerSheetWindowController?

    override func setupContent() {
        // Switching section — the core ⌘Tab triggers. The trigger must include a
        // hold modifier (⌘/⌥/⌃); Shift is reserved for stepping backwards and is
        // rejected by the recorder.
        let switching = addSection(title: "Switching", anchor: SettingsAnchor.switching)
        addRow(
            to: switching,
            title: "Switch apps",
            subtitle: "Hold the modifier (⌘ by default) and tap to move through your open apps.",
            accessory: appRecorder,
            searchItemID: SearchID.switchApps
        )
        addRow(
            to: switching,
            title: "Switch windows",
            subtitle: "Cycle through the windows of the app you're on.",
            accessory: windowRecorder,
            searchItemID: SearchID.switchWindows
        )

        // Direct activation section — global shortcuts that jump straight to a
        // chosen app, bypassing the switcher.
        let direct = addSection(title: "Direct activation", anchor: SettingsAnchor.directActivation)
        addRow(
            to: direct,
            title: "Jump straight to an app",
            subtitle: "Give a shortcut to one app — it focuses that app, opening it first if needed.",
            searchItemID: SearchID.directActivation
        )
        for (index, name) in BetterShortcuts.Name.directActivate.enumerated() {
            let recorder = BetterShortcuts.RecorderCocoa(for: name)
            let button = NSButton(title: "Choose…", target: self, action: #selector(chooseDirectApp(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = index
            let stack = NSStackView(views: [button, recorder])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.alignment = .centerY
            addRow(to: direct, title: "Slot \(index + 1)", accessory: stack)
            directButtons.append(button)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshDirectSlots()
    }

    // MARK: - Direct activation slots

    /// Sync each slot's "choose app" button to its stored bundle ID.
    private func refreshDirectSlots() {
        let bindings = Preferences.shared.directActivationBindings
        for (index, button) in directButtons.enumerated() {
            let bundleID = bindings.indices.contains(index) ? bindings[index] : ""
            if bundleID.isEmpty {
                button.title = "Choose…"
                button.image = nil
            } else {
                button.title = Self.appName(forBundleID: bundleID) ?? bundleID
                button.image = Self.appIcon(forBundleID: bundleID)
                button.imagePosition = .imageLeading
            }
        }
    }

    @objc private func chooseDirectApp(_ sender: NSButton) {
        let slot = sender.tag
        guard let window = view.window, directSlotSheet == nil else { return }
        let current = Preferences.shared.directActivationBindings
        let selected: Set<String> = (current.indices.contains(slot) && !current[slot].isEmpty) ? [current[slot]] : []
        let controller = AppsPickerSheetWindowController(
            title: "Activate App",
            prompt: "Choose the app this shortcut focuses.",
            selectedBundleIDs: selected,
            singleSelection: true
        ) { selection in
            var bindings = Preferences.shared.directActivationBindings
            while bindings.count <= slot { bindings.append("") }
            bindings[slot] = selection.sorted().first ?? ""
            Preferences.shared.directActivationBindings = bindings
        }
        controller.onDidDismiss = { [weak self] in
            self?.directSlotSheet = nil
            self?.refreshDirectSlots()
        }
        directSlotSheet = controller
        controller.present(asSheetFor: window)
    }

    private static func appName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }

    private static func appIcon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
