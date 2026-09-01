import Carbon
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var hotkeyManager: HotkeyManager!
    private var panelController: PanelController!
    private var settingsWindowController: SettingsWindowController!
    private var historyWindowController: HistoryWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        GroqTranscriptionService.shared.apiKey = AppSettings.shared.groqAPIKey

        panelController = PanelController()
        settingsWindowController = SettingsWindowController()
        historyWindowController = HistoryWindowController()

        settingsWindowController.onAPIKeyChanged = {
            GroqTranscriptionService.shared.apiKey = AppSettings.shared.groqAPIKey
        }
        settingsWindowController.onShortcutChanged = { [weak self] in
            self?.hotkeyManager.updateShortcuts()
            self?.statusBarController.refreshShortcut()
        }

        statusBarController = StatusBarController(
            openSettings: { [weak self] in self?.settingsWindowController.show() },
            openHistory: { [weak self] in self?.historyWindowController.show() }
        )

        hotkeyManager = HotkeyManager(
            onDictationPress: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if AppSettings.shared.holdToTalkEnabled {
                        if !self.panelController.isVisible { self.panelController.showDictation() }
                    } else {
                        if self.panelController.isVisible { self.panelController.hide() }
                        else { self.panelController.showDictation() }
                    }
                }
            },
            onDictationRelease: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if AppSettings.shared.holdToTalkEnabled,
                       self.panelController.isVisible,
                       self.panelController.purpose == .dictation,
                       !self.panelController.isTranscribing {
                        self.panelController.confirmFromHold()
                    }
                }
            },
            onCommandPress: { [weak self] in
                DispatchQueue.main.async {
                    self?.panelController.toggleCommandMode()
                }
            },
            onRecordingCancel: { [weak self] in
                DispatchQueue.main.async {
                    self?.panelController.cancelFromKeyboard()
                }
            },
            onRecordingConfirm: { [weak self] in
                DispatchQueue.main.async {
                    self?.panelController.confirmFromKeyboard()
                }
            }
        )
        hotkeyManager.register()
        panelController.onRecordingControlsChanged = { [weak self] active, enterEnabled in
            self?.hotkeyManager.setRecordingControlsActive(active, enterEnabled: enterEnabled)
        }

        // Useful for local verification and scripted smoke tests without changing normal menu-bar behavior.
        if CommandLine.arguments.contains("--settings") {
            settingsWindowController.show()
        } else if CommandLine.arguments.contains("--history") {
            historyWindowController.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
    }
}
