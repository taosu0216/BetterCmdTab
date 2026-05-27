import AppKit

struct SwitcherMetrics: Equatable {
    let layoutMode: SwitcherLayoutMode
    let scale: CGFloat
    let rowHeight: CGFloat
    let rowWidth: CGFloat
    let iconSize: CGFloat
    let appNameWidth: CGFloat
    let interGap: CGFloat
    let horizontalInset: CGFloat
    let fontSize: CGFloat
    let outerPadding: CGFloat
    let cornerRadius: CGFloat
    let highlightCornerRadius: CGFloat
    let highlightInset: CGFloat
    let labelHeight: CGFloat
    let letterColumnWidth: CGFloat
    let letterFontSize: CGFloat

    // Icon-dock layout metrics
    let tileSize: CGFloat
    let tileIconSize: CGFloat
    let tileGap: CGFloat
    let tileLabelArea: CGFloat
    let tileLetterArea: CGFloat
    let tileNameFontSize: CGFloat
    let tileTitleFontSize: CGFloat
    let tileLetterFontSize: CGFloat
    let tileLetterBadgeSize: CGFloat
    let tileStatusIconSize: CGFloat
    let tileSelectionInset: CGFloat
    let tileSelectionCornerRadius: CGFloat

    // Window-preview (alt-tab) layout metrics
    let previewTileWidth: CGFloat
    let previewThumbHeight: CGFloat
    let previewGap: CGFloat
    let previewLabelArea: CGFloat
    let previewLetterArea: CGFloat
    let previewIconSize: CGFloat
    let previewNameFontSize: CGFloat
    let previewThumbCornerRadius: CGFloat
    let previewSelectionInset: CGFloat
    let previewSelectionCornerRadius: CGFloat

    static let baseRowHeight: CGFloat = 28
    static let baseRowWidth: CGFloat = 720
    static let baseIconSize: CGFloat = 18
    static let baseAppNameWidth: CGFloat = 200
    static let baseInterGap: CGFloat = 10
    static let baseHorizontalInset: CGFloat = 14
    static let baseFontSize: CGFloat = 13
    static let baseOuterPadding: CGFloat = 8
    static let baseCornerRadius: CGFloat = 12
    static let baseHighlightCornerRadius: CGFloat = 6
    static let baseHighlightInset: CGFloat = 4
    static let baseLabelHeight: CGFloat = 18
    static let baseLetterColumnWidth: CGFloat = 34
    static let baseLetterFontSize: CGFloat = 11
    static let referenceWidth: CGFloat = 1440

    // Icon-dock base metrics (sized to match macOS-default Cmd+Tab proportions).
    static let baseTileSize: CGFloat = 80
    static let baseTileIconSize: CGFloat = 64
    static let baseTileGap: CGFloat = 10
    static let baseTileLabelArea: CGFloat = 34
    /// Top strip above each tile's icon that holds the type-to-jump letter, so
    /// the letter never overlaps the icon.
    static let baseTileLetterArea: CGFloat = 16
    static let baseTileNameFontSize: CGFloat = 11
    static let baseTileTitleFontSize: CGFloat = 10
    static let baseTileLetterFontSize: CGFloat = 11
    static let baseTileLetterBadgeSize: CGFloat = 20
    static let baseTileStatusIconSize: CGFloat = 12
    static let baseTileSelectionInset: CGFloat = 4
    static let baseTileSelectionCornerRadius: CGFloat = 16
    static let baseTileOuterPadding: CGFloat = 14
    static let baseTileCornerRadius: CGFloat = 24

    // Window-preview base metrics. A uniform tile: jump-letter strip on top, a
    // 16:10 thumbnail area in the middle (the live capture is aspect-fit and
    // letterboxed inside it), and a label row (small app icon + window title)
    // below. Reuses the grid tile's outer padding / panel corner radius.
    static let basePreviewTileWidth: CGFloat = 208
    static let basePreviewThumbHeight: CGFloat = 130
    static let basePreviewGap: CGFloat = 12
    static let basePreviewLabelArea: CGFloat = 24
    static let basePreviewIconSize: CGFloat = 18
    static let basePreviewNameFontSize: CGFloat = 11
    static let basePreviewThumbCornerRadius: CGFloat = 8
    static let basePreviewSelectionInset: CGFloat = 3
    static let basePreviewSelectionCornerRadius: CGFloat = 12

