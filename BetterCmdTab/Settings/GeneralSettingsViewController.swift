import AppKit
import Combine

@MainActor
final class GeneralSettingsViewController: NSViewController {

    private let launchSwitch = NSSwitch()
    private let accessibilityRow = SettingsRowView(
        title: "Accessibility access",
        description: "Required to intercept the switcher shortcut and read your open windows."
    )
    private let permissionIcon = NSImageView()
    private let permissionButton = NSButton(title: "", target: nil, action: nil)

    private let betaSwitch = NSSwitch()
    private let appRecorder = KeyboardShortcuts.RecorderCocoa(for: .switchApps)
    private let windowRecorder = KeyboardShortcuts.RecorderCocoa(for: .switchWindows)

    private let minimizedSwitch = NSSwitch()
    private let hiddenSwitch = NSSwitch()
    private let windowlessSwitch = NSSwitch()
    private let fuzzySwitch = NSSwitch()
    private let searchModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let searchDismissModes: [SearchDismissMode] = SearchDismissMode.allCases
    private let excludedButton = NSButton(title: "Manage apps", target: nil, action: nil)
    private let pinnedButton = NSButton(title: "Manage apps", target: nil, action: nil)
    private let excludedRow = SettingsRowView(
        title: "Excluded apps",
        description: "Hidden from the switcher entirely."
    )
    private let pinnedRow = SettingsRowView(
        title: "Pinned apps",
        description: "Forced to the front of the switcher, before recents."
    )
    private var appsSheet: AppsPickerSheetWindowController?

    private var cancellables = Set<AnyCancellable>()
    private var axTimer: Timer?

