import AppKit

@MainActor
final class SettingsWindowPresenter {

    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    private var windowController: NSWindowController?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func show() {
        if window == nil {
            createWindow()
        }
        guard let window else { return }

        if !window.isVisible {
            window.center()
        }
        // Activate without switching activation policy — this stays an
        // accessory app (no dock icon) while still receiving key events.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak window] in
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Closing the window (red button / ⌘W) releases the whole window tree —
    /// the split view controller, the sidebar, and every cached per-tab
    /// controller with its views, gradient layers and images — so RAM returns
    /// to the pre-open baseline instead of staying resident for the process
    /// lifetime. `show()` lazily rebuilds it on the next open. None of the tab
    /// controllers retain `self` (all Combine sinks/observers/timers use
    /// `[weak self]` and are torn down on disappear), so dropping these two
    /// references is enough for ARC to free the tree.
    ///
    /// Runs as a separate main-queue operation (the `willClose` observer uses
    /// `queue: .main`), i.e. after AppKit's close sequence unwinds — releasing
    /// the window's last reference *during* `close` would dealloc it mid-call.
    private func teardownAfterClose() {
        if let token = closeObserver {
            NotificationCenter.default.removeObserver(token)
            closeObserver = nil
        }
        // Drop the content view controller (and toolbar) explicitly so the whole
        // VC/view tree — the controls, gradient layers and images that grow the
        // footprint — is released right now, decoupled from when the NSWindow
        // object itself finally deallocs (it can linger briefly in an autorelease
        // pool or in NSApp's window list).
        //
        // This genuinely frees the memory, but the process footprint won't fall
        // all the way back to the pre-open baseline: macOS keeps freed small
        // allocations mapped in libmalloc's per-size free lists for fast reuse
        // rather than returning them to the OS (malloc_zone_pressure_relief is a
        // measured no-op for these — it reclaims 0). The memory is not leaked:
        // reopening Settings reuses these pages instead of growing the footprint,
        // and the kernel reclaims them under real memory pressure.
        window?.contentViewController = nil
        window?.toolbar = nil
        windowController = nil
        window = nil
    }

    private func createWindow() {
        let vc = SettingsViewController()

        let size = NSSize(width: 870, height: 650)
        let win = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = SettingsTab.general.title
        win.titleVisibility = .visible
        win.titlebarAppearsTransparent = false
        win.titlebarSeparatorStyle = .automatic
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.collectionBehavior.insert(.fullScreenAuxiliary)
        win.collectionBehavior.insert(.moveToActiveSpace)
        win.hidesOnDeactivate = false
        win.level = .normal

        // Unified toolbar so macOS 26 Liquid Glass applies naturally.
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        win.toolbar = toolbar
        win.toolbarStyle = .unified

        win.contentViewController = vc
        win.setContentSize(size)
        win.contentMinSize = size
        win.contentMaxSize = size
        win.center()

        self.window = win
        self.windowController = NSWindowController(window: win)

        // Free the window tree when the user closes it (see teardownAfterClose).
        // Scoped to this window; `queue: .main` defers the block until after the
        // close sequence finishes.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.teardownAfterClose()
            }
        }
    }
}

private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Handle Cmd+W locally — the app is accessory and has no main menu, so
    /// there's no File > Close menu item routing the shortcut to performClose.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
