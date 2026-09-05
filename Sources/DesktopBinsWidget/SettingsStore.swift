import Foundation

/// User-tunable appearance and behaviour, persisted in UserDefaults.
///
/// The knobs differ from Desktop Bins: because a panel lays out its own
/// items rather than nudging Finder icons onto a grid, there is no snapping
/// to tune. Icon size and labels drive the layout instead.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let iconSize = "iconSize"
        static let showLabels = "showLabels"
        static let panelOpacity = "panelOpacity"
        static let hideDesktopIcons = "hideDesktopIcons"
        static let clickTitleBarToMove = "clickTitleBarToMove"
    }

    static let defaultIconSize: Double = 48
    static let defaultOpacity: Double = 0.9

    var onChange: (() -> Void)?

    /// Backed by the system login-item registration rather than UserDefaults,
    /// since macOS is the source of truth and the user can change it in
    /// System Settings behind our back.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LaunchAtLoginController.isEnabled else { return }
            if !LaunchAtLoginController.setEnabled(launchAtLogin) {
                launchAtLogin = LaunchAtLoginController.isEnabled
            }
        }
    }

    @Published var iconSize: Double { didSet { save(); onChange?() } }
    @Published var showLabels: Bool { didSet { save(); onChange?() } }
    @Published var panelOpacity: Double { didSet { save(); onChange?() } }

    /// Hide the desktop icon of an item once it lives in a bin, so the same
    /// file isn't shown twice. Only applies to items sitting on the Desktop.
    @Published var hideDesktopIcons: Bool { didSet { save(); onHideDesktopIconsChanged?(hideDesktopIcons) } }

    var onHideDesktopIconsChanged: ((Bool) -> Void)?

    /// When on, dragging the title bar moves the panel. Turn it off to
    /// require Command-drag instead, so a panel can't be nudged by accident.
    @Published var clickTitleBarToMove: Bool { didSet { save() } }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.iconSize: Self.defaultIconSize,
            Key.showLabels: true,
            Key.panelOpacity: Self.defaultOpacity,
            Key.hideDesktopIcons: true,
            Key.clickTitleBarToMove: true
        ])
        launchAtLogin = LaunchAtLoginController.isEnabled
        iconSize = defaults.double(forKey: Key.iconSize)
        showLabels = defaults.bool(forKey: Key.showLabels)
        panelOpacity = defaults.double(forKey: Key.panelOpacity)
        hideDesktopIcons = defaults.bool(forKey: Key.hideDesktopIcons)
        clickTitleBarToMove = defaults.bool(forKey: Key.clickTitleBarToMove)
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(iconSize, forKey: Key.iconSize)
        defaults.set(showLabels, forKey: Key.showLabels)
        defaults.set(panelOpacity, forKey: Key.panelOpacity)
        defaults.set(hideDesktopIcons, forKey: Key.hideDesktopIcons)
        defaults.set(clickTitleBarToMove, forKey: Key.clickTitleBarToMove)
    }

    /// Smallest a panel can be: one column of icons plus its insets, so a
    /// narrow single-column panel is possible at any icon size.
    var minPanelWidth: Double { cellWidth + 2 * Double(WidgetMetrics.contentInset) }
    var minPanelHeight: Double {
        Double(WidgetMetrics.titleBarHeight) + cellHeight + 2 * Double(WidgetMetrics.contentInset)
    }

    /// Cell size derived from the icon size, leaving room for the label.
    var cellWidth: Double { iconSize + 36 }
    var cellHeight: Double { iconSize + (showLabels ? Double(WidgetMetrics.labelHeight) : 8) + 12 }

    func resetToDefaults() {
        iconSize = Self.defaultIconSize
        showLabels = true
        panelOpacity = Self.defaultOpacity
        hideDesktopIcons = true
        clickTitleBarToMove = true
    }
}
