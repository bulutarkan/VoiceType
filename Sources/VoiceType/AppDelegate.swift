import Cocoa
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var hotkeyManager: HotkeyManager!
    private var panelController: PanelController!
    private var settingsWindowController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        GroqTranscriptionService.shared.apiKey = AppSettings.shared.groqAPIKey
        panelController = PanelController()
        settingsWindowController = SettingsWindowController()
        settingsWindowController.onAPIKeyChanged = {
            GroqTranscriptionService.shared.apiKey = AppSettings.shared.groqAPIKey
        }
        statusBarController = StatusBarController { [weak self] in
            self?.settingsWindowController.show()
        }
        hotkeyManager = HotkeyManager { [weak self] in
            DispatchQueue.main.async {
                if self?.panelController.isVisible == true {
                    self?.panelController.hide()
                } else {
                    self?.panelController.show()
                }
            }
        }
        settingsWindowController.onShortcutChanged = { [weak self] in
            self?.hotkeyManager.updateShortcut()
            self?.statusBarController.refreshShortcut()
        }
        hotkeyManager.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
    }
}
