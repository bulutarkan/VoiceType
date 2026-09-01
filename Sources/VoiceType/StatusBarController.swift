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
            button.image = statusImage(named: "waveform", accessibilityDescription: "VoiceType")
        }

        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildHistory), name: .historyDidUpdate, object: nil)
        refreshShortcut()
    }

    private func buildMenu() {
        menu.removeAllItems()

        // Header view item — custom
        let headerItem = NSMenuItem()
        headerItem.view = makeHeaderView()
        menu.addItem(headerItem)

        menu.addItem(.separator())

        shortcutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        shortcutItem.view = makeShortcutRow(title: "Dictate", shortcut: AppSettings.shared.hotkeyDisplayString, symbol: "mic.fill")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        commandShortcutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        commandShortcutItem.view = makeShortcutRow(title: "Command", shortcut: AppSettings.shared.commandHotkeyDisplayString, symbol: "sparkles")
        commandShortcutItem.isEnabled = false
        menu.addItem(commandShortcutItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(didOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let historyItem = NSMenuItem(title: "History…", action: #selector(didOpenHistory), keyEquivalent: "h")
        historyItem.target = self
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(historyItem)

        // Quick actions row via menu items
        let quickCopy = NSMenuItem(title: "Copy Last Transcript", action: #selector(didCopyLast), keyEquivalent: "c")
        quickCopy.target = self
        quickCopy.keyEquivalentModifierMask = [.command, .shift]
        quickCopy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(quickCopy)

        menu.addItem(.separator())

        historyMenu = NSMenu()
        historyParentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        historyParentItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        historyParentItem.submenu = historyMenu
        menu.addItem(historyParentItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit VoiceType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeHeaderView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        let icon = NSImageView(frame: NSRect(x: 14, y: 14, width: 28, height: 28))
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let img = NSImage(contentsOf: url) {
            icon.image = img
        } else {
            icon.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)
        }
        icon.imageScaling = .scaleProportionallyDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 7
        icon.layer?.masksToBounds = true
        view.addSubview(icon)

        let title = NSTextField(labelWithString: "VoiceType")
        title.font = .systemFont(ofSize: 13.5, weight: .semibold)
        title.frame = NSRect(x: 52, y: 28, width: 140, height: 18)
        view.addSubview(title)

        let sub = NSTextField(labelWithString: "Fast dictation • Anywhere")
        sub.font = .systemFont(ofSize: 10.5, weight: .regular)
        sub.textColor = .secondaryLabelColor
        sub.frame = NSRect(x: 52, y: 12, width: 160, height: 14)
        view.addSubview(sub)

        let version = NSTextField(labelWithString: "v1.1")
        version.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        version.textColor = .tertiaryLabelColor
        version.alignment = .right
        version.frame = NSRect(x: 210, y: 20, width: 56, height: 14)
        view.addSubview(version)

        return view
    }

    private func makeShortcutRow(title: String, shortcut: String, symbol: String) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        let icon = NSImageView(frame: NSRect(x: 14, y: 6, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        icon.contentTintColor = .secondaryLabelColor
        view.addSubview(icon)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.frame = NSRect(x: 36, y: 6, width: 80, height: 16)
        view.addSubview(label)

        // pill for shortcut
        let pill = NSView(frame: .zero)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 6
        pill.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.separatorColor.cgColor
        let pillLabel = NSTextField(labelWithString: shortcut)
        pillLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        pillLabel.textColor = .secondaryLabelColor
        pillLabel.alignment = .center
        pill.addSubview(pillLabel)
        view.addSubview(pill)

        // size pill
        let textSize = (shortcut as NSString).size(withAttributes: [.font: pillLabel.font!])
        let pw = max(56, textSize.width + 16)
        pill.frame = NSRect(x: 280 - pw - 12, y: 4, width: pw, height: 20)
        pillLabel.frame = NSRect(x: 0, y: 1, width: pw, height: 16)
        return view
    }

    func refreshShortcut() {
        // rebuild shortcut rows to reflect new shortcuts
        shortcutItem.view = makeShortcutRow(title: "Dictate", shortcut: AppSettings.shared.hotkeyDisplayString, symbol: "mic.fill")
        commandShortcutItem.view = makeShortcutRow(title: "Command", shortcut: AppSettings.shared.commandHotkeyDisplayString, symbol: "sparkles")
        statusItem.button?.toolTip = "VoiceType — Dictate \(AppSettings.shared.hotkeyDisplayString) • Command \(AppSettings.shared.commandHotkeyDisplayString)"
        rebuildHistory()
    }

    func setActivity(_ activity: PanelActivity) {
        guard let button = statusItem.button else { return }

        let symbol: String
        let description: String
        let tooltip: String
        switch activity {
        case .idle:
            symbol = "waveform"
            description = "VoiceType"
            tooltip = "VoiceType — Dictate \(AppSettings.shared.hotkeyDisplayString) • Command \(AppSettings.shared.commandHotkeyDisplayString)"
        case .recording:
            symbol = "waveform.circle.fill"
            description = "VoiceType is recording"
            tooltip = "VoiceType — Recording ●"
        case .processing:
            symbol = "ellipsis.circle"
            description = "VoiceType is processing"
            tooltip = "VoiceType — Transcribing"
        case .error:
            symbol = "exclamationmark.triangle"
            description = "VoiceType needs attention"
            tooltip = "VoiceType — Retry available"
        }

        button.image = statusImage(named: symbol, accessibilityDescription: description)
        button.toolTip = tooltip

        // subtle attention for error
        if activity == .error {
            button.contentTintColor = .systemRed
        } else if activity == .recording {
            button.contentTintColor = .systemRed.withAlphaComponent(0.92)
        } else {
            button.contentTintColor = nil
        }
    }

    private func statusImage(named symbol: String, accessibilityDescription: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    @objc private func rebuildHistory() {
        historyMenu.removeAllItems()
        let items = Array(TranscriptionHistory.shared.items.prefix(10))
        guard !items.isEmpty else {
            let empty = NSMenuItem(title: "No recent transcriptions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.image = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)
            historyMenu.addItem(empty)
            historyParentItem.isEnabled = false

            let hint = NSMenuItem(title: "Press \(AppSettings.shared.hotkeyDisplayString) to start", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            historyMenu.addItem(hint)
            return
        }

        historyParentItem.isEnabled = true
        for item in items {
            let title = "\(item.preview) — \(VTTime.relativeString(from: item.date))"
            let menuItem = NSMenuItem(title: title, action: #selector(didSelectHistory(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.text
            // icon by kind
            if item.kind == "command" {
                menuItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            } else {
                menuItem.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
            }
            menuItem.toolTip = item.text
            historyMenu.addItem(menuItem)
        }
        historyMenu.addItem(.separator())
        let open = NSMenuItem(title: "Open Full History…", action: #selector(didOpenHistory), keyEquivalent: "")
        open.target = self
        open.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        historyMenu.addItem(open)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(didClearHistory), keyEquivalent: "")
        clear.target = self
        clear.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        historyMenu.addItem(clear)
    }

    @objc private func didOpenSettings() { openSettings() }
    @objc private func didOpenHistory() { openHistory() }

    @objc private func didCopyLast() {
        guard let first = TranscriptionHistory.shared.items.first else {
            NSSound.beep()
            return
        }
        TextInjector.copyToPasteboard(first.text)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc private func didClearHistory() {
        guard !TranscriptionHistory.shared.items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear transcription history?"
        alert.informativeText = "This removes all saved transcript text from VoiceType on this Mac."
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        TranscriptionHistory.shared.clear()
    }

    @objc private func didSelectHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        TextInjector.copyToPasteboard(text)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

extension Notification.Name {
    static let historyDidUpdate = Notification.Name("VoiceTypeHistoryDidUpdate")
}
