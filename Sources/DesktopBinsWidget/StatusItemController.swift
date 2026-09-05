import AppKit

/// Menu bar entry point. The menu is rebuilt on open so its checkmarks and
/// counts always reflect current state.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let panelController: BinPanelController
    private let settingsWindowController = SettingsWindowController()

    private static let iconSizes: [(String, Double)] = [
        ("Small (32 pt)", 32),
        ("Medium (48 pt)", 48),
        ("Large (64 pt)", 64),
        ("Extra Large (96 pt)", 96)
    ]

    init(panelController: BinPanelController) {
        self.panelController = panelController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Desktop Bins Widget")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = SettingsStore.shared
        menu.removeAllItems()

        menu.addItem(withTitle: "New Bin", action: #selector(newBin), keyEquivalent: "n", target: self)
        menu.addItem(.separator())

        let sizeItem = menu.addItem(withTitle: "Icon Size", action: nil, keyEquivalent: "", target: nil)
        let sizeMenu = NSMenu()
        for (name, value) in Self.iconSizes {
            let item = NSMenuItem(title: name, action: #selector(setIconSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = settings.iconSize == value ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu

        let labelsItem = menu.addItem(withTitle: "Show Labels", action: #selector(toggleLabels), keyEquivalent: "", target: self)
        labelsItem.state = settings.showLabels ? .on : .off

        let hideItem = menu.addItem(withTitle: "Hide Desktop Icons for Items in Bins", action: #selector(toggleHideDesktopIcons), keyEquivalent: "", target: self)
        hideItem.state = settings.hideDesktopIcons ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove Missing Items", action: #selector(removeMissing), keyEquivalent: "", target: self)
        menu.addItem(withTitle: "Show All Hidden Desktop Icons", action: #selector(unhideAll), keyEquivalent: "", target: self)
        menu.addItem(withTitle: "Bring All Bins to Main Display", action: #selector(consolidate), keyEquivalent: "", target: self)

        let visibilityTitle = panelController.isVisible ? "Hide All Bins" : "Show All Bins"
        menu.addItem(withTitle: visibilityTitle, action: #selector(toggleVisibility), keyEquivalent: "", target: self)

        let loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "", target: self)
        loginItem.state = settings.launchAtLogin ? .on : .off

        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",", target: self)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Desktop Bins Widget", action: #selector(quit), keyEquivalent: "q", target: self)

        // Version last, as a non-actionable footer.
        menu.addItem(.separator())
        let versionItem = NSMenuItem(title: "Desktop Bins Widget \(AppInfo.displayVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
    }

    @objc private func newBin() { panelController.addBinAtCenterOfMainScreen() }
    @objc private func toggleLabels() { SettingsStore.shared.showLabels.toggle() }
    @objc private func toggleHideDesktopIcons() { SettingsStore.shared.hideDesktopIcons.toggle() }

    @objc private func unhideAll() {
        let restored = panelController.restoreAllDesktopIcons()
        let alert = NSAlert()
        alert.messageText = restored == 0 ? "Nothing was hidden" : "Restored \(restored) desktop icon(s)"
        alert.informativeText = restored == 0
            ? "No bin item currently has its desktop icon hidden."
            : "Those files are visible on the Desktop again. They are still in their bins."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc private func toggleVisibility() { panelController.setAllVisible(!panelController.isVisible) }
    @objc private func toggleLaunchAtLogin() { SettingsStore.shared.launchAtLogin.toggle() }
    @objc private func showSettings() { settingsWindowController.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func setIconSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        SettingsStore.shared.iconSize = value
    }

    @objc private func consolidate() {
        let alert = NSAlert()
        alert.messageText = "Bring all bins to the main display?"
        alert.informativeText = "Every panel will be moved onto this display and re-pinned here. Use this if panels are stranded on a monitor that is no longer attached."
        alert.addButton(withTitle: "Bring Them Here")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let moved = panelController.consolidateBinsToMainDisplay()
        let done = NSAlert()
        done.messageText = "Moved \(moved) bin(s)"
        done.informativeText = "They are now on the main display and pinned to it."
        done.addButton(withTitle: "OK")
        done.runModal()
    }

    @objc private func removeMissing() {
        let removed = panelController.removeMissingItems()
        let alert = NSAlert()
        alert.messageText = removed == 0 ? "No missing items" : "Removed \(removed) missing item(s)"
        alert.informativeText = removed == 0
            ? "Every item in your bins still points at a file that exists."
            : "Those files no longer exist, so their shortcuts were cleared."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private extension NSMenu {
    @discardableResult
    func addItem(withTitle title: String, action: Selector?, keyEquivalent: String, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        addItem(item)
        return item
    }
}
