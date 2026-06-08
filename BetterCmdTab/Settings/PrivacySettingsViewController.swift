import AppKit
import BetterPermissions
import BetterSettings

@MainActor
final class PrivacySettingsViewController: SettingsTabViewController {

    private let hideFromScreenSharingSwitch = NSSwitch()

    private let permissionIcon = NSImageView()
    private let permissionButton = NSButton(title: "", target: nil, action: nil)

    private let restoreShortcutsButton = NSButton(title: "", target: nil, action: nil)

    private var observationTask: Task<Void, Never>?

    override func setupContent() {
        // Screen-sharing section — hide the switcher panel from screen recording
        // / sharing capture (Zoom, Meet, Teams, QuickTime, ScreenCaptureKit).
        let sharing = addSection(title: String(localized: "Screen sharing"), anchor: SettingsAnchor.screenSharing)
        configureSwitch(hideFromScreenSharingSwitch, action: #selector(toggleHideFromScreenSharing(_:)))
        addRow(
            to: sharing,
            title: String(localized: "Don't look at my windows"),
            subtitle: String(localized: "Hide the switcher from screen recordings and shared screens (Zoom, Meet, Teams). Needs macOS 14.6 or later."),
            accessory: hideFromScreenSharingSwitch,
            searchItemID: SearchID.hideFromScreenSharing
        )

        // Permissions section.
        let permissions = addSection(title: String(localized: "Permissions"), anchor: SettingsAnchor.permissions)

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
        permissionButton.action = #selector(grantAccess)

        let permissionAccessory = NSStackView()
        permissionAccessory.orientation = .horizontal
        permissionAccessory.spacing = 8
        permissionAccessory.alignment = .centerY
        permissionAccessory.addArrangedSubview(permissionIcon)
        permissionAccessory.addArrangedSubview(permissionButton)

        addRow(
            to: permissions,
            title: String(localized: "Accessibility access"),
            subtitle: String(localized: "Lets BetterCmdTab capture the shortcut and read your open windows. Required to work."),
            accessory: permissionAccessory,
            searchItemID: SearchID.accessibility
        )

        // Recovery section — manual escape hatch if the native ⌘Tab is stuck.
        // BetterCmdTab disables the system's ⌘Tab so it can take over under
        // Secure Event Input; that disable lives in the WindowServer and
        // outlives the process, so an unclean exit (crash, Force Quit) can leave
        // macOS's own ⌘Tab dead. This button re-enables every native chord, then
        // the live trigger re-disables only what it currently needs.
        let recovery = addSection(title: String(localized: "Recovery"), anchor: SettingsAnchor.recovery)

        restoreShortcutsButton.bezelStyle = .rounded
        restoreShortcutsButton.controlSize = .small
        restoreShortcutsButton.title = String(localized: "Restore")
        restoreShortcutsButton.target = self
        restoreShortcutsButton.action = #selector(restoreNativeShortcuts)

        addRow(
            to: recovery,
            title: String(localized: "Restore macOS keyboard shortcuts"),
            subtitle: String(localized: "Re-enable the system's ⌘Tab and ⌘` — for example if they got stuck off after a crash. BetterCmdTab hands them back to macOS until you next relaunch it."),
            accessory: restoreShortcutsButton,
            searchItemID: SearchID.restoreShortcuts
        )
    }

    private func configureSwitch(_ toggle: NSSwitch, action: Selector) {
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = action
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        hideFromScreenSharingSwitch.state = Preferences.shared.hideFromScreenSharing ? .on : .off

        // Reactive accessibility status via BetterPermissions: yields the current value
        // immediately, then every change (TCC notification / app activation / adaptive
        // poll), replacing the hand-rolled 1 Hz timer + didBecomeActive observer. The
        // engine disarms when this task is cancelled on disappear / memory release.
        observationTask?.cancel() // never leak a second armed observation
        observationTask = Task { @MainActor [weak self] in
            for await snapshot in BetterPermissions.changes(.accessibility) {
                self?.refreshAccessibilityStatus(isUsable: snapshot.status.isUsable)
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        observationTask?.cancel()
        observationTask = nil
    }

    // BetterSettings can tear down the active tab (window close / memory eviction)
    // without a matching viewWillDisappear, which would orphan the observation Task and
    // leave the BetterPermissions accessibility detector armed for the process lifetime.
    override func prepareForMemoryRelease() {
        observationTask?.cancel()
        observationTask = nil
        super.prepareForMemoryRelease()
    }

    @objc private func toggleHideFromScreenSharing(_ sender: NSSwitch) {
        Preferences.shared.hideFromScreenSharing = (sender.state == .on)
    }

    @objc private func grantAccess() {
        Task { @MainActor in
            let outcome = await BetterPermissions.request(.accessibility)
            if outcome.needsSettings { BetterPermissions.openSettings(for: .accessibility) }
        }
    }

    @objc private func restoreNativeShortcuts() {
        // Hand off to the live SwitcherController (it owns the symbolic-hotkey
        // state and the Carbon fallback), which re-enables every native chord and
        // then re-syncs the override for the current trigger.
        NotificationCenter.default.post(name: Notification.Name("BetterCmdTab_restoreNativeShortcuts"), object: nil)
    }

    private func refreshAccessibilityStatus(isUsable: Bool) {
        if isUsable {
            // Granted: show the state only — no actionable button.
            permissionIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: String(localized: "Granted"))
            permissionIcon.contentTintColor = .systemGreen
            permissionButton.isHidden = true
        } else {
            permissionIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: String(localized: "Required"))
            permissionIcon.contentTintColor = .systemOrange
            permissionButton.isHidden = false
            permissionButton.title = String(localized: "Grant Access")
        }
    }
}
