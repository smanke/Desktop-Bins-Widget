import AppKit

/// Owns one window per bin and handles every panel action.
final class BinPanelController: NSObject, BinPanelViewDelegate {
    private let store: BinStore
    private var windows: [UUID: BinPanelWindow] = [:]
    private var expandedHeights: [UUID: Double] = [:]
    private var gestureStartFrame: NSRect?
    private var screenSettleWorkItem: DispatchWorkItem?
    private(set) var isVisible = true

    private var minWidth: CGFloat { CGFloat(SettingsStore.shared.minPanelWidth) }
    private var minHeight: CGFloat { CGFloat(SettingsStore.shared.minPanelHeight) }

    init(store: BinStore) {
        self.store = store
        super.init()
        store.onChange = { [weak self] in self?.syncWindows() }
        SettingsStore.shared.onChange = { [weak self] in self?.redrawAll() }
        SettingsStore.shared.onHideDesktopIconsChanged = { [weak self] hide in
            self?.applyDesktopIconHiding(hide)
        }
        syncWindows()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        adoptCurrentDisplayForUnpinnedBins()
        recordLayoutForCurrentConfigurationIfNew()
        // Bring existing items in line with the setting: dropping an item is
        // not the only way one can end up in a bin, and the setting may have
        // been changed while the app was not running.
        applyDesktopIconHiding(SettingsStore.shared.hideDesktopIcons)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Display changes arrive as a burst of notifications, so the response is
    /// coalesced before the new arrangement is recorded.
    @objc private func screenConfigurationChanged() {
        syncWindows()
        screenSettleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncWindows()
            self.recordLayoutForCurrentConfigurationIfNew()
        }
        screenSettleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - Windows

    func syncWindows() {
        let currentIDs = Set(store.bins.map(\.id))
        for (id, window) in windows where !currentIDs.contains(id) {
            window.close()
            windows.removeValue(forKey: id)
        }

        for bin in store.bins {
            let window: BinPanelWindow
            if let existing = windows[bin.id] {
                window = existing
                (window.contentView as? BinPanelView)?.bin = bin
            } else {
                window = makeWindow(for: bin)
                windows[bin.id] = window
            }

            let frame = frameOf(bin)
            window.setFrame(frame, display: true)
            window.contentView?.frame = NSRect(origin: .zero, size: frame.size)
            window.contentView?.needsDisplay = true
            if isVisible { window.orderFront(nil) }
        }
    }

    private func makeWindow(for bin: Bin) -> BinPanelWindow {
        let frame = frameOf(bin)
        let window = BinPanelWindow(contentRect: frame)
        let view = BinPanelView(bin: bin)
        view.delegate = self
        view.frame = NSRect(origin: .zero, size: frame.size)
        window.contentView = view
        return window
    }

    private func redrawAll() {
        for window in windows.values {
            window.contentView?.needsDisplay = true
        }
    }

    private func view(for id: UUID) -> BinPanelView? {
        windows[id]?.contentView as? BinPanelView
    }

    /// Pushes a changed bin into both the store and the on-screen view.
    private func commit(_ bin: Bin) {
        store.updateBin(bin)
        view(for: bin.id)?.bin = bin
    }

    // MARK: - Display placement

    /// A panel whose display is absent is shown on the main display rather
    /// than vanishing — plugging into a different set of monitors should not
    /// look like the panels were lost. Its stored pin is left alone so it
    /// returns home when its own display comes back; it is only re-pinned if
    /// the user actually moves it.
    private func frameOf(_ bin: Bin) -> NSRect {
        // A layout remembered for this exact set of monitors wins, so
        // returning to a previous setup restores that arrangement.
        let signature = DisplayIdentity.configurationSignature()
        if let placement = bin.layouts[signature],
           let screen = DisplayIdentity.screen(withUUID: placement.displayUUID) {
            return NSRect(
                x: screen.frame.origin.x + CGFloat(placement.relativeX),
                y: screen.frame.origin.y + CGFloat(placement.relativeY),
                width: placement.width,
                height: placement.height
            )
        }

        if let uuid = bin.displayUUID, let screen = DisplayIdentity.screen(withUUID: uuid) {
            return NSRect(
                x: screen.frame.origin.x + CGFloat(bin.relativeX ?? 0),
                y: screen.frame.origin.y + CGFloat(bin.relativeY ?? 0),
                width: bin.width,
                height: bin.height
            )
        }

        let stored = NSRect(x: bin.x, y: bin.y, width: bin.width, height: bin.height)
        guard bin.displayUUID != nil, let fallback = mainScreen() else { return stored }

        // Offsets from a bigger monitor can land far outside a laptop screen,
        // so fit the panel to whatever display is actually available.
        let relative = NSRect(
            x: fallback.frame.origin.x + CGFloat(bin.relativeX ?? 0),
            y: fallback.frame.origin.y + CGFloat(bin.relativeY ?? 0),
            width: bin.width,
            height: bin.height
        )
        return clamp(relative, into: fallback.visibleFrame)
    }

    private func mainScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func clamp(_ frame: NSRect, into bounds: NSRect) -> NSRect {
        let width = min(frame.width, bounds.width)
        let height = min(frame.height, bounds.height)
        let x = min(max(frame.origin.x, bounds.minX), bounds.maxX - width)
        let y = min(max(frame.origin.y, bounds.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Emergency escape hatch: gathers every panel onto the main display and
    /// re-pins it there, for when panels are stranded on a monitor that no
    /// longer exists.
    @discardableResult
    func consolidateBinsToMainDisplay() -> Int {
        guard let screen = mainScreen() else { return 0 }
        let bounds = screen.visibleFrame
        let padding: CGFloat = 20
        var cursor = NSPoint(x: bounds.minX + padding, y: bounds.maxY - padding)
        var rowHeight: CGFloat = 0
        var moved = 0

        for var bin in store.bins {
            let width = min(CGFloat(bin.width), bounds.width - 2 * padding)
            let height = min(CGFloat(bin.height), bounds.height - 2 * padding)

            // Tile left to right, wrapping to a new row when out of width.
            if cursor.x + width > bounds.maxX - padding {
                cursor.x = bounds.minX + padding
                cursor.y -= rowHeight + padding
                rowHeight = 0
            }
            if cursor.y - height < bounds.minY + padding {
                cursor = NSPoint(x: bounds.minX + padding, y: bounds.maxY - padding)
                rowHeight = 0
            }

            let frame = NSRect(x: cursor.x, y: cursor.y - height, width: width, height: height)
            pinToDisplay(&bin, frame: frame)
            store.updateBin(bin)

            cursor.x += width + padding
            rowHeight = max(rowHeight, height)
            moved += 1
        }

        syncWindows()
        return moved
    }

    private func pinToDisplay(_ bin: inout Bin, frame: NSRect) {
        bin.x = Double(frame.origin.x)
        bin.y = Double(frame.origin.y)
        bin.width = Double(frame.width)
        bin.height = Double(frame.height)

        guard let screen = DisplayIdentity.screen(containing: frame),
              let uuid = DisplayIdentity.uuid(for: screen) else {
            bin.displayUUID = nil
            bin.relativeX = nil
            bin.relativeY = nil
            return
        }
        bin.displayUUID = uuid
        bin.relativeX = Double(frame.origin.x - screen.frame.origin.x)
        bin.relativeY = Double(frame.origin.y - screen.frame.origin.y)

        // Remember this arrangement against the current set of monitors.
        bin.layouts[DisplayIdentity.configurationSignature()] = BinPlacement(
            displayUUID: uuid,
            relativeX: Double(frame.origin.x - screen.frame.origin.x),
            relativeY: Double(frame.origin.y - screen.frame.origin.y),
            width: Double(frame.width),
            height: Double(frame.height)
        )
    }

    /// Records where each bin ended up under a set of monitors we have not
    /// seen before, so this arrangement becomes the one restored next time.
    private func recordLayoutForCurrentConfigurationIfNew() {
        let signature = DisplayIdentity.configurationSignature()
        guard signature != "none" else { return }
        for bin in store.bins where bin.layouts[signature] == nil {
            var updated = bin
            pinToDisplay(&updated, frame: frameOf(bin))
            store.updateBin(updated)
        }
    }

    private func adoptCurrentDisplayForUnpinnedBins() {
        for var bin in store.bins where bin.displayUUID == nil {
            pinToDisplay(&bin, frame: NSRect(x: bin.x, y: bin.y, width: bin.width, height: bin.height))
            if bin.displayUUID != nil { store.updateBin(bin) }
        }
    }

    // MARK: - Bin lifecycle

    func addBinAtCenterOfMainScreen() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 320, height: 260)
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let colors = ["3B82F6", "10B981", "F59E0B", "EF4444", "8B5CF6", "EC4899"]
        var bin = Bin(
            title: "New Bin",
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.width),
            height: Double(frame.height),
            colorHex: colors[store.bins.count % colors.count]
        )
        pinToDisplay(&bin, frame: frame)
        store.addBin(bin)
    }

    func setAllVisible(_ visible: Bool) {
        isVisible = visible
        for window in windows.values {
            visible ? window.orderFront(nil) : window.orderOut(nil)
        }
    }

    /// Drops items whose underlying file no longer exists, across all bins.
    @discardableResult
    func removeMissingItems() -> Int {
        var removed = 0
        for var bin in store.bins {
            let before = bin.items.count
            bin.items.removeAll { $0.isMissing }
            removed += before - bin.items.count
            if bin.items.count != before { commit(bin) }
        }
        return removed
    }


    // MARK: - Hiding desktop icons

    /// Once an item lives in a bin, its desktop icon is redundant, so the
    /// file is marked hidden and Finder stops drawing it on the desktop.
    ///
    /// Only files sitting directly on the Desktop are touched: hiding an item
    /// dragged in from Documents would make it vanish from a folder the user
    /// is actively browsing, which is not what they asked for. Nothing is
    /// moved or renamed, so the change is undone by simply clearing the flag.
    private func isOnDesktop(_ url: URL) -> Bool {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return false }
        return url.deletingLastPathComponent().resolvingSymlinksInPath().path
            == desktop.resolvingSymlinksInPath().path
    }

