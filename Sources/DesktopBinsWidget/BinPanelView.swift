import AppKit

protocol BinPanelViewDelegate: AnyObject {
    func panelDidBeginGesture(_ view: BinPanelView, kind: BinPanelView.GestureKind)
    func panel(_ view: BinPanelView, didDragBy delta: CGSize, kind: BinPanelView.GestureKind)
    func panelDidEndGesture(_ view: BinPanelView)
    func panelRequestsToggleCollapse(_ view: BinPanelView)
    func panel(_ view: BinPanelView, didDropURLs urls: [URL], atIndex index: Int)
    func panel(_ view: BinPanelView, didReorderFrom oldIndex: Int, to newIndex: Int)
    func panel(_ view: BinPanelView, didOpenItemAt index: Int)
    func panelContextMenu(_ view: BinPanelView, forItemAt index: Int?) -> NSMenu
}

/// Draws a whole panel — title bar, item grid, resize grip — and handles all
/// of its input.
///
/// Because the panel owns its items, this is a single ordinary interactive
/// view: no splitting across window levels, no click-through, and no Finder
/// involvement. Items flow in list order, so the layout is inherently
/// gap-free.
final class BinPanelView: NSView {
    enum GestureKind {
        case move
        case resize
    }

    var bin: Bin {
        didSet { needsDisplay = true }
    }
    weak var delegate: BinPanelViewDelegate?

    private var dragMode: GestureKind?
    private var draggingItemIndex: Int?
    private var dragCurrentPoint: NSPoint?
    private var hoveredDropIndex: Int?
    private var pendingCommandPoint: NSPoint?
    private var isDropTarget = false

    init(bin: Bin) {
        self.bin = bin
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Geometry

    private var titleBarRect: NSRect {
        NSRect(x: 0, y: bounds.height - WidgetMetrics.titleBarHeight, width: bounds.width, height: WidgetMetrics.titleBarHeight)
    }

    private var resizeHandleRect: NSRect {
        NSRect(x: bounds.width - WidgetMetrics.resizeHandleSize, y: 0,
               width: WidgetMetrics.resizeHandleSize, height: WidgetMetrics.resizeHandleSize)
    }

    private var contentRect: NSRect {
        NSRect(x: WidgetMetrics.contentInset,
               y: WidgetMetrics.contentInset,
               width: bounds.width - 2 * WidgetMetrics.contentInset,
               height: bounds.height - WidgetMetrics.titleBarHeight - 2 * WidgetMetrics.contentInset)
    }

    private var columns: Int {
        let cell = SettingsStore.shared.cellWidth
        return max(1, Int(contentRect.width / CGFloat(cell)))
    }

    /// Frame of the cell at a given index, in view coordinates.
    private func cellFrame(at index: Int) -> NSRect {
        let settings = SettingsStore.shared
        let cellW = CGFloat(settings.cellWidth)
        let cellH = CGFloat(settings.cellHeight)
        let col = index % columns
        let row = index / columns
        return NSRect(
            x: contentRect.minX + CGFloat(col) * cellW,
            y: contentRect.maxY - CGFloat(row + 1) * cellH,
            width: cellW,
            height: cellH
        )
    }

    /// Index of the cell under a point, clamped into the valid insert range.
    private func insertionIndex(at point: NSPoint) -> Int {
        let settings = SettingsStore.shared
        let cellW = CGFloat(settings.cellWidth)
        let cellH = CGFloat(settings.cellHeight)
        guard cellW > 0, cellH > 0 else { return bin.items.count }

        let col = Int((point.x - contentRect.minX) / cellW)
        let row = Int((contentRect.maxY - point.y) / cellH)
        let index = max(0, row) * columns + min(max(col, 0), columns - 1)
        return min(max(index, 0), bin.items.count)
    }

    private func itemIndex(at point: NSPoint) -> Int? {
        for index in bin.items.indices where cellFrame(at: index).contains(point) {
            return index
        }
        return nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let settings = SettingsStore.shared
        let color = NSColor(hex: bin.colorHex)
        let path = NSBezierPath(roundedRect: bounds, xRadius: WidgetMetrics.cornerRadius, yRadius: WidgetMetrics.cornerRadius)

        color.withAlphaComponent(CGFloat(settings.panelOpacity) * 0.18).setFill()
        path.fill()

        if bin.isCollapsed {
            color.withAlphaComponent(CGFloat(settings.panelOpacity) * 0.65).setFill()
            path.fill()
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: titleBarRect).addClip()
            color.withAlphaComponent(CGFloat(settings.panelOpacity) * 0.65).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: WidgetMetrics.cornerRadius, yRadius: WidgetMetrics.cornerRadius).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        (isDropTarget ? NSColor.white : color.withAlphaComponent(0.9)).setStroke()
        path.lineWidth = isDropTarget ? 3 : 1.5
        path.stroke()

        drawTitle()

        guard !bin.isCollapsed else { return }

        if bin.items.isEmpty {
            drawEmptyState()
        } else {
            for index in bin.items.indices where index != draggingItemIndex {
                draw(item: bin.items[index], in: cellFrame(at: index))
            }
            drawDropIndicator()
            drawDraggedItem()
        }

        drawResizeGrip()
    }

