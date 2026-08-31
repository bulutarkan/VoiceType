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
        hotkeyManager = HotkeyManager(
            onPress: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if AppSettings.shared.holdToTalkEnabled {
                        if !self.panelController.isVisible {
                            self.panelController.show()
                        }
                    } else {
                        if self.panelController.isVisible {
                            self.panelController.hide()
                        } else {
                            self.panelController.show()
                        }
                    }
                }
            },
            onRelease: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if AppSettings.shared.holdToTalkEnabled, self.panelController.isVisible, !self.panelController.isTranscribing {
                        self.panelController.confirmFromHold()
                    }
                }
            }
        )
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
