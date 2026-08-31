import Cocoa

class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var shortcutItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var historyParentItem: NSMenuItem!
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoiceType")
            btn.toolTip = "VoiceType — \(AppSettings.shared.hotkeyDisplayString)  •  Hold to talk \(AppSettings.shared.holdToTalkEnabled ? "on" : "off")"
        }
        menu.addItem(withTitle: "VoiceType", action: nil, keyEquivalent: "").isEnabled = false
        shortcutItem = menu.addItem(withTitle: "Shortcut: \(AppSettings.shared.hotkeyDisplayString)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(didOpenSettings), keyEquivalent: ",")
        settingsItem.target = self

        // History submenu
        historyMenu = NSMenu()
        historyParentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        historyParentItem.submenu = historyMenu
        menu.addItem(historyParentItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit VoiceType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        rebuildHistory()

        // Observe history adds via notification
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildHistory), name: .historyDidUpdate, object: nil)
    }

    func refreshShortcut() {
        shortcutItem.title = "Shortcut: \(AppSettings.shared.hotkeyDisplayString)"
        statusItem.button?.toolTip = "VoiceType — \(AppSettings.shared.hotkeyDisplayString)  •  Hold to talk \(AppSettings.shared.holdToTalkEnabled ? "on" : "off")"
        // history parent enabled state depends on items
        rebuildHistory()
    }

    @objc func rebuildHistory() {
        historyMenu.removeAllItems()
        let items = TranscriptionHistory.shared.items
        if items.isEmpty {
            let empty = NSMenuItem(title: "No recent transcriptions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
            historyParentItem.isEnabled = false
        } else {
            historyParentItem.isEnabled = true
            for item in items {
                let title = "\(item.preview)  —  \(item.timeString)"
                let mi = NSMenuItem(title: title, action: #selector(didSelectHistory(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.text
                // small monospaced tweak not needed; keep simple
                historyMenu.addItem(mi)
            }
            historyMenu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear History", action: #selector(didClearHistory), keyEquivalent: "")
            clear.target = self
            historyMenu.addItem(clear)
            let copyLast = NSMenuItem(title: "Copy Last to Clipboard", action: #selector(didCopyLast), keyEquivalent: "")
            copyLast.target = self
            historyMenu.insertItem(copyLast, at: 0)
            historyMenu.insertItem(.separator(), at: 1)
        }
    }

    @objc private func didOpenSettings() {
        openSettings()
    }

    @objc private func didSelectHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        // subtle feedback via tooltip flash could be added
    }

    @objc private func didClearHistory() {
        TranscriptionHistory.shared.clear()
        rebuildHistory()
    }

    @objc private func didCopyLast() {
        guard let last = TranscriptionHistory.shared.items.first?.text else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(last, forType: .string)
    }
}

extension Notification.Name {
    static let historyDidUpdate = Notification.Name("VoiceTypeHistoryDidUpdate")
}
