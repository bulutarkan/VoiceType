import Cocoa

final class SettingsWindowController: NSWindowController {
    var onShortcutChanged: (() -> Void)?
    var onAPIKeyChanged: (() -> Void)?

    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let apiKeyField = NSSecureTextField()
    private let saveAPIKeyButton = NSButton(title: "Save", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let holdToTalkToggle = NSButton(checkboxWithTitle: "Hold to talk — keep shortcut pressed to record, release to send", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "")
    private var keyMonitor: Any?
    private var isRecordingShortcut = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceType Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.appearance = NSAppearance(named: .vibrantDark)
        setupView()
        refreshShortcut()
        refreshHoldToggle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshShortcut()
        refreshHoldToggle()
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    override func close() {
        stopRecordingShortcut()
        super.close()
        NSApp.setActivationPolicy(.accessory)
    }

    private func setupView() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Shortcut section
        let title = NSTextField(labelWithString: "Shortcut")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 28, y: 312, width: 200, height: 20)
        contentView.addSubview(title)

        let description = NSTextField(labelWithString: "Global shortcut to show / hide the VoiceType recording panel.")
        description.font = .systemFont(ofSize: 11, weight: .regular)
        description.textColor = .secondaryLabelColor
        description.frame = NSRect(x: 28, y: 294, width: 444, height: 16)
        contentView.addSubview(description)

        shortcutButton.target = self
        shortcutButton.action = #selector(startRecordingShortcut)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        shortcutButton.frame = NSRect(x: 28, y: 250, width: 200, height: 34)
        shortcutButton.focusRingType = .none
        contentView.addSubview(shortcutButton)

        hintLabel.stringValue = ""
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = NSRect(x: 240, y: 258, width: 232, height: 18)
        contentView.addSubview(hintLabel)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 28, y: 228, width: 444, height: 16)
        contentView.addSubview(statusLabel)

        // Hold-to-talk toggle
        holdToTalkToggle.target = self
        holdToTalkToggle.action = #selector(toggleHoldToTalk)
        holdToTalkToggle.font = .systemFont(ofSize: 12, weight: .regular)
        holdToTalkToggle.frame = NSRect(x: 28, y: 200, width: 444, height: 18)
        holdToTalkToggle.state = AppSettings.shared.holdToTalkEnabled ? .on : .off
        contentView.addSubview(holdToTalkToggle)

        let holdHint = NSTextField(labelWithString: "When on, press and hold the shortcut to record. Release to transcribe and paste. Press Esc to cancel.")
        holdHint.font = .systemFont(ofSize: 10.5, weight: .regular)
        holdHint.textColor = .tertiaryLabelColor
        holdHint.frame = NSRect(x: 28, y: 184, width: 444, height: 14)
        contentView.addSubview(holdHint)

        // Divider
        let divider = NSBox(frame: NSRect(x: 28, y: 166, width: 444, height: 1))
        divider.boxType = .separator
        contentView.addSubview(divider)

        // Groq API section
        let apiTitle = NSTextField(labelWithString: "Groq API Key")
        apiTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        apiTitle.frame = NSRect(x: 28, y: 136, width: 220, height: 20)
        contentView.addSubview(apiTitle)

        let apiDesc = NSTextField(labelWithString: "Get a free key at console.groq.com — whisper-large-v3-turbo is used.")
        apiDesc.font = .systemFont(ofSize: 11)
        apiDesc.textColor = .secondaryLabelColor
        apiDesc.frame = NSRect(x: 28, y: 120, width: 444, height: 14)
        contentView.addSubview(apiDesc)

        apiKeyField.placeholderString = "gsk_..."
        apiKeyField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        apiKeyField.frame = NSRect(x: 28, y: 76, width: 360, height: 28)
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        apiKeyField.focusRingType = .none
        contentView.addSubview(apiKeyField)

        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKey)
        saveAPIKeyButton.bezelStyle = .rounded
        saveAPIKeyButton.font = .systemFont(ofSize: 13, weight: .medium)
        saveAPIKeyButton.frame = NSRect(x: 398, y: 76, width: 74, height: 28)
        saveAPIKeyButton.keyEquivalent = "\r"
        contentView.addSubview(saveAPIKeyButton)

        let footer = NSTextField(labelWithString: "Transcript is always copied to clipboard. Grant Accessibility permission to auto-paste.")
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor
        footer.frame = NSRect(x: 28, y: 28, width: 444, height: 14)
        contentView.addSubview(footer)
    }

    private func refreshShortcut() {
        shortcutButton.title = AppSettings.shared.hotkeyDisplayString
        statusLabel.stringValue = "Click the button above to change the shortcut."
        hintLabel.stringValue = AppSettings.shared.holdToTalkEnabled ? "Hold to talk enabled" : "Toggle mode"
    }

    private func refreshHoldToggle() {
        holdToTalkToggle.state = AppSettings.shared.holdToTalkEnabled ? .on : .off
        hintLabel.stringValue = AppSettings.shared.holdToTalkEnabled ? "Hold to talk enabled" : "Toggle mode"
    }

    @objc private func toggleHoldToTalk() {
        AppSettings.shared.holdToTalkEnabled = holdToTalkToggle.state == .on
        hintLabel.stringValue = AppSettings.shared.holdToTalkEnabled ? "Hold to talk enabled" : "Toggle mode"
        onShortcutChanged?()
    }

    @objc private func startRecordingShortcut() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutButton.title = "Press new shortcut…"
        statusLabel.stringValue = "Press any key with at least one modifier (⌘, ⌥, ⌃, ⇧). Press Esc to cancel."
        hintLabel.stringValue = "Listening…"

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleShortcutEvent(event)
            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        isRecordingShortcut = false
    }

    private func handleShortcutEvent(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecordingShortcut()
            refreshShortcut()
            return
        }

        let modifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            statusLabel.stringValue = "Please include at least one modifier: ⌘, ⌥, ⌃, or ⇧."
            return
        }

        AppSettings.shared.hotkeyKeyCode = UInt32(event.keyCode)
        AppSettings.shared.hotkeyModifiers = modifiers
        stopRecordingShortcut()
        refreshShortcut()
        onShortcutChanged?()
    }

    @objc private func saveAPIKey() {
        AppSettings.shared.groqAPIKey = apiKeyField.stringValue
        onAPIKeyChanged?()
        statusLabel.stringValue = "API key saved."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.statusLabel.stringValue = "Click the button above to change the shortcut."
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopRecordingShortcut()
        NSApp.setActivationPolicy(.accessory)
    }
}