    override func loadView() {
        // Behavior section
        let behavior = SettingsSectionView(header: "Behavior")
        let launchRow = SettingsRowView(title: "Launch at login", accessory: launchSwitch)
        launchSwitch.controlSize = .small
        launchSwitch.target = self
        launchSwitch.action = #selector(toggleLaunchAtLogin(_:))
        behavior.addContent(launchRow)

        // Shortcut section — native KeyboardShortcuts recorders. The trigger must
        // include a hold modifier (Command/Option/Control); Shift is reserved for
        // reverse-direction stepping and is rejected by the recorder.
        let shortcut = SettingsSectionView(header: "Shortcut")
        shortcut.addContent(SettingsRowView(title: "Switch apps", accessory: appRecorder))
        shortcut.addContent(SettingsRowView(title: "Switch windows", accessory: windowRecorder))

        // Switcher contents section — what kinds of windows/apps appear.
        let contents = SettingsSectionView(header: "Switcher Contents")
        configureSwitch(minimizedSwitch, action: #selector(toggleMinimized(_:)))
        contents.addContent(SettingsRowView(
            title: "Show minimized windows",
            accessory: minimizedSwitch
        ))
        configureSwitch(hiddenSwitch, action: #selector(toggleHidden(_:)))
        contents.addContent(SettingsRowView(
            title: "Show hidden apps",
            accessory: hiddenSwitch
        ))
        configureSwitch(windowlessSwitch, action: #selector(toggleWindowless(_:)))
        contents.addContent(SettingsRowView(
            title: "Show apps without windows",
            subtitle: "Running apps that have no open windows.",
            accessory: windowlessSwitch
        ))
        configureSwitch(fuzzySwitch, action: #selector(toggleFuzzy(_:)))
        contents.addContent(SettingsRowView(
            title: "Type-to-filter search",
            subtitle: "Press / while the switcher is open to filter by app name or window title.",
            accessory: fuzzySwitch
        ))

        searchModePopup.controlSize = .small
        searchModePopup.translatesAutoresizingMaskIntoConstraints = false
        searchModePopup.setContentHuggingPriority(.required, for: .horizontal)
        searchModePopup.removeAllItems()
        searchModePopup.addItems(withTitles: searchDismissModes.map(\.displayName))
        searchModePopup.target = self
        searchModePopup.action = #selector(searchModeChanged)
        contents.addContent(SettingsRowView(
            title: "When searching",
            subtitle: "“Hold ⌘” keeps the current behavior; “Stay open” lets you release ⌘ after / and pick with Return or the mouse.",
            accessory: searchModePopup
        ))

        // App lists section — exclusion and pinning, each via a picker sheet.
        let appLists = SettingsSectionView(header: "Apps")
        configureManageButton(excludedButton, action: #selector(manageExcluded))
        excludedRow.setAccessory(excludedButton)
        appLists.addContent(excludedRow)
        configureManageButton(pinnedButton, action: #selector(managePinned))
        pinnedRow.setAccessory(pinnedButton)
        appLists.addContent(pinnedRow)

        // Permissions section
        let permissions = SettingsSectionView(header: "Permissions")

        permissionIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        permissionIcon.translatesAutoresizingMaskIntoConstraints = false
        permissionIcon.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            permissionIcon.widthAnchor.constraint(equalToConstant: 16),
            permissionIcon.heightAnchor.constraint(equalToConstant: 16),
        ])

        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .small
        permissionButton.target = self
        permissionButton.action = #selector(openSystemSettings)

        let permissionAccessory = NSStackView()
        permissionAccessory.orientation = .horizontal
        permissionAccessory.spacing = 8
        permissionAccessory.alignment = .centerY
        permissionAccessory.addArrangedSubview(permissionIcon)
        permissionAccessory.addArrangedSubview(permissionButton)

        accessibilityRow.setAccessory(permissionAccessory)
        permissions.addContent(accessibilityRow)

        // Update Channel section
        let updates = SettingsSectionView(header: "Update Channel")
        let betaRow = SettingsRowView(
            title: "Include beta releases",
            description: "Beta builds may be unstable.",
            accessory: betaSwitch
        )
        betaSwitch.controlSize = .small
        betaSwitch.target = self
        betaSwitch.action = #selector(toggleBeta(_:))
        updates.addContent(betaRow)

        view = SettingsLayout.makeScrollingTab(sections: [behavior, shortcut, contents, appLists, permissions, updates])
    }

    private func configureSwitch(_ toggle: NSSwitch, action: Selector) {
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = action
    }

    private func configureManageButton(_ button: NSButton, action: Selector) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        LaunchAtLogin.shared.refresh()
        applyLaunchState(LaunchAtLogin.shared.isEnabled)
        refreshAccessibilityStatus()

        let prefs = Preferences.shared
        minimizedSwitch.state = prefs.showMinimizedWindows ? .on : .off
        hiddenSwitch.state = prefs.showHiddenApps ? .on : .off
        windowlessSwitch.state = prefs.showWindowlessApps ? .on : .off
        fuzzySwitch.state = prefs.fuzzySearchEnabled ? .on : .off
        selectSearchMode(prefs.searchDismissMode)
        updateAppListCounts()

        prefs.$searchDismissMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectSearchMode($0) }
            .store(in: &cancellables)

        prefs.$excludedBundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.excludedRow.rowDescription = Self.countDescription($0.count, suffix: "hidden from the switcher entirely.") }
            .store(in: &cancellables)
        prefs.$pinnedBundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.pinnedRow.rowDescription = Self.countDescription($0.count, suffix: "forced to the front of the switcher.") }
            .store(in: &cancellables)

        let updater = GitHubUpdater.shared
        betaSwitch.state = updater.includePreReleases ? .on : .off

        LaunchAtLogin.shared.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyLaunchState($0) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshAccessibilityStatus() }
            .store(in: &cancellables)

