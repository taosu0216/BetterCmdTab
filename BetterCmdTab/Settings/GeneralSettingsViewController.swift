import AppKit
import Combine

@MainActor
final class GeneralSettingsViewController: NSViewController {

    private let launchSwitch = NSSwitch()
    private let accessibilityRow = SettingsRowView(title: "Accessibility access")
    private let permissionIcon = NSImageView()
    private let permissionButton = NSButton(title: "", target: nil, action: nil)

    private let betaSwitch = NSSwitch()
    private let layoutModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)

    private var cancellables = Set<AnyCancellable>()
    private var axTimer: Timer?

    override func loadView() {
        // Behavior section
        let behavior = SettingsSectionView(header: "Behavior")
        let launchRow = SettingsRowView(
            title: "Launch at login",
            accessory: launchSwitch
        )
        launchSwitch.controlSize = .small
        launchSwitch.target = self
        launchSwitch.action = #selector(toggleLaunchAtLogin(_:))
        behavior.addContent(launchRow)

        // Appearance section
        let appearance = SettingsSectionView(header: "Appearance")
        layoutModePopUp.controlSize = .small
        layoutModePopUp.bezelStyle = .rounded
        layoutModePopUp.target = self
        layoutModePopUp.action = #selector(changeLayoutMode(_:))
        layoutModePopUp.removeAllItems()
        for mode in SwitcherLayoutMode.allCases {
            layoutModePopUp.addItem(withTitle: mode.displayName)
            if let item = layoutModePopUp.lastItem {
                item.representedObject = mode.rawValue
            }
        }
        let layoutRow = SettingsRowView(
            title: "Switcher layout",
            accessory: layoutModePopUp
        )
        appearance.addContent(layoutRow)

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
            accessory: betaSwitch
        )
        betaSwitch.controlSize = .small
        betaSwitch.target = self
        betaSwitch.action = #selector(toggleBeta(_:))
        updates.addContent(betaRow)

        view = SettingsLayout.makeScrollingTab(sections: [behavior, appearance, permissions, updates])
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        LaunchAtLogin.shared.refresh()
        applyLaunchState(LaunchAtLogin.shared.isEnabled)
        refreshAccessibilityStatus()

        let updater = GitHubUpdater.shared
        betaSwitch.state = updater.includePreReleases ? .on : .off

        applyLayoutMode(Preferences.shared.switcherLayoutMode)

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

        Preferences.shared.$switcherLayoutMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyLayoutMode($0) }
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

    @objc private func changeLayoutMode(_ sender: NSPopUpButton) {
        guard
            let raw = sender.selectedItem?.representedObject as? String,
            let mode = SwitcherLayoutMode(rawValue: raw)
        else { return }
        Preferences.shared.switcherLayoutMode = mode
    }

    private func applyLayoutMode(_ mode: SwitcherLayoutMode) {
        let targetIndex = layoutModePopUp.itemArray.firstIndex { item in
            (item.representedObject as? String) == mode.rawValue
        } ?? 0
        if layoutModePopUp.indexOfSelectedItem != targetIndex {
            layoutModePopUp.selectItem(at: targetIndex)
        }
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