    @discardableResult
    private func setHidden(_ url: URL, _ hidden: Bool) -> Bool {
        var target = url
        var values = URLResourceValues()
        values.isHidden = hidden
        do {
            try target.setResourceValues(values)
            return true
        } catch {
            NSLog("DesktopBinsWidget: could not \(hidden ? "hide" : "unhide") \(url.lastPathComponent): \(error)")
            return false
        }
    }

    /// Hides an item's desktop icon if the setting allows it, recording that
    /// we were the ones who hid it.
    private func hideDesktopIconIfNeeded(_ item: inout BinItem) {
        guard SettingsStore.shared.hideDesktopIcons, !item.didHideOriginal,
              let url = item.resolveURL(), isOnDesktop(url) else { return }
        if setHidden(url, true) { item.didHideOriginal = true }
    }

    /// Puts back anything this app hid — used when an item leaves a bin, a
    /// bin is deleted, or the setting is turned off.
    private func restoreDesktopIcon(_ item: inout BinItem) {
        guard item.didHideOriginal, let url = item.resolveURL() else {
            item.didHideOriginal = false
            return
        }
        setHidden(url, false)
        item.didHideOriginal = false
    }

    /// Applies the setting across every existing item, in both directions.
    @discardableResult
    func applyDesktopIconHiding(_ hide: Bool) -> Int {
        var changed = 0
        for var bin in store.bins {
            var items = bin.items
            for index in items.indices {
                let before = items[index].didHideOriginal
                if hide {
                    hideDesktopIconIfNeeded(&items[index])
                } else {
                    restoreDesktopIcon(&items[index])
                }
                if items[index].didHideOriginal != before { changed += 1 }
            }
            if items != bin.items {
                bin.items = items
                commit(bin)
            }
        }
        return changed
    }

