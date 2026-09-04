import AppKit

/// A borderless panel pinned to the desktop layer.
///
/// This can be one ordinary interactive window, unlike Desktop Bins, which
/// had to split each bin across two window levels to stay both visible
/// behind desktop icons and clickable. Since the panel owns its contents
/// there is nothing underneath it that needs to stay reachable.
final class BinPanelWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Above the desktop icon layer so it receives clicks, but below every
        // ordinary window so it never covers real work.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
