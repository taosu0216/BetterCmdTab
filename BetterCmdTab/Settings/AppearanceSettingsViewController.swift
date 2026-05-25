import AppKit
import Combine

@MainActor
final class AppearanceSettingsViewController: NSViewController {

    private let layoutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gridPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let delaySlider = NSSlider()
    private let delayValueLabel = NSTextField(labelWithString: "")

    private var cancellables = Set<AnyCancellable>()

    // Ordered option models backing the popups (index ↔ value).
    private let layoutModes: [SwitcherLayoutMode] = [.gridView, .list]
    private let panelSizes: [PanelSize] = PanelSize.allCases
    private let gridValues: [Int] = [0, 2, 3, 4, 5, 6] // 0 = automatic

    override func loadView() {
        let section = SettingsSectionView(header: "Switcher")

        configurePopup(layoutPopup, titles: layoutModes.map(\.displayName), action: #selector(layoutChanged))
        section.addContent(SettingsRowView(title: "Layout", accessory: layoutPopup))

        configurePopup(sizePopup, titles: panelSizes.map(\.displayName), action: #selector(sizeChanged))
        section.addContent(SettingsRowView(title: "Size", accessory: sizePopup))

        configurePopup(gridPopup, titles: gridValues.map { $0 == 0 ? "Automatic" : "\($0)" }, action: #selector(gridChanged))
        section.addContent(SettingsRowView(
            title: "Grid columns",
            subtitle: "Applies to the Grid layout only.",
            accessory: gridPopup
        ))

        delaySlider.minValue = Double(Preferences.revealDelayRange.lowerBound)
        delaySlider.maxValue = Double(Preferences.revealDelayRange.upperBound)
        delaySlider.isContinuous = true
        delaySlider.target = self
        delaySlider.action = #selector(delayChanged(_:))
        delaySlider.translatesAutoresizingMaskIntoConstraints = false

        delayValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        delayValueLabel.textColor = .secondaryLabelColor
        delayValueLabel.alignment = .right
        delayValueLabel.translatesAutoresizingMaskIntoConstraints = false
        delayValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let sliderStack = NSStackView(views: [delaySlider, delayValueLabel])
        sliderStack.orientation = .horizontal
        sliderStack.spacing = 8
        sliderStack.alignment = .centerY
        NSLayoutConstraint.activate([
            delaySlider.widthAnchor.constraint(equalToConstant: 140),
            delayValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
        section.addContent(SettingsRowView(
            title: "Quick-switch delay",
            subtitle: "Tap and release to switch instantly; hold longer to open the switcher.",
            accessory: sliderStack
        ))

        view = SettingsLayout.makeScrollingTab(sections: [section])
    }

    private func configurePopup(_ popup: NSPopUpButton, titles: [String], action: Selector) {
        popup.controlSize = .small
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.setContentHuggingPriority(.required, for: .horizontal)
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = action
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        syncFromPreferences()

        let prefs = Preferences.shared
        prefs.$switcherLayoutMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectLayout($0) }
            .store(in: &cancellables)
        prefs.$panelSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectSize($0) }
            .store(in: &cancellables)
        prefs.$gridMaxColumns
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.selectGrid($0) }
            .store(in: &cancellables)
        prefs.$revealDelayMs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyDelay($0) }
            .store(in: &cancellables)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        cancellables.removeAll()
    }

    private func syncFromPreferences() {
        let prefs = Preferences.shared
        selectLayout(prefs.switcherLayoutMode)
        selectSize(prefs.panelSize)
        selectGrid(prefs.gridMaxColumns)
        applyDelay(prefs.revealDelayMs)
    }

    private func selectLayout(_ mode: SwitcherLayoutMode) {
        if let i = layoutModes.firstIndex(of: mode) { layoutPopup.selectItem(at: i) }
    }

    private func selectSize(_ size: PanelSize) {
        if let i = panelSizes.firstIndex(of: size) { sizePopup.selectItem(at: i) }
    }

    private func selectGrid(_ value: Int) {
        gridPopup.selectItem(at: gridValues.firstIndex(of: value) ?? 0)
    }

    private func applyDelay(_ ms: Int) {
        if Int(delaySlider.intValue) != ms { delaySlider.integerValue = ms }
        delayValueLabel.stringValue = "\(ms) ms"
    }

    @objc private func layoutChanged() {
        Preferences.shared.switcherLayoutMode = layoutModes[layoutPopup.indexOfSelectedItem]
    }

    @objc private func sizeChanged() {
        Preferences.shared.panelSize = panelSizes[sizePopup.indexOfSelectedItem]
    }

    @objc private func gridChanged() {
        Preferences.shared.gridMaxColumns = gridValues[gridPopup.indexOfSelectedItem]
    }

    @objc private func delayChanged(_ sender: NSSlider) {
        Preferences.shared.revealDelayMs = sender.integerValue
    }
}