    /// Safety valve: unhide everything, whatever the setting says.
    @discardableResult
    func restoreAllDesktopIcons() -> Int {
        applyDesktopIconHiding(false)
    }

    // MARK: - BinPanelViewDelegate

    func panelDidBeginGesture(_ view: BinPanelView, kind: BinPanelView.GestureKind) {
        gestureStartFrame = windows[view.bin.id]?.frame
    }

    func panel(_ view: BinPanelView, didDragBy delta: CGSize, kind: BinPanelView.GestureKind) {
        guard let window = windows[view.bin.id] else { return }
        let frame = window.frame

        switch kind {
        case .move:
            window.setFrameOrigin(NSPoint(x: frame.origin.x + delta.width, y: frame.origin.y + delta.height))
        case .resize:
            let width = max(minWidth, frame.width + delta.width)
            let height = max(minHeight, frame.height - delta.height)
            window.setFrame(
                NSRect(x: frame.origin.x, y: frame.maxY - height, width: width, height: height),
                display: true
            )
            window.contentView?.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            window.contentView?.needsDisplay = true
        }
    }

    func panelDidEndGesture(_ view: BinPanelView) {
        gestureStartFrame = nil
        guard var bin = store.bin(for: view.bin.id), let window = windows[bin.id] else { return }
        pinToDisplay(&bin, frame: window.frame)
        commit(bin)
    }

    func panelRequestsToggleCollapse(_ view: BinPanelView) {
        guard var bin = store.bin(for: view.bin.id), let window = windows[bin.id] else { return }
        let frame = window.frame
        bin.isCollapsed.toggle()

        let newHeight: CGFloat
        if bin.isCollapsed {
            expandedHeights[bin.id] = Double(frame.height)
            newHeight = WidgetMetrics.titleBarHeight
        } else {
            newHeight = CGFloat(expandedHeights[bin.id] ?? 260)
        }

        let newFrame = NSRect(x: frame.minX, y: frame.maxY - newHeight, width: frame.width, height: newHeight)
        pinToDisplay(&bin, frame: newFrame)
        window.setFrame(newFrame, display: true)
        window.contentView?.frame = NSRect(origin: .zero, size: newFrame.size)
        commit(bin)
    }

