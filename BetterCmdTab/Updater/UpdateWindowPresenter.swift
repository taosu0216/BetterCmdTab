//
//  UpdateWindowPresenter.swift
//  BetterCmdTab
//
//  Manages a Sparkle-like update window (NSPanel) that hosts UpdateWindowView.
//  Shown automatically when a new version is detected via GitHub Releases API.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class UpdateWindowPresenter {

    // MARK: - Singleton

    static let shared = UpdateWindowPresenter()

    // MARK: - Private Properties

    private var panel: NSPanel?
    private var updateView: UpdateWindowView?
    private var stateObserver: AnyCancellable?
    private var betaToggleObserver: AnyCancellable?

    // MARK: - Init

    private init() {
        observeUpdaterState()
    }

    // MARK: - Public

    func show() {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        panel.center()
        panel.orderFrontRegardless()

        updateView?.forceReloadContent()

        DispatchQueue.main.async { [weak panel] in
            guard let panel else { return }
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        // Release the release-notes image cache (up to 24 MB) now that the
        // window is gone — it would otherwise persist for the app's lifetime
        // after a single viewing. Re-downloaded lazily on the next open.
        MarkdownImageCache.clearAll()
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Private

    private func createPanel() {
        let size = NSSize(
            width: UpdateWindowView.Layout.windowWidth,
            height: UpdateWindowView.Layout.windowHeight
        )

        let panel = UpdatePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.animationBehavior = .documentWindow
        panel.hidesOnDeactivate = false

        panel.contentMinSize = size
        panel.contentMaxSize = size

        guard let contentView = panel.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 16
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true

        if let frameView = contentView.superview {
            frameView.wantsLayer = true
            if frameView.layer == nil { frameView.layer = CALayer() }
            frameView.layer?.backgroundColor = NSColor.clear.cgColor
            frameView.layer?.cornerRadius = 16
            frameView.layer?.cornerCurve = .continuous
            frameView.layer?.masksToBounds = true
        }

        let background = makeBackground(cornerRadius: 16)
        background.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let updateView = UpdateWindowView(frame: contentView.bounds)
        updateView.autoresizingMask = [.width, .height]
        contentView.addSubview(updateView)

        self.panel = panel
        self.updateView = updateView
    }

    private func makeBackground(cornerRadius: CGFloat) -> NSView {
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glassView = glassClass.init(frame: .zero)

            if let effectView = glassView as? NSVisualEffectView {
                effectView.state = .active
            }
            if glassView.responds(to: Selector(("setCornerRadius:"))) {
                glassView.setValue(cornerRadius, forKey: "cornerRadius")
            }
            if glassView.responds(to: Selector(("set_variant:"))) {
                glassView.setValue(LiquidGlassVariant.bestSupportedVariant.rawValue, forKey: "_variant")
            }
            if glassView.responds(to: Selector(("setUsesAccentColor:"))) {
                glassView.setValue(false, forKey: "usesAccentColor")
            }
            if glassView.responds(to: Selector(("setAutomaticGrouping:"))) {
                glassView.setValue(true, forKey: "automaticGrouping")
            }
            if glassView.responds(to: Selector(("setNativeRendering:"))) {
                glassView.setValue(true, forKey: "nativeRendering")
            }
            if glassView.responds(to: Selector(("setIntegratedWithWindow:"))) {
                glassView.setValue(true, forKey: "integratedWithWindow")
            }

            glassView.wantsLayer = true
            glassView.layer?.masksToBounds = true
            return glassView
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = .popover
            effectView.state = .active
            effectView.blendingMode = .behindWindow
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = cornerRadius
            effectView.layer?.cornerCurve = .continuous
            effectView.layer?.masksToBounds = true
            return effectView
        }
    }

    private func observeUpdaterState() {
        stateObserver = GitHubUpdater.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle, .upToDate:
                    self.hide()
                default:
                    break
                }
            }

        betaToggleObserver = GitHubUpdater.shared.$includePreReleases
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                switch GitHubUpdater.shared.state {
                case .downloading, .installing, .readyToInstall:
                    return
                default:
                    self.hide()
                }
            }
    }

    // MARK: - Custom Panel

    private final class UpdatePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}
