import Cocoa

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var shortcutItem: NSMenuItem!
    private var commandShortcutItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var historyParentItem: NSMenuItem!
    private let openSettings: () -> Void
    private let openHistory: () -> Void

    init(openSettings: @escaping () -> Void, openHistory: @escaping () -> Void) {
        self.openSettings = openSettings
        self.openHistory = openHistory
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceType")
        }

        menu.addItem(withTitle: "VoiceType", action: nil, keyEquivalent: "").isEnabled = false
        shortcutItem = menu.addItem(withTitle: "Dictate: \(AppSettings.shared.hotkeyDisplayString)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        commandShortcutItem = menu.addItem(withTitle: "Command: \(AppSettings.shared.commandHotkeyDisplayString)", action: nil, keyEquivalent: "")
        commandShortcutItem.isEnabled = false
        menu.addItem(.separator())

        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(didOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        let historyItem = menu.addItem(withTitle: "History…", action: #selector(didOpenHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(.separator())

        historyMenu = NSMenu()
        historyParentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        historyParentItem.submenu = historyMenu
        menu.addItem(historyParentItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit VoiceType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        NotificationCenter.default.addObserver(self, selector: #selector(rebuildHistory), name: .historyDidUpdate, object: nil)
        refreshShortcut()
    }

    func refreshShortcut() {
        shortcutItem.title = "Dictate: \(AppSettings.shared.hotkeyDisplayString)"
        commandShortcutItem.title = "Command: \(AppSettings.shared.commandHotkeyDisplayString)"
        statusItem.button?.toolTip = "VoiceType — Dictate \(AppSettings.shared.hotkeyDisplayString) • Command \(AppSettings.shared.commandHotkeyDisplayString)"
        rebuildHistory()
    }

    @objc private func rebuildHistory() {
        historyMenu.removeAllItems()
        let items = Array(TranscriptionHistory.shared.items.prefix(8))
        guard !items.isEmpty else {
            let empty = NSMenuItem(title: "No recent transcriptions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
            historyParentItem.isEnabled = false
            return
        }

        historyParentItem.isEnabled = true
        for item in items {
            let menuItem = NSMenuItem(title: "\(item.preview) — \(item.timeString)", action: #selector(didSelectHistory(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.text
            historyMenu.addItem(menuItem)
        }
        historyMenu.addItem(.separator())
        let open = NSMenuItem(title: "Open Full History…", action: #selector(didOpenHistory), keyEquivalent: "")
        open.target = self
        historyMenu.addItem(open)
    }

    @objc private func didOpenSettings() { openSettings() }
    @objc private func didOpenHistory() { openHistory() }

    @objc private func didSelectHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        TextInjector.copyToPasteboard(text)
    }
}

extension Notification.Name {
    static let historyDidUpdate = Notification.Name("VoiceTypeHistoryDidUpdate")
}