    func panel(_ view: BinPanelView, didDropURLs urls: [URL], atIndex index: Int) {
        guard var bin = store.bin(for: view.bin.id) else { return }
        // Ignore anything already held, so dropping twice doesn't duplicate.
        let existing = Set(bin.items.map(\.path))
        var newItems = urls
            .filter { !existing.contains($0.path) }
            .map { BinItem(url: $0) }
        guard !newItems.isEmpty else { return }
        for index in newItems.indices {
            hideDesktopIconIfNeeded(&newItems[index])
        }

        let insertAt = min(max(index, 0), bin.items.count)
        bin.items.insert(contentsOf: newItems, at: insertAt)
        commit(bin)
    }

    func panel(_ view: BinPanelView, didReorderFrom oldIndex: Int, to newIndex: Int) {
        guard var bin = store.bin(for: view.bin.id),
              bin.items.indices.contains(oldIndex) else { return }
        let item = bin.items.remove(at: oldIndex)
        bin.items.insert(item, at: min(max(newIndex, 0), bin.items.count))
        commit(bin)
    }

    func panel(_ view: BinPanelView, didOpenItemAt index: Int) {
        guard let bin = store.bin(for: view.bin.id), bin.items.indices.contains(index) else { return }
        guard let url = bin.items[index].resolveURL() else {
            presentMissingItemAlert(name: bin.items[index].displayName)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func presentMissingItemAlert(name: String) {
        let alert = NSAlert()
        alert.messageText = "“\(name)” can’t be found"
        alert.informativeText = "The file may have been deleted or moved to a location Desktop Bins Widget can't follow."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menus

    func panelContextMenu(_ view: BinPanelView, forItemAt index: Int?) -> NSMenu {
        let menu = NSMenu()
        let id = view.bin.id
        guard let bin = store.bin(for: id) else { return menu }

        if let index, bin.items.indices.contains(index) {
            let item = bin.items[index]
            menu.addItem(withActionTitle: "Open “\(item.displayName)”") { [weak self] in
                guard let self, let view = self.view(for: id) else { return }
                self.panel(view, didOpenItemAt: index)
            }
            menu.addItem(withActionTitle: "Reveal in Finder") { [weak self] in
                guard let url = self?.store.bin(for: id)?.items[safe: index]?.resolveURL() else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            menu.addItem(withActionTitle: "Remove from Bin") { [weak self] in
                guard let self, var bin = self.store.bin(for: id), bin.items.indices.contains(index) else { return }
                var removed = bin.items.remove(at: index)
                // Put the desktop icon back now that it has left the bin.
                self.restoreDesktopIcon(&removed)
                self.commit(bin)
            }
            menu.addItem(.separator())
        }

        menu.addItem(withActionTitle: bin.isCollapsed ? "Expand Bin" : "Collapse Bin") { [weak self] in
            guard let self, let view = self.view(for: id) else { return }
            self.panelRequestsToggleCollapse(view)
        }
        let countItem = menu.addItem(withActionTitle: "Show Item Count") { [weak self] in
            guard let self, var bin = self.store.bin(for: id) else { return }
            bin.showsItemCount.toggle()
            self.commit(bin)
        }
        countItem.state = bin.showsItemCount ? .on : .off
        menu.addItem(withActionTitle: "Rename Bin…") { [weak self] in self?.renameBin(id) }
        menu.addItem(withActionTitle: "Change Color…") { [weak self] in self?.changeColor(id) }
        menu.addItem(.separator())
        menu.addItem(withActionTitle: "Delete Bin") { [weak self] in self?.deleteBin(id) }
        return menu
    }

    private func renameBin(_ id: UUID) {
        guard var bin = store.bin(for: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Bin"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = bin.title
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        bin.title = trimmed.isEmpty ? bin.title : trimmed
        commit(bin)
    }

    private var colorTargetID: UUID?

    private func changeColor(_ id: UUID) {
        guard let bin = store.bin(for: id) else { return }
        colorTargetID = id
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.color = NSColor(hex: bin.colorHex)
        panel.isContinuous = true
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        guard let id = colorTargetID, var bin = store.bin(for: id) else { return }
        bin.colorHex = sender.color.hexString
        commit(bin)
    }

    private func deleteBin(_ id: UUID) {
        guard let bin = store.bin(for: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(bin.title)”?"
        alert.informativeText = bin.items.isEmpty
            ? "This removes the bin."
            : "This removes the bin and its \(bin.items.count) shortcut(s). The original files are not deleted."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            // Deleting a bin must not leave its files hidden with no way back.
            if var doomed = store.bin(for: id) {
                for index in doomed.items.indices {
                    restoreDesktopIcon(&doomed.items[index])
                }
            }
            store.removeBin(id: id)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// Lets menu construction read linearly instead of via target/action selectors.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    @objc private func invoke() { handler() }
}

private extension NSMenu {
    @discardableResult
    func addItem(withActionTitle title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        addItem(item)
        return item
    }
}