    static let baseline = SwitcherMetrics.forScale(1.0, layoutMode: .list)

    static func forScreen(_ screen: NSScreen?, layoutMode: SwitcherLayoutMode = .list, userScale: CGFloat = 1.0, letterHints: Bool = true) -> SwitcherMetrics {
        let width = screen?.frame.width ?? referenceWidth
        let raw = width / referenceWidth
        // Screen-adaptive clamp first (keep base size on small displays, cap on
        // huge ones), then fold in the user's size preference as a free multiplier
        // so "Small" can shrink below the 1.0 floor.
        let clamped = max(1.0, min(1.8, raw)) * userScale
        return forScale(clamped, layoutMode: layoutMode, letterHints: letterHints)
    }

    /// `letterHints == false` collapses the space the jump-letter occupies — the
    /// top strip on tiles and the left column in the list — so the panel reflows
    /// tighter when the user turned letter hints off.
    static func forScale(_ scale: CGFloat, layoutMode: SwitcherLayoutMode = .list, letterHints: Bool = true) -> SwitcherMetrics {
        let outerPadding: CGFloat
        let cornerRadius: CGFloat
        switch layoutMode {
        case .list:
            outerPadding = round(baseOuterPadding * scale)
            cornerRadius = round(baseCornerRadius * scale)
        case .gridView, .windowPreview:
            outerPadding = round(baseTileOuterPadding * scale)
            cornerRadius = round(baseTileCornerRadius * scale)
        }

        return SwitcherMetrics(
            layoutMode: layoutMode,
            scale: scale,
            rowHeight: round(baseRowHeight * scale),
            rowWidth: round(baseRowWidth * scale),
            iconSize: round(baseIconSize * scale),
            appNameWidth: round(baseAppNameWidth * scale),
            interGap: round(baseInterGap * scale),
            horizontalInset: round(baseHorizontalInset * scale),
            fontSize: baseFontSize * scale,
            outerPadding: outerPadding,
            cornerRadius: cornerRadius,
            highlightCornerRadius: round(baseHighlightCornerRadius * scale),
            highlightInset: round(baseHighlightInset * scale),
            labelHeight: round(baseLabelHeight * scale),
            letterColumnWidth: letterHints ? round(baseLetterColumnWidth * scale) : 0,
            letterFontSize: baseLetterFontSize * scale,
            tileSize: round(baseTileSize * scale),
            tileIconSize: round(baseTileIconSize * scale),
            tileGap: round(baseTileGap * scale),
            tileLabelArea: round(baseTileLabelArea * scale),
            tileLetterArea: letterHints ? round(baseTileLetterArea * scale) : 0,
            tileNameFontSize: baseTileNameFontSize * scale,
            tileTitleFontSize: baseTileTitleFontSize * scale,
            tileLetterFontSize: baseTileLetterFontSize * scale,
            tileLetterBadgeSize: round(baseTileLetterBadgeSize * scale),
            tileStatusIconSize: round(baseTileStatusIconSize * scale),
            tileSelectionInset: round(baseTileSelectionInset * scale),
            tileSelectionCornerRadius: round(baseTileSelectionCornerRadius * scale),
            previewTileWidth: round(basePreviewTileWidth * scale),
            previewThumbHeight: round(basePreviewThumbHeight * scale),
            previewGap: round(basePreviewGap * scale),
            previewLabelArea: round(basePreviewLabelArea * scale),
            previewLetterArea: letterHints ? round(baseTileLetterArea * scale) : 0,
            previewIconSize: round(basePreviewIconSize * scale),
            previewNameFontSize: basePreviewNameFontSize * scale,
            previewThumbCornerRadius: round(basePreviewThumbCornerRadius * scale),
            previewSelectionInset: round(basePreviewSelectionInset * scale),
            previewSelectionCornerRadius: round(basePreviewSelectionCornerRadius * scale)
        )
    }
}
