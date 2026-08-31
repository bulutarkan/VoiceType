import Cocoa

final class SettingsWindowController: NSWindowController {
    var onShortcutChanged: (() -> Void)?
    var onAPIKeyChanged: (() -> Void)?

    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let apiKeyField = NSSecureTextField()
    private let apiVisibleField = NSTextField()
    private let toggleVisibilityButton = NSButton()
    private let saveAPIKeyButton = NSButton(title: "Save", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let holdSwitch = NSSwitch()
    private let holdTitleLabel = NSTextField(labelWithString: "Hold to talk")
    private let holdDescLabel = NSTextField(labelWithString: "Hold shortcut to record, release to send")
    private var keyMonitor: Any?
    private var isRecordingShortcut = false
    private var isAPIKeyVisible = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceType"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        setupView()
        refreshShortcut()
        refreshHoldToggle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshShortcut()
        refreshHoldToggle()
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        apiVisibleField.stringValue = AppSettings.shared.groqAPIKey
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

    // MARK: - View

    private func setupView() {
        guard let contentView = window?.contentView else { return }

        // Root visual effect
        let effect = NSVisualEffectView(frame: contentView.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        contentView.addSubview(effect)

        // Header
        let headerH: CGFloat = 92
        let header = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - headerH, width: contentView.bounds.width, height: headerH))
        header.autoresizingMask = [.width, .minYMargin]
        effect.addSubview(header)

        // App icon (use bundled AppIcon or fallback SF)
        let iconView = NSImageView(frame: NSRect(x: 28, y: 20, width: 52, height: 52))
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            iconView.image = icon
        } else if let bundled = NSImage(named: "AppIcon") {
            iconView.image = bundled
        } else {
            iconView.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .white
        }
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 12
        iconView.layer?.masksToBounds = true
        header.addSubview(iconView)

