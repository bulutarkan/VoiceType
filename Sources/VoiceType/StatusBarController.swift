import Cocoa

class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var shortcutItem: NSMenuItem!
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceType")
            btn.toolTip = "VoiceType — \(AppSettings.shared.hotkeyDisplayString)"
        }
        menu.addItem(withTitle: "VoiceType", action: nil, keyEquivalent: "").isEnabled = false
        shortcutItem = menu.addItem(withTitle: "Kısayol: \(AppSettings.shared.hotkeyDisplayString)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: "Ayarlar...", action: #selector(didOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func refreshShortcut() {
        shortcutItem.title = "Kısayol: \(AppSettings.shared.hotkeyDisplayString)"
        statusItem.button?.toolTip = "VoiceType — \(AppSettings.shared.hotkeyDisplayString)"
    }

    @objc private func didOpenSettings() {
        openSettings()
    }
}
