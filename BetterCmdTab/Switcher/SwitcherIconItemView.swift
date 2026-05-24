import AppKit

@MainActor
protocol SwitcherItemViewProtocol: NSView {
    var isSelected: Bool { get set }
    func configure(with row: SwitcherRow, label: String, prefixLength: Int, selected: Bool, metrics: SwitcherMetrics)
}

@MainActor
final class SwitcherIconItemView: NSView, SwitcherItemViewProtocol {
    private let selectionBackdrop = NSView()
    private let imageView = NSImageView()
    private let letterBadge = NSView()
    private let letterLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusStack = NSStackView()
    private let hiddenIcon = NSImageView()
    private let minimizedIcon = NSImageView()
    private let noWindowIcon = NSImageView()
    private let fullscreenIcon = NSImageView()

    private var metrics: SwitcherMetrics = .baseline

    var isSelected: Bool = false {
        didSet {
            guard oldValue != isSelected else { return }
            applySelection()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        selectionBackdrop.wantsLayer = true
        selectionBackdrop.layer?.cornerCurve = .continuous
        selectionBackdrop.layer?.borderWidth = 1.5
        selectionBackdrop.isHidden = true
        addSubview(selectionBackdrop)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        addSubview(imageView)

        letterBadge.wantsLayer = true
        letterBadge.layer?.cornerCurve = .continuous
        letterBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        addSubview(letterBadge)

        letterLabel.alignment = .center
        letterLabel.lineBreakMode = .byClipping
        letterLabel.maximumNumberOfLines = 1
        letterLabel.usesSingleLineMode = true
        letterLabel.textColor = .white
        letterLabel.drawsBackground = false
        letterLabel.isBezeled = false
        letterLabel.isEditable = false
        letterLabel.isSelectable = false
        letterBadge.addSubview(letterLabel)

        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.usesSingleLineMode = true
        nameLabel.textColor = .labelColor
        nameLabel.drawsBackground = false
        nameLabel.isBezeled = false
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        addSubview(nameLabel)

        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.usesSingleLineMode = true
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        addSubview(titleLabel)

        statusStack.orientation = .horizontal
        statusStack.spacing = 2
        statusStack.alignment = .centerY
        statusStack.distribution = .fill
        addSubview(statusStack)

        for iv in [hiddenIcon, minimizedIcon, noWindowIcon, fullscreenIcon] {
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.imageAlignment = .alignCenter
            iv.imageFrameStyle = .none
            iv.isHidden = true
            iv.wantsLayer = true
            iv.translatesAutoresizingMaskIntoConstraints = false
            statusStack.addArrangedSubview(iv)
            NSLayoutConstraint.activate([
                iv.widthAnchor.constraint(equalToConstant: SwitcherMetrics.baseTileStatusIconSize),
                iv.heightAnchor.constraint(equalToConstant: SwitcherMetrics.baseTileStatusIconSize),
            ])
        }
        updateStatusIconTint()
        updateSelectionAppearance()
        hiddenIcon.image = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: "Hidden app")
        minimizedIcon.image = NSImage(systemSymbolName: "minus.rectangle.fill", accessibilityDescription: "Minimized window")
        noWindowIcon.image = NSImage(systemSymbolName: "square.dashed", accessibilityDescription: "No active window")
        fullscreenIcon.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Fullscreen window")

        applyMetrics(metrics)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStatusIconTint()
        updateSelectionAppearance()
    }