        updater.$includePreReleases
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.betaSwitch.state = $0 ? .on : .off }
            .store(in: &cancellables)

        startAccessibilityPolling()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopAccessibilityPolling()
        cancellables.removeAll()
    }

    private func applyLaunchState(_ enabled: Bool) {
        let target: NSControl.StateValue = enabled ? .on : .off
        if launchSwitch.state != target { launchSwitch.state = target }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSSwitch) {
        LaunchAtLogin.shared.setEnabled(sender.state == .on)
    }

    @objc private func toggleBeta(_ sender: NSSwitch) {
        GitHubUpdater.shared.includePreReleases = (sender.state == .on)
    }

    @objc private func toggleMinimized(_ sender: NSSwitch) {
        Preferences.shared.showMinimizedWindows = (sender.state == .on)
    }

    @objc private func toggleHidden(_ sender: NSSwitch) {
        Preferences.shared.showHiddenApps = (sender.state == .on)
    }

    @objc private func toggleWindowless(_ sender: NSSwitch) {
        Preferences.shared.showWindowlessApps = (sender.state == .on)
    }

    @objc private func toggleFuzzy(_ sender: NSSwitch) {
        Preferences.shared.fuzzySearchEnabled = (sender.state == .on)
    }

    @objc private func searchModeChanged() {
        let idx = searchModePopup.indexOfSelectedItem
        guard searchDismissModes.indices.contains(idx) else { return }
        Preferences.shared.searchDismissMode = searchDismissModes[idx]
    }

    private func selectSearchMode(_ mode: SearchDismissMode) {
        if let i = searchDismissModes.firstIndex(of: mode) { searchModePopup.selectItem(at: i) }
    }

    @objc private func manageExcluded() {
        presentAppsSheet(
            title: "Excluded Apps",
            prompt: "Selected apps are hidden from the switcher entirely.",
            selected: Preferences.shared.excludedBundleIDs
        ) { selection in
            Preferences.shared.excludedBundleIDs = selection
        }
    }

    @objc private func managePinned() {
        presentAppsSheet(
            title: "Pinned Apps",
            prompt: "Selected apps are forced to the front of the switcher, before recents.",
            selected: Set(Preferences.shared.pinnedBundleIDs)
        ) { selection in
            // Preserve existing pin order; append newly-checked apps at the end.
            let current = Preferences.shared.pinnedBundleIDs
            var order = current.filter { selection.contains($0) }
            for bid in selection where !order.contains(bid) { order.append(bid) }
            Preferences.shared.pinnedBundleIDs = order
        }
    }

    private func presentAppsSheet(
        title: String,
        prompt: String,
        selected: Set<String>,
        onDone: @escaping (Set<String>) -> Void
    ) {
        guard let window = view.window, appsSheet == nil else { return }
        let controller = AppsPickerSheetWindowController(
            title: title,
            prompt: prompt,
            selectedBundleIDs: selected,
            onDone: onDone
        )
        controller.onDidDismiss = { [weak self] in
            self?.appsSheet = nil
            self?.updateAppListCounts()
        }
        appsSheet = controller
        controller.present(asSheetFor: window)
    }

    private func updateAppListCounts() {
        let prefs = Preferences.shared
        excludedRow.rowDescription = Self.countDescription(prefs.excludedBundleIDs.count, suffix: "hidden from the switcher entirely.")
        pinnedRow.rowDescription = Self.countDescription(prefs.pinnedBundleIDs.count, suffix: "forced to the front of the switcher.")
    }

    private static func countDescription(_ count: Int, suffix: String) -> String {
        let prefix = count == 0 ? "None" : "\(count) app\(count == 1 ? "" : "s")"
        return "\(prefix) — \(suffix)"
    }

    @objc private func openSystemSettings() {
        AccessibilityCheck.promptIfNeeded()
        AccessibilityCheck.openSystemSettings()
    }

    private func refreshAccessibilityStatus() {
        if AccessibilityCheck.isTrusted {
            permissionIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Granted")
            permissionIcon.contentTintColor = .systemGreen
            permissionButton.title = "Open Settings"
        } else {
            permissionIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Required")
            permissionIcon.contentTintColor = .systemOrange
            permissionButton.title = "Grant Access"
        }
    }

    private func startAccessibilityPolling() {
        axTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAccessibilityStatus() }
        }
        RunLoop.main.add(timer, forMode: .common)
        axTimer = timer
    }

    private func stopAccessibilityPolling() {
        axTimer?.invalidate()
        axTimer = nil
    }
}