    private func drawTitle() {
        let titleRect = bin.isCollapsed ? bounds : titleBarRect
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let inner = titleRect.insetBy(dx: 10, dy: 0)
        let textHeight = font.boundingRectForFont.height
        let count = (bin.showsItemCount && !bin.items.isEmpty) ? "  (\(bin.items.count))" : ""
        (bin.title + count).draw(
            in: NSRect(x: inner.minX, y: inner.midY - textHeight / 2, width: inner.width, height: textHeight),
            withAttributes: attrs
        )
    }

    private func drawEmptyState() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph
        ]
        let text = "Drag files or folders here"
        text.draw(in: NSRect(x: contentRect.minX, y: contentRect.midY - 8, width: contentRect.width, height: 16), withAttributes: attrs)
    }

    private func draw(item: BinItem, in cell: NSRect, alpha: CGFloat = 1.0) {
        let settings = SettingsStore.shared
        let iconSize = CGFloat(settings.iconSize)
        let labelSpace = settings.showLabels ? WidgetMetrics.labelHeight : 0

        let iconRect = NSRect(
            x: cell.midX - iconSize / 2,
            y: cell.maxY - iconSize - 6,
            width: iconSize,
            height: iconSize
        )
        let image = item.icon
        image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: item.isMissing ? 0.35 * alpha : alpha)

        guard settings.showLabels else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white.withAlphaComponent(item.isMissing ? 0.4 * alpha : alpha),
            .paragraphStyle: paragraph
        ]
        let labelRect = NSRect(x: cell.minX + 2, y: iconRect.minY - labelSpace + 6, width: cell.width - 4, height: labelSpace - 6)
        item.displayName.draw(in: labelRect, withAttributes: attrs)
    }

    /// Shows where a dragged or dropped item will land.
    private func drawDropIndicator() {
        guard let index = hoveredDropIndex else { return }
        let cell = cellFrame(at: min(index, max(bin.items.count - 1, 0)))
        let line = NSBezierPath(rect: NSRect(x: cell.minX - 2, y: cell.minY + 4, width: 3, height: cell.height - 8))
        NSColor.white.withAlphaComponent(0.85).setFill()
        line.fill()
    }

    private func drawDraggedItem() {
        guard let index = draggingItemIndex, let point = dragCurrentPoint, bin.items.indices.contains(index) else { return }
        let settings = SettingsStore.shared
        let cell = NSRect(
            x: point.x - CGFloat(settings.cellWidth) / 2,
            y: point.y - CGFloat(settings.cellHeight) / 2,
            width: CGFloat(settings.cellWidth),
            height: CGFloat(settings.cellHeight)
        )
        draw(item: bin.items[index], in: cell, alpha: 0.7)
    }

    private func drawResizeGrip() {
        guard !bin.isCollapsed else { return }
        let handle = resizeHandleRect.insetBy(dx: 5, dy: 5)
        let grip = NSBezierPath()
        grip.move(to: NSPoint(x: handle.minX, y: handle.minY))
        grip.line(to: NSPoint(x: handle.maxX, y: handle.minY))
        grip.line(to: NSPoint(x: handle.maxX, y: handle.maxY))
        NSColor.white.withAlphaComponent(0.7).setStroke()
        grip.lineWidth = 2
        grip.stroke()
    }

    // MARK: - Mouse

    override func resetCursorRects() {
        addCursorRect(titleBarRect, cursor: .openHand)
        if !bin.isCollapsed {
            addCursorRect(resizeHandleRect, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.command) {
            // When plain dragging is turned off, Command is what moves the
            // panel, so the menu has to wait until we know this was a click
            // and not the start of a drag.
            if SettingsStore.shared.requiresCommandToMove {
                pendingCommandPoint = point
                return
            }
            showMenu(at: point, itemIndex: itemIndex(at: point))
            return
        }

        if event.clickCount == 2 {
            if titleBarRect.contains(point) || bin.isCollapsed {
                delegate?.panelRequestsToggleCollapse(self)
                return
            }
            if let index = itemIndex(at: point) {
                delegate?.panel(self, didOpenItemAt: index)
                return
            }
        }

        if !bin.isCollapsed, resizeHandleRect.contains(point) {
            dragMode = .resize
            delegate?.panelDidBeginGesture(self, kind: .resize)
            return
        }

        if !bin.isCollapsed, let index = itemIndex(at: point) {
            draggingItemIndex = index
            dragCurrentPoint = point
            return
        }

        // With the setting checked, a bare drag must not move the panel —
        // Command-drag does instead.
        guard !SettingsStore.shared.requiresCommandToMove else { return }
        dragMode = .move
        delegate?.panelDidBeginGesture(self, kind: .move)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // A Command-press that turns into a drag is a move, not a menu.
        if let start = pendingCommandPoint {
            guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            pendingCommandPoint = nil
            dragMode = .move
            delegate?.panelDidBeginGesture(self, kind: .move)
        }

        if draggingItemIndex != nil {
            dragCurrentPoint = point
            hoveredDropIndex = insertionIndex(at: point)
            needsDisplay = true
            return
        }

        guard let dragMode else { return }
        delegate?.panel(self, didDragBy: CGSize(width: event.deltaX, height: -event.deltaY), kind: dragMode)
    }

    override func mouseUp(with event: NSEvent) {
        // A Command-press that never became a drag opens the menu.
        if let start = pendingCommandPoint {
            pendingCommandPoint = nil
            showMenu(at: start, itemIndex: itemIndex(at: start))
            return
        }

        if let from = draggingItemIndex {
            let point = convert(event.locationInWindow, from: nil)
            var to = insertionIndex(at: point)
            to = min(to, max(bin.items.count - 1, 0))
            draggingItemIndex = nil
            dragCurrentPoint = nil
            hoveredDropIndex = nil
            if to != from {
                delegate?.panel(self, didReorderFrom: from, to: to)
            }
            needsDisplay = true
            return
        }

        if dragMode != nil {
            dragMode = nil
            delegate?.panelDidEndGesture(self)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return delegate?.panelContextMenu(self, forItemAt: itemIndex(at: point))
    }

    private func showMenu(at point: NSPoint, itemIndex: Int?) {
        guard let menu = delegate?.panelContextMenu(self, forItemAt: itemIndex) else { return }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    // MARK: - Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTarget = !droppableURLs(from: sender).isEmpty
        needsDisplay = true
        return isDropTarget ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isDropTarget else { return [] }
        hoveredDropIndex = insertionIndex(at: convert(sender.draggingLocation, from: nil))
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
        hoveredDropIndex = nil
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppableURLs(from: sender)
        isDropTarget = false
        hoveredDropIndex = nil
        needsDisplay = true
        guard !urls.isEmpty else { return false }

        let index = insertionIndex(at: convert(sender.draggingLocation, from: nil))
        delegate?.panel(self, didDropURLs: urls, atIndex: index)
        return true
    }

    private func droppableURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
    }
}
