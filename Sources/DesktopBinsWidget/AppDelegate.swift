import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: BinStore!
    private var panelController: BinPanelController!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = BinStore()
        panelController = BinPanelController(store: store)
        statusItemController = StatusItemController(panelController: panelController)

        if store.bins.isEmpty {
            panelController.addBinAtCenterOfMainScreen()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