    private func updateStatusIconTint() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color: NSColor = isDark ? .white : .black
        for iv in [hiddenIcon, minimizedIcon, noWindowIcon, fullscreenIcon] {
            iv.contentTintColor = color
        }
    }

    private func updateSelectionAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill: NSColor
        let border: NSColor
        if isDark {
            fill = NSColor.white.withAlphaComponent(0.14)
            border = NSColor.white.withAlphaComponent(0.50)
        } else {
            fill = NSColor.black.withAlphaComponent(0.10)
            border = NSColor.black.withAlphaComponent(0.55)
        }
        selectionBackdrop.layer?.backgroundColor = fill.cgColor
        selectionBackdrop.layer?.borderColor = border.cgColor
    }

    private var currentLabel: String = ""
    private var currentPrefixLength: Int = 0

    func configure(with row: SwitcherRow, label: String, prefixLength: Int, selected: Bool, metrics: SwitcherMetrics) {
        if metrics != self.metrics {
            applyMetrics(metrics)
        }
        currentLabel = label
        currentPrefixLength = prefixLength
        renderLetter()
        nameLabel.stringValue = row.appName
        let secondary: String
        if row.isPlaceholder || row.window == nil {
            secondary = ""
        } else {
            secondary = row.windowTitle
        }
        titleLabel.stringValue = secondary
        titleLabel.isHidden = secondary.isEmpty
        imageView.image = IconCache.icon(for: row)

        let showHidden = !row.isPlaceholder && row.app.isHidden
        let showMinimized = !row.isPlaceholder && row.isMinimized && !showHidden
        let showNoWindow = !row.isPlaceholder && row.window == nil && !showHidden
        let showFullscreen = !row.isPlaceholder && row.isFullscreen && !showHidden && !showMinimized && !showNoWindow
        hiddenIcon.isHidden = !showHidden
        minimizedIcon.isHidden = !showMinimized
        noWindowIcon.isHidden = !showNoWindow
        fullscreenIcon.isHidden = !showFullscreen
        let anyStatus = showHidden || showMinimized || showNoWindow || showFullscreen
        statusStack.isHidden = !anyStatus

        letterBadge.isHidden = label.isEmpty

        isSelected = selected
        applySelection()
        needsLayout = true
    }

    private func applyMetrics(_ metrics: SwitcherMetrics) {
        self.metrics = metrics
        letterLabel.font = NSFont.monospacedSystemFont(ofSize: metrics.tileLetterFontSize, weight: .bold)
        nameLabel.font = NSFont.systemFont(ofSize: metrics.tileNameFontSize, weight: .medium)
        titleLabel.font = NSFont.systemFont(ofSize: metrics.tileTitleFontSize, weight: .regular)
        letterBadge.layer?.cornerRadius = metrics.tileLetterBadgeSize / 2
        selectionBackdrop.layer?.cornerRadius = metrics.tileSelectionCornerRadius

        let symbolCfg = NSImage.SymbolConfiguration(pointSize: metrics.tileStatusIconSize - 2, weight: .semibold)
        for iv in [hiddenIcon, minimizedIcon, noWindowIcon, fullscreenIcon] {
            iv.symbolConfiguration = symbolCfg
        }
        needsLayout = true
    }

    private func applySelection() {
        selectionBackdrop.isHidden = !isSelected
        nameLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        nameLabel.font = NSFont.systemFont(
            ofSize: metrics.tileNameFontSize,
            weight: isSelected ? .semibold : .medium
        )
        renderLetter()
    }

    private func renderLetter() {
        let labelStr = currentLabel.uppercased()
        guard !labelStr.isEmpty else {
            letterLabel.stringValue = ""
            letterLabel.frame = .zero
            return
        }
        let highlightLen = min(currentPrefixLength, labelStr.count)
        let base = NSFont.monospacedSystemFont(ofSize: metrics.tileLetterFontSize, weight: .bold)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attr = NSMutableAttributedString(string: labelStr, attributes: [
            .font: base,
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ])
        if highlightLen > 0 {
            let range = NSRange(location: 0, length: highlightLen)
            attr.addAttribute(.foregroundColor, value: NSColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1.0), range: range)
        }
        letterLabel.attributedStringValue = attr
        letterLabel.sizeToFit()
        centerLetterLabel()
    }

    private func centerLetterLabel() {
        let badgeSize = letterBadge.bounds.width
        guard badgeSize > 0 else { return }
        let w = ceil(letterLabel.frame.width)
        let h = ceil(letterLabel.frame.height)
        letterLabel.frame = NSRect(
            x: round((badgeSize - w) / 2),
            y: round((badgeSize - h) / 2),
            width: w,
            height: h
        )
    }

    override func layout() {
        super.layout()
        let m = metrics
        let w = bounds.width
        let tile = m.tileSize
        let iconArea = NSRect(x: (w - tile) / 2, y: bounds.height - tile, width: tile, height: tile)

        selectionBackdrop.frame = iconArea.insetBy(dx: m.tileSelectionInset, dy: m.tileSelectionInset)

        let iconRect = NSRect(
            x: iconArea.midX - m.tileIconSize / 2,
            y: iconArea.midY - m.tileIconSize / 2,
            width: m.tileIconSize,
            height: m.tileIconSize
        )
        imageView.frame = iconRect

        let badgeSize = m.tileLetterBadgeSize
        letterBadge.frame = NSRect(
            x: iconArea.minX + 2,
            y: iconArea.maxY - badgeSize - 2,
            width: badgeSize,
            height: badgeSize
        )
        centerLetterLabel()

        if !statusStack.isHidden {
            let visibleCount = statusStack.arrangedSubviews.filter { !$0.isHidden }.count
            let stackW = CGFloat(visibleCount) * m.tileStatusIconSize + CGFloat(max(0, visibleCount - 1)) * 2
            statusStack.frame = NSRect(
                x: iconArea.maxX - stackW - 4,
                y: iconArea.minY + 4,
                width: stackW,
                height: m.tileStatusIconSize
            )
        }

        let labelAreaH = m.tileLabelArea
        let nameH = ceil(nameLabel.font?.pointSize ?? m.tileNameFontSize) + 4
        let titleH = ceil(titleLabel.font?.pointSize ?? m.tileTitleFontSize) + 2
        let labelY: CGFloat = 0
        nameLabel.frame = NSRect(
            x: 0,
            y: labelY + labelAreaH - nameH,
            width: w,
            height: nameH
        )
        titleLabel.frame = NSRect(
            x: 0,
            y: labelY + labelAreaH - nameH - titleH,
            width: w,
            height: titleH
        )
    }
}
