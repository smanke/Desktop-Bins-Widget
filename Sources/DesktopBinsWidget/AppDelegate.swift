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

        scheduleLaunchUpdateCheck()
    }

    /// Looks for a newer release shortly after launch rather than during it,
    /// so startup isn't waiting on the network. Silent unless there is
    /// something to offer.
    private func scheduleLaunchUpdateCheck() {
        guard SettingsStore.shared.checkForUpdatesAtLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            UpdateController.checkForUpdates(silent: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