        let title = NSTextField(labelWithString: "VoiceType")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 96, y: 46, width: 200, height: 24)
        header.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Global voice-to-text  •  macOS 14+")
        subtitle.font = .systemFont(ofSize: 11.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 96, y: 26, width: 260, height: 16)
        header.addSubview(subtitle)

        let version = NSTextField(labelWithString: "v1.0  •  Groq Whisper")
        version.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        version.textColor = .tertiaryLabelColor
        version.alignment = .right
        version.frame = NSRect(x: contentView.bounds.width - 170, y: 34, width: 140, height: 14)
        version.autoresizingMask = [.minXMargin]
        header.addSubview(version)

        // Divider under header
        let headerDivider = NSBox(frame: NSRect(x: 28, y: contentView.bounds.height - headerH, width: contentView.bounds.width - 56, height: 1))
        headerDivider.boxType = .separator
        headerDivider.autoresizingMask = [.width, .minYMargin]
        effect.addSubview(headerDivider)

        let cardW: CGFloat = 504
        let cardX: CGFloat = 28

        // MARK: Shortcut card — increased height to avoid crowding
        let shortcutCard = makeCard(frame: NSRect(x: cardX, y: 250, width: cardW, height: 164))
        effect.addSubview(shortcutCard)

        let sHeaderIcon = makeSymbol("keyboard", size: 11, tint: .secondaryLabelColor)
        shortcutCard.addSubview(sHeaderIcon)

        let sHeaderLabel = NSTextField(labelWithString: "SHORTCUT")
        sHeaderLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        sHeaderLabel.textColor = .secondaryLabelColor
        shortcutCard.addSubview(sHeaderLabel)

        let sTitle = NSTextField(labelWithString: "Global shortcut")
        sTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        sTitle.textColor = .labelColor
        shortcutCard.addSubview(sTitle)

        let sDesc = NSTextField(labelWithString: "Press to show the recording panel. Works in any app.")
        sDesc.font = .systemFont(ofSize: 11, weight: .regular)
        sDesc.textColor = .secondaryLabelColor
        shortcutCard.addSubview(sDesc)

        // Shortcut button — keycap style
        shortcutButton.target = self
        shortcutButton.action = #selector(startRecordingShortcut)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        shortcutButton.wantsLayer = true
        shortcutButton.layer?.cornerRadius = 8
        shortcutButton.layer?.borderWidth = 0.5
        shortcutButton.layer?.borderColor = NSColor.separatorColor.cgColor
        shortcutButton.focusRingType = .none
        shortcutCard.addSubview(shortcutButton)

        hintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = .secondaryLabelColor
        shortcutCard.addSubview(hintLabel)

        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .tertiaryLabelColor
        shortcutCard.addSubview(statusLabel)

        let holdDivider = NSBox(frame: NSRect.zero)
        holdDivider.boxType = .separator
        shortcutCard.addSubview(holdDivider)

        holdTitleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        holdTitleLabel.textColor = .labelColor
        shortcutCard.addSubview(holdTitleLabel)

        holdDescLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        holdDescLabel.textColor = .tertiaryLabelColor
        holdDescLabel.stringValue = "Release to transcribe and paste. Press Esc to cancel."
        shortcutCard.addSubview(holdDescLabel)

        holdSwitch.target = self
        holdSwitch.action = #selector(toggleHoldToTalk)
        holdSwitch.controlSize = .small
        holdSwitch.state = AppSettings.shared.holdToTalkEnabled ? .on : .off
        shortcutCard.addSubview(holdSwitch)

        // Layout — fixed non-overlapping coordinates
        sHeaderIcon.frame = NSRect(x: 20, y: 138, width: 14, height: 14)
        sHeaderLabel.frame = NSRect(x: 38, y: 137, width: 120, height: 14)
        sTitle.frame = NSRect(x: 20, y: 116, width: 320, height: 18)
        sDesc.frame = NSRect(x: 20, y: 98, width: 380, height: 14)
        shortcutButton.frame = NSRect(x: 20, y: 52, width: 196, height: 36)
        hintLabel.frame = NSRect(x: 228, y: 72, width: 256, height: 14)
        statusLabel.frame = NSRect(x: 228, y: 52, width: 256, height: 14)
        holdDivider.frame = NSRect(x: 20, y: 38, width: cardW - 40, height: 1)
        holdSwitch.frame = NSRect(x: cardW - 46, y: 14, width: 28, height: 18)
        holdTitleLabel.frame = NSRect(x: 20, y: 18, width: 200, height: 16)
        holdDescLabel.frame = NSRect(x: 20, y: 4, width: 380, height: 12)

        // MARK: API card
        let apiCard = makeCard(frame: NSRect(x: cardX, y: 86, width: cardW, height: 158))
        effect.addSubview(apiCard)

        let aHeaderIcon = makeSymbol("key.fill", size: 11, tint: .secondaryLabelColor)
        aHeaderIcon.frame = NSRect(x: 20, y: 128, width: 14, height: 14)
        apiCard.addSubview(aHeaderIcon)

        let aHeaderLabel = NSTextField(labelWithString: "TRANSCRIPTION")
        aHeaderLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        aHeaderLabel.textColor = .secondaryLabelColor
        aHeaderLabel.frame = NSRect(x: 38, y: 127, width: 140, height: 14)
        apiCard.addSubview(aHeaderLabel)

        let apiTitle = NSTextField(labelWithString: "Groq API key")
        apiTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        apiTitle.textColor = .labelColor
        apiTitle.frame = NSRect(x: 20, y: 104, width: 200, height: 18)
        apiCard.addSubview(apiTitle)

        let apiDesc = NSTextField(labelWithString: "Used for whisper-large-v3-turbo. Free at console.groq.com")
        apiDesc.font = .systemFont(ofSize: 11, weight: .regular)
        apiDesc.textColor = .secondaryLabelColor
        apiDesc.frame = NSRect(x: 20, y: 86, width: 340, height: 14)
        apiCard.addSubview(apiDesc)

        let link = NSButton(title: "Get free key →", target: self, action: #selector(openGroqConsole))
        link.bezelStyle = .inline
        link.font = .systemFont(ofSize: 11, weight: .medium)
        link.contentTintColor = .systemBlue
        link.frame = NSRect(x: 364, y: 86, width: 120, height: 14)
        link.isBordered = false
        apiCard.addSubview(link)

        // Fields
        apiKeyField.placeholderString = "gsk_..."
        apiKeyField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        apiKeyField.frame = NSRect(x: 20, y: 36, width: 364, height: 28)
        apiKeyField.focusRingType = .none
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        apiKeyField.wantsLayer = true
        apiKeyField.layer?.cornerRadius = 6
        apiCard.addSubview(apiKeyField)

        apiVisibleField.isHidden = true
        apiVisibleField.placeholderString = "gsk_..."
        apiVisibleField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        apiVisibleField.frame = NSRect(x: 20, y: 36, width: 364, height: 28)
        apiVisibleField.focusRingType = .none
        apiVisibleField.stringValue = AppSettings.shared.groqAPIKey
        apiVisibleField.wantsLayer = true
        apiVisibleField.layer?.cornerRadius = 6
        apiCard.addSubview(apiVisibleField)

        toggleVisibilityButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Show")
        toggleVisibilityButton.bezelStyle = .inline
        toggleVisibilityButton.isBordered = false
        toggleVisibilityButton.contentTintColor = .secondaryLabelColor
        toggleVisibilityButton.target = self
        toggleVisibilityButton.action = #selector(toggleAPIKeyVisibility)
        toggleVisibilityButton.frame = NSRect(x: 390, y: 36, width: 28, height: 28)
        apiCard.addSubview(toggleVisibilityButton)

        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKey)
        saveAPIKeyButton.bezelStyle = .rounded
        saveAPIKeyButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        saveAPIKeyButton.frame = NSRect(x: 424, y: 36, width: 60, height: 28)
        saveAPIKeyButton.keyEquivalent = "\r"
        saveAPIKeyButton.wantsLayer = true
        saveAPIKeyButton.layer?.cornerRadius = 7
        apiCard.addSubview(saveAPIKeyButton)

        // Inline status inside API card at bottom
        let apiStatus = NSTextField(labelWithString: "Transcript is always copied to clipboard. Accessibility permission enables auto-paste.")
        apiStatus.font = .systemFont(ofSize: 10, weight: .regular)
        apiStatus.textColor = .tertiaryLabelColor
        apiStatus.frame = NSRect(x: 20, y: 12, width: 464, height: 12)
        apiCard.addSubview(apiStatus)

        // Footer
        let footer = NSTextField(labelWithString: "VoiceType keeps your audio only for transcription. Files are deleted after sending.")
        footer.font = .systemFont(ofSize: 10, weight: .regular)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center
        footer.frame = NSRect(x: 28, y: 22, width: 504, height: 12)
        effect.addSubview(footer)

        let footer2 = NSTextField(labelWithString: "Tip: Press Esc to cancel recording. Recent transcripts live in the menu bar → Recent.")
        footer2.font = .systemFont(ofSize: 10, weight: .regular)
        footer2.textColor = .tertiaryLabelColor
        footer2.alignment = .center
        footer2.frame = NSRect(x: 28, y: 8, width: 504, height: 12)
        effect.addSubview(footer2)
    }

    private func makeCard(frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.borderWidth = 0.5
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.cornerRadius = 12
        box.wantsLayer = true
        box.layer?.masksToBounds = false
        box.shadow = NSShadow()
        box.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.08)
        box.shadow?.shadowBlurRadius = 12
        box.shadow?.shadowOffset = NSSize(width: 0, height: 4)
        return box
    }

    private func makeSymbol(_ name: String, size: CGFloat, tint: NSColor) -> NSImageView {
        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        iv.contentTintColor = tint
        return iv
    }

    private func refreshShortcut() {
        shortcutButton.title = AppSettings.shared.hotkeyDisplayString
        statusLabel.stringValue = isRecordingShortcut ? "Listening for new shortcut…" : "Click to change"
        hintLabel.stringValue = AppSettings.shared.holdToTalkEnabled ? "Hold to talk enabled" : "Toggle mode"
        if isRecordingShortcut {
            shortcutButton.layer?.borderColor = NSColor.systemBlue.cgColor
            shortcutButton.layer?.borderWidth = 1.2
        } else {
            shortcutButton.layer?.borderColor = NSColor.separatorColor.cgColor
            shortcutButton.layer?.borderWidth = 0.5
        }
    }

    private func refreshHoldToggle() {
        holdSwitch.state = AppSettings.shared.holdToTalkEnabled ? .on : .off
        hintLabel.stringValue = AppSettings.shared.holdToTalkEnabled ? "Hold to talk enabled" : "Toggle mode"
    }

    @objc private func toggleHoldToTalk() {
        AppSettings.shared.holdToTalkEnabled = holdSwitch.state == .on
        hintLabel.stringValue = AppSettings.shared.holdToTalkEnabled ? "Hold to talk enabled" : "Toggle mode"
        onShortcutChanged?()
        // subtle haptic
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc private func startRecordingShortcut() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutButton.title = "Press new shortcut…"
        statusLabel.stringValue = "Include at least one modifier (⌘ ⌥ ⌃ ⇧). Esc to cancel."
        hintLabel.stringValue = "Listening…"
        refreshShortcut()

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
        refreshShortcut()
    }

    private func handleShortcutEvent(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecordingShortcut()
            return
        }
        let modifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            statusLabel.stringValue = "Add a modifier: ⌘, ⌥, ⌃, or ⇧"
            return
        }
        AppSettings.shared.hotkeyKeyCode = UInt32(event.keyCode)
        AppSettings.shared.hotkeyModifiers = modifiers
        stopRecordingShortcut()
        onShortcutChanged?()
    }

    @objc private func toggleAPIKeyVisibility() {
        isAPIKeyVisible.toggle()
        if isAPIKeyVisible {
            apiVisibleField.stringValue = apiKeyField.stringValue
            apiVisibleField.isHidden = false
            apiKeyField.isHidden = true
            toggleVisibilityButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Hide")
            apiVisibleField.becomeFirstResponder()
        } else {
            apiKeyField.stringValue = apiVisibleField.stringValue
            apiKeyField.isHidden = false
            apiVisibleField.isHidden = true
            toggleVisibilityButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Show")
            apiKeyField.becomeFirstResponder()
        }
    }

    @objc private func saveAPIKey() {
        let value = isAPIKeyVisible ? apiVisibleField.stringValue : apiKeyField.stringValue
        AppSettings.shared.groqAPIKey = value
        apiKeyField.stringValue = value
        apiVisibleField.stringValue = value
        onAPIKeyChanged?()
        statusLabel.stringValue = "API key saved ✓"
        hintLabel.stringValue = ""
        NSSound(named: .init("Tink"))?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.refreshShortcut()
        }
    }

    @objc private func openGroqConsole() {
        NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopRecordingShortcut()
        NSApp.setActivationPolicy(.accessory)
    }
}
