import AppKit

/// A small floating row of macOS "traffic light"–style circular buttons (close /
/// minimize / maximize / hide / quit) shown over a switcher row while the mouse
/// hovers it. Which buttons appear is driven by the `Preferences.hoverShow*`
/// toggles; the whole bar is shown/hidden by the host item view based on hover
/// state.
///
/// Clicks and per-dot hover are NOT handled by the dots themselves: the switcher
/// content lives inside an `NSGlassEffectView` whose hosted subtree doesn't
/// deliver mouse events to deep subviews, so `SwitcherView` does manual hit
/// testing (like its tile hit testing) and calls `action(atWindowPoint:)` /
/// `setHotAction(_:)` here.
@MainActor
final class HoverActionBar: NSView {
    /// Diameter of each circular dot, and the gap between them.
    static let dotSize: CGFloat = 14
    private static let spacing: CGFloat = 5

    private var dotsByAction: [RowAction: TrafficLightDot] = [:]
    private var orderedDots: [TrafficLightDot] = []

    /// The dot currently highlighted (mouse hovering it), if any.
    private(set) var hotAction: RowAction?

    private struct Spec {
        let action: RowAction
        let symbol: String
        let color: NSColor
        let tooltip: String
    }

    // Window controls borrow the real traffic-light colors (red / yellow /
    // green); app controls use neutral grays to read as a different group.
    private static let specs: [Spec] = [
        Spec(action: .close, symbol: "xmark", color: .systemRed, tooltip: "Close window"),
        Spec(action: .minimize, symbol: "minus", color: .systemYellow, tooltip: "Minimize window"),
        Spec(action: .maximize, symbol: "plus", color: .systemGreen, tooltip: "Zoom window"),
        Spec(action: .hide, symbol: "eye.slash.fill", color: .systemGray, tooltip: "Hide app"),
        Spec(action: .quit, symbol: "power", color: .systemGray, tooltip: "Quit app"),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for spec in Self.specs {
            let dot = TrafficLightDot(action: spec.action, color: spec.color, symbol: spec.symbol, tooltip: spec.tooltip)
            dotsByAction[spec.action] = dot
            orderedDots.append(dot)
            addSubview(dot)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layout() {
        super.layout()
        layoutDots()
    }

    /// Position the visible dots left-to-right. Called from `layout()` and from
    /// `applyEnabledButtons()` so frames are correct even when the bar's size
    /// doesn't change between reveals.
    private func layoutDots() {
        var x: CGFloat = 0
        for dot in orderedDots where !dot.isHidden {
            dot.frame = NSRect(x: x, y: 0, width: Self.dotSize, height: Self.dotSize)
            x += Self.dotSize + Self.spacing
        }
    }

    /// Exact size of the currently-visible dots; the host item view positions the
    /// bar using this so it never clips or stretches.
    var contentSize: NSSize {
        let visible = orderedDots.filter { !$0.isHidden }.count
        guard visible > 0 else { return .zero }
        let width = CGFloat(visible) * Self.dotSize + CGFloat(visible - 1) * Self.spacing
        return NSSize(width: width, height: Self.dotSize)
    }

    /// Show/hide each dot per the user's per-action preferences.
    func applyEnabledButtons() {
        let prefs = Preferences.shared
        dotsByAction[.close]?.isHidden = !prefs.hoverShowClose
        dotsByAction[.minimize]?.isHidden = !prefs.hoverShowMinimize
        dotsByAction[.maximize]?.isHidden = !prefs.hoverShowMaximize
        dotsByAction[.hide]?.isHidden = !prefs.hoverShowHide
        dotsByAction[.quit]?.isHidden = !prefs.hoverShowQuit
        layoutDots()
    }

    /// True when at least one action button is enabled.
    var hasAnyEnabledButton: Bool {
        let prefs = Preferences.shared
        return prefs.hoverShowClose || prefs.hoverShowMinimize || prefs.hoverShowMaximize
            || prefs.hoverShowHide || prefs.hoverShowQuit
    }

    /// The action whose dot contains `windowPoint` (in window coordinates), or
    /// nil. Used by `SwitcherView`'s manual hit testing.
    func action(atWindowPoint windowPoint: NSPoint) -> RowAction? {
        for dot in orderedDots where !dot.isHidden {
            let p = dot.convert(windowPoint, from: nil)
            if dot.bounds.contains(p) { return dot.action }
        }
        return nil
    }

    /// Highlight the given dot (mouse hovering it) and un-highlight the rest.
    func setHotAction(_ action: RowAction?) {
        guard hotAction != action else { return }
        hotAction = action
        for dot in orderedDots { dot.isHot = (dot.action == action) }
    }
}

/// A single circular traffic-light dot. Custom-drawn so it's always a perfect
/// circle. Mouse handling is driven externally by `SwitcherView` (see the type
/// doc on `HoverActionBar`), so this view only draws — including a brighter
/// "hot" state when the pointer is over it.
@MainActor
final class TrafficLightDot: NSView {
    let action: RowAction

    private let fillColor: NSColor
    private let glyph: NSImage?
    var isHot = false { didSet { if oldValue != isHot { needsDisplay = true } } }

    init(action: RowAction, color: NSColor, symbol: String, tooltip: String) {
        self.action = action
        self.fillColor = color
        let cfg = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            .applying(.init(paletteColors: [NSColor.black.withAlphaComponent(0.65)]))
        self.glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?.withSymbolConfiguration(cfg)
        super.init(frame: NSRect(x: 0, y: 0, width: HoverActionBar.dotSize, height: HoverActionBar.dotSize))
        toolTip = tooltip
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: HoverActionBar.dotSize, height: HoverActionBar.dotSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        let d = min(bounds.width, bounds.height)
        let circle = NSRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d).insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(ovalIn: circle)
        // Brighten on hover for a clear "hot" state.
        let fill = isHot ? (fillColor.blended(withFraction: 0.28, of: .white) ?? fillColor) : fillColor
        fill.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(isHot ? 0.28 : 0.18).setStroke()
        path.lineWidth = isHot ? 0.75 : 0.5
        path.stroke()

        // The glyph is always shown (the bar only appears on row hover anyway);
        // the hot state just brightens the dot beneath it.
        if let glyph {
            let gs = glyph.size
            let gr = NSRect(
                x: bounds.midX - gs.width / 2,
                y: bounds.midY - gs.height / 2,
                width: gs.width,
                height: gs.height
            )
            glyph.draw(in: gr)
        }
    }
}
