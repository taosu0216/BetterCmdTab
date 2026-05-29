import AppKit
import BetterSettings

/// Presents the settings window. Lifecycle (lazy creation, activation,
/// free-on-close, robust reopen) is owned by `BetterSettings.SettingsPresenter`;
/// this just wires the catalog and keeps the existing `show()` call sites working.
@MainActor
final class SettingsWindowPresenter {

    static let shared = SettingsWindowPresenter()

    private let presenter = SettingsPresenter(closeBehavior: .releaseOnClose) {
        SettingsCatalog.makeConfiguration()
    }

    /// Observer that reverts the activation policy when the settings window
    /// closes. Re-created on every `show()` because `.releaseOnClose` builds a
    /// fresh window each time.
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func show() {
        // The app normally runs as `.accessory` (no Dock icon, menu-bar only).
        // An accessory app can't pull a window in front of the active app —
        // `NSApp.activate(ignoringOtherApps:)` is weakened for accessory apps on
        // macOS 14+, so Settings opens *behind* whatever's frontmost. Promote to
        // `.regular` so the app can activate as a normal foreground app; revert
        // to `.accessory` once the window closes so the Dock icon doesn't linger.
        NSApp.setActivationPolicy(.regular)
        presenter.show()

        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        observeCloseForPolicyRevert(window)

        // Activate on the next runloop tick. A just-promoted accessory app can't
        // foreground in the same tick the policy changed — the change has to
        // register with the window server first, so a synchronous `activate` is
        // a no-op and the window stays behind. Deferring one tick lets the
        // activation actually raise the window above other apps.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }

    func hide() {
        presenter.hide()
    }

    /// Watch the now-visible settings window for close and drop the app back to
    /// `.accessory`. Keyed off that specific window so a stray close of some
    /// other window (e.g. an apps-picker sheet) doesn't demote us early.
    private func observeCloseForPolicyRevert(_ window: NSWindow?) {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        guard let window else { return }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                NSApp.setActivationPolicy(.accessory)
                if let token = self?.closeObserver {
                    NotificationCenter.default.removeObserver(token)
                    self?.closeObserver = nil
                }
            }
        }
    }
}
