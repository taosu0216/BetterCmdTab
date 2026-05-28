import AppKit
import BetterSettings
import BetterUpdater
import Combine

@MainActor
final class GeneralSettingsViewController: SettingsTabViewController {

    private let launchSwitch = NSSwitch()
    private let hideMenuBarSwitch = NSSwitch()
    private let hapticSwitch = NSSwitch()
    private let soundSwitch = NSSwitch()
    private let betaSwitch = NSSwitch()
    private let intervalPopUp = NSPopUpButton(frame: .zero, pullsDown: false)

    private var cancellables = Set<AnyCancellable>()

    override func setupContent() {
        // Startup section
        let startup = addSection(title: "Startup", anchor: SettingsAnchor.startup)
        launchSwitch.controlSize = .small
        launchSwitch.target = self
        launchSwitch.action = #selector(toggleLaunchAtLogin(_:))
        addRow(
            to: startup,
            title: "Launch at login",
            subtitle: "Open BetterCmdTab automatically when you log in.",
            accessory: launchSwitch,
            searchItemID: SearchID.launchAtLogin
        )

        configureSwitch(hideMenuBarSwitch, action: #selector(toggleHideMenuBarIcon(_:)))
        addRow(
            to: startup,
            title: "Hide menu bar icon",
            subtitle: "Hide the ⌘ icon. Reopen this window from Spotlight.",
            accessory: hideMenuBarSwitch,
            searchItemID: SearchID.hideMenuBar
        )

        // Feedback section — confirmation cues on commit.
        let feedback = addSection(title: "Feedback", anchor: SettingsAnchor.feedback)
        configureSwitch(hapticSwitch, action: #selector(toggleHaptic(_:)))
        addRow(
            to: feedback,
            title: "Haptic feedback on switch",
            subtitle: "A tap when you pick an app. Force Touch trackpads only.",
            accessory: hapticSwitch,
            searchItemID: SearchID.haptic
        )
        configureSwitch(soundSwitch, action: #selector(toggleSound(_:)))
        addRow(
            to: feedback,
            title: "Sound on switch",
            subtitle: "A soft click when you pick an app.",
            accessory: soundSwitch,
            searchItemID: SearchID.sound
        )

        // Updates section
        let updates = addSection(title: "Updates", anchor: SettingsAnchor.updates)

        for cadence in UpdateCheckInterval.selectableCadences {
            intervalPopUp.addItem(withTitle: cadence.title)
        }
        intervalPopUp.controlSize = .small
        intervalPopUp.target = self
        intervalPopUp.action = #selector(changeInterval(_:))
        addRow(
            to: updates,
            title: "Check for updates",
            subtitle: "How often to check automatically. The beta channel always checks hourly.",
            accessory: intervalPopUp,
            searchItemID: SearchID.updateInterval
        )

        betaSwitch.controlSize = .small
        betaSwitch.target = self
        betaSwitch.action = #selector(toggleBeta(_:))
        addRow(
            to: updates,
            title: "Include beta releases",
            subtitle: "Get pre-release builds early. They may be unstable.",
            accessory: betaSwitch,
            searchItemID: SearchID.beta
        )
    }

    private func configureSwitch(_ toggle: NSSwitch, action: Selector) {
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = action
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        LaunchAtLogin.shared.refresh()
        applyLaunchState(LaunchAtLogin.shared.isEnabled)

        let prefs = Preferences.shared
        hideMenuBarSwitch.state = prefs.hideMenuBarIcon ? .on : .off
        hapticSwitch.state = prefs.hapticOnCommit ? .on : .off
        soundSwitch.state = prefs.soundOnCommit ? .on : .off

        let updater = GitHubUpdater.shared
        betaSwitch.state = updater.includePreReleases ? .on : .off

        let cadences = UpdateCheckInterval.selectableCadences
        intervalPopUp.selectItem(at: cadences.firstIndex(of: updater.checkInterval) ?? 0)

        LaunchAtLogin.shared.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyLaunchState($0) }
            .store(in: &cancellables)

        updater.$includePreReleases
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.betaSwitch.state = $0 ? .on : .off }
            .store(in: &cancellables)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
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

    @objc private func changeInterval(_ sender: NSPopUpButton) {
        let cadences = UpdateCheckInterval.selectableCadences
        let idx = sender.indexOfSelectedItem
        guard cadences.indices.contains(idx) else { return }
        GitHubUpdater.shared.setCheckInterval(cadences[idx])
    }

    @objc private func toggleHideMenuBarIcon(_ sender: NSSwitch) {
        Preferences.shared.hideMenuBarIcon = (sender.state == .on)
    }

    @objc private func toggleHaptic(_ sender: NSSwitch) {
        Preferences.shared.hapticOnCommit = (sender.state == .on)
    }

    @objc private func toggleSound(_ sender: NSSwitch) {
        Preferences.shared.soundOnCommit = (sender.state == .on)
    }
}
