import AVFoundation
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
    private let holdDescLabel = NSTextField(labelWithString: "Release the shortcut to transcribe and paste.")

    private let microphonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let microphoneRefreshButton = NSButton()
    private let microphoneLevelView = MicrophoneLevelView(frame: .zero)
    private let microphoneStatusLabel = NSTextField(labelWithString: "Speak to test")
    private let microphoneLevelMonitor = MicrophoneLevelMonitor()

    private var keyMonitor: Any?
    private var isRecordingShortcut = false
    private var isAPIKeyVisible = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
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

        microphoneLevelMonitor.onLevel = { [weak self] level in
            self?.updateMicrophoneLevel(level)
        }

        setupView()
        refreshShortcut()
        refreshHoldToggle()
        refreshMicrophoneDevices()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshShortcut()
        refreshHoldToggle()
        refreshMicrophoneDevices()
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        apiVisibleField.stringValue = AppSettings.shared.groqAPIKey
        startMicrophonePreview()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    override func close() {
        stopRecordingShortcut()
        microphoneLevelMonitor.stop()
        super.close()
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - View

    private func setupView() {
        guard let contentView = window?.contentView else { return }

        let effect = NSVisualEffectView(frame: contentView.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        contentView.addSubview(effect)

        let headerH: CGFloat = 104
        let header = NSView(frame: NSRect(
            x: 0,
            y: contentView.bounds.height - headerH,
            width: contentView.bounds.width,
            height: headerH
        ))
        header.autoresizingMask = [.width, .minYMargin]
        effect.addSubview(header)

        let iconView = NSImageView(frame: NSRect(x: 32, y: 18, width: 58, height: 58))
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
        iconView.layer?.cornerRadius = 13
        iconView.layer?.masksToBounds = true
        header.addSubview(iconView)

        let title = NSTextField(labelWithString: "VoiceType")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 108, y: 50, width: 220, height: 28)
        header.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Global voice-to-text  •  macOS 14+")
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 108, y: 29, width: 300, height: 17)
        header.addSubview(subtitle)

        let version = NSTextField(labelWithString: "v1.0  •  Groq Whisper")
        version.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        version.textColor = .tertiaryLabelColor
        version.alignment = .right
        version.frame = NSRect(x: contentView.bounds.width - 190, y: 39, width: 158, height: 16)
        version.autoresizingMask = [.minXMargin]
        header.addSubview(version)

        let headerDivider = NSBox(frame: NSRect(
            x: 32,
            y: contentView.bounds.height - headerH,
            width: contentView.bounds.width - 64,
            height: 1
        ))
        headerDivider.boxType = .separator
        headerDivider.autoresizingMask = [.width, .minYMargin]
        effect.addSubview(headerDivider)

        let cardW: CGFloat = 536
        let cardX: CGFloat = 32

        setupShortcutCard(in: effect, frame: NSRect(x: cardX, y: 388, width: cardW, height: 176))
        setupMicrophoneCard(in: effect, frame: NSRect(x: cardX, y: 234, width: cardW, height: 142))
        setupAPICard(in: effect, frame: NSRect(x: cardX, y: 62, width: cardW, height: 160))

        let footer = NSTextField(labelWithString: "Audio is kept only long enough to transcribe, then the temporary file is deleted.")
        footer.font = .systemFont(ofSize: 10, weight: .regular)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center
        footer.frame = NSRect(x: 32, y: 28, width: 536, height: 13)
        effect.addSubview(footer)

        let footer2 = NSTextField(labelWithString: "Press Esc to cancel recording. Recent transcripts are available from the menu bar.")
        footer2.font = .systemFont(ofSize: 10, weight: .regular)
        footer2.textColor = .tertiaryLabelColor
        footer2.alignment = .center
        footer2.frame = NSRect(x: 32, y: 13, width: 536, height: 13)
        effect.addSubview(footer2)
    }

    private func setupShortcutCard(in parent: NSView, frame: NSRect) {
        let card = makeCard(frame: frame)
        parent.addSubview(card)

        let headerIcon = makeSymbol("keyboard", size: 11, tint: .secondaryLabelColor)
        headerIcon.frame = NSRect(x: 20, y: 148, width: 14, height: 14)
        card.addSubview(headerIcon)

        let headerLabel = NSTextField(labelWithString: "SHORTCUT")
        headerLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.frame = NSRect(x: 38, y: 147, width: 120, height: 14)
        card.addSubview(headerLabel)

        let title = NSTextField(labelWithString: "Global shortcut")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 20, y: 124, width: 320, height: 19)
        card.addSubview(title)

        let desc = NSTextField(labelWithString: "Open the recording panel from any app without changing focus.")
        desc.font = .systemFont(ofSize: 11, weight: .regular)
        desc.textColor = .secondaryLabelColor
        desc.frame = NSRect(x: 20, y: 105, width: 430, height: 15)
        card.addSubview(desc)

        shortcutButton.target = self
        shortcutButton.action = #selector(startRecordingShortcut)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        shortcutButton.wantsLayer = true
        shortcutButton.layer?.cornerRadius = 9
        shortcutButton.layer?.borderWidth = 0.5
        shortcutButton.layer?.borderColor = NSColor.separatorColor.cgColor
        shortcutButton.focusRingType = .none
        shortcutButton.frame = NSRect(x: 20, y: 58, width: 212, height: 38)
        card.addSubview(shortcutButton)

        hintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = NSRect(x: 248, y: 79, width: 268, height: 15)
        card.addSubview(hintLabel)

        statusLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.frame = NSRect(x: 248, y: 60, width: 268, height: 15)
        card.addSubview(statusLabel)

        let divider = NSBox(frame: NSRect(x: 20, y: 45, width: frame.width - 40, height: 1))
        divider.boxType = .separator
        card.addSubview(divider)

        holdTitleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        holdTitleLabel.textColor = .labelColor
        holdTitleLabel.frame = NSRect(x: 20, y: 23, width: 200, height: 17)
        card.addSubview(holdTitleLabel)

        holdDescLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        holdDescLabel.textColor = .tertiaryLabelColor
        holdDescLabel.frame = NSRect(x: 20, y: 7, width: 390, height: 14)
        card.addSubview(holdDescLabel)

        holdSwitch.target = self
        holdSwitch.action = #selector(toggleHoldToTalk)
        holdSwitch.controlSize = .small
        holdSwitch.state = AppSettings.shared.holdToTalkEnabled ? .on : .off
        holdSwitch.frame = NSRect(x: frame.width - 48, y: 14, width: 30, height: 20)
        card.addSubview(holdSwitch)
    }

    private func setupMicrophoneCard(in parent: NSView, frame: NSRect) {
        let card = makeCard(frame: frame)
        parent.addSubview(card)

        let headerIcon = makeSymbol("mic.fill", size: 11, tint: .secondaryLabelColor)
        headerIcon.frame = NSRect(x: 20, y: 114, width: 14, height: 14)
        card.addSubview(headerIcon)

        let headerLabel = NSTextField(labelWithString: "MICROPHONE")
        headerLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.frame = NSRect(x: 38, y: 113, width: 140, height: 14)
        card.addSubview(headerLabel)

        let title = NSTextField(labelWithString: "Input device")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 20, y: 90, width: 220, height: 19)
        card.addSubview(title)

        let desc = NSTextField(labelWithString: "Auto follows the current macOS default, or choose a system input manually.")
        desc.font = .systemFont(ofSize: 11, weight: .regular)
        desc.textColor = .secondaryLabelColor
        desc.frame = NSRect(x: 20, y: 71, width: 485, height: 15)
        card.addSubview(desc)

        microphonePopup.target = self
        microphonePopup.action = #selector(microphoneSelectionChanged)
        microphonePopup.controlSize = .small
        microphonePopup.font = .systemFont(ofSize: 11.5, weight: .regular)
        microphonePopup.frame = NSRect(x: 20, y: 30, width: 302, height: 30)
        card.addSubview(microphonePopup)

        microphoneRefreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh microphones")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        microphoneRefreshButton.bezelStyle = .inline
        microphoneRefreshButton.isBordered = false
        microphoneRefreshButton.contentTintColor = .secondaryLabelColor
        microphoneRefreshButton.target = self
        microphoneRefreshButton.action = #selector(refreshMicrophonesClicked)
        microphoneRefreshButton.frame = NSRect(x: 326, y: 31, width: 28, height: 28)
        card.addSubview(microphoneRefreshButton)

        let liveLabel = NSTextField(labelWithString: "LIVE INPUT")
        liveLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
        liveLabel.textColor = .tertiaryLabelColor
        liveLabel.frame = NSRect(x: 370, y: 52, width: 110, height: 13)
        card.addSubview(liveLabel)

        microphoneLevelView.frame = NSRect(x: 370, y: 35, width: 146, height: 14)
        card.addSubview(microphoneLevelView)

        microphoneStatusLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        microphoneStatusLabel.textColor = .tertiaryLabelColor
        microphoneStatusLabel.alignment = .left
        microphoneStatusLabel.frame = NSRect(x: 370, y: 17, width: 146, height: 13)
        card.addSubview(microphoneStatusLabel)

        let note = NSTextField(labelWithString: "Changes apply to the next recording immediately.")
        note.font = .systemFont(ofSize: 9.5, weight: .regular)
        note.textColor = .tertiaryLabelColor
        note.frame = NSRect(x: 20, y: 12, width: 315, height: 13)
        card.addSubview(note)
    }

    private func setupAPICard(in parent: NSView, frame: NSRect) {
        let card = makeCard(frame: frame)
        parent.addSubview(card)

        let headerIcon = makeSymbol("key.fill", size: 11, tint: .secondaryLabelColor)
        headerIcon.frame = NSRect(x: 20, y: 130, width: 14, height: 14)
        card.addSubview(headerIcon)

        let headerLabel = NSTextField(labelWithString: "TRANSCRIPTION")
        headerLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.frame = NSRect(x: 38, y: 129, width: 140, height: 14)
        card.addSubview(headerLabel)

        let apiTitle = NSTextField(labelWithString: "Groq API key")
        apiTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        apiTitle.textColor = .labelColor
        apiTitle.frame = NSRect(x: 20, y: 105, width: 220, height: 19)
        card.addSubview(apiTitle)

        let apiDesc = NSTextField(labelWithString: "Used for whisper-large-v3-turbo. Free at console.groq.com")
        apiDesc.font = .systemFont(ofSize: 11, weight: .regular)
        apiDesc.textColor = .secondaryLabelColor
        apiDesc.frame = NSRect(x: 20, y: 86, width: 350, height: 15)
        card.addSubview(apiDesc)

        let link = NSButton(title: "Get free key →", target: self, action: #selector(openGroqConsole))
        link.bezelStyle = .inline
        link.font = .systemFont(ofSize: 11, weight: .medium)
        link.contentTintColor = .systemBlue
        link.frame = NSRect(x: 388, y: 86, width: 128, height: 15)
        link.isBordered = false
        card.addSubview(link)

        apiKeyField.placeholderString = "gsk_..."
        apiKeyField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        apiKeyField.frame = NSRect(x: 20, y: 38, width: 390, height: 30)
        apiKeyField.focusRingType = .none
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        apiKeyField.wantsLayer = true
        apiKeyField.layer?.cornerRadius = 7
        card.addSubview(apiKeyField)

        apiVisibleField.isHidden = true
        apiVisibleField.placeholderString = "gsk_..."
        apiVisibleField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        apiVisibleField.frame = apiKeyField.frame
        apiVisibleField.focusRingType = .none
        apiVisibleField.stringValue = AppSettings.shared.groqAPIKey
        apiVisibleField.wantsLayer = true
        apiVisibleField.layer?.cornerRadius = 7
        card.addSubview(apiVisibleField)

        toggleVisibilityButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Show")
        toggleVisibilityButton.bezelStyle = .inline
        toggleVisibilityButton.isBordered = false
        toggleVisibilityButton.contentTintColor = .secondaryLabelColor
        toggleVisibilityButton.target = self
        toggleVisibilityButton.action = #selector(toggleAPIKeyVisibility)
        toggleVisibilityButton.frame = NSRect(x: 416, y: 39, width: 28, height: 28)
        card.addSubview(toggleVisibilityButton)

        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKey)
        saveAPIKeyButton.bezelStyle = .rounded
        saveAPIKeyButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        saveAPIKeyButton.frame = NSRect(x: 452, y: 38, width: 64, height: 30)
        saveAPIKeyButton.keyEquivalent = "\r"
        saveAPIKeyButton.wantsLayer = true
        saveAPIKeyButton.layer?.cornerRadius = 8
        card.addSubview(saveAPIKeyButton)

        let apiStatus = NSTextField(labelWithString: "Transcript is always copied to clipboard. Accessibility permission enables auto-paste.")
        apiStatus.font = .systemFont(ofSize: 9.8, weight: .regular)
        apiStatus.textColor = .tertiaryLabelColor
        apiStatus.frame = NSRect(x: 20, y: 14, width: 496, height: 13)
        card.addSubview(apiStatus)
    }

    private func makeCard(frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.borderWidth = 0.5
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor.withAlphaComponent(0.82)
        box.cornerRadius = 13
        box.wantsLayer = true
        box.layer?.masksToBounds = false
        box.shadow = NSShadow()
        box.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.09)
        box.shadow?.shadowBlurRadius = 14
        box.shadow?.shadowOffset = NSSize(width: 0, height: 5)
        return box
    }

    private func makeSymbol(_ name: String, size: CGFloat, tint: NSColor) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        imageView.contentTintColor = tint
        return imageView
    }

    // MARK: - Shortcut

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
        refreshHoldToggle()
        onShortcutChanged?()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc private func startRecordingShortcut() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutButton.title = "Press new shortcut…"
        statusLabel.stringValue = "Use at least one modifier (⌘ ⌥ ⌃ ⇧). Esc cancels."
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

    // MARK: - Microphone

    private func refreshMicrophoneDevices() {
        let devices = SystemAudioInput.devices()
        let defaultID = SystemAudioInput.defaultDeviceID()
        let selectedUID = AppSettings.shared.microphoneDeviceUID ?? ""

        microphonePopup.removeAllItems()
        microphonePopup.addItem(withTitle: "Auto — System Default")
        microphonePopup.lastItem?.representedObject = ""

        for device in devices {
            let suffix = device.id == defaultID ? "  • Default" : ""
            microphonePopup.addItem(withTitle: device.name + suffix)
            microphonePopup.lastItem?.representedObject = device.uid
        }

        if let index = microphonePopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String ?? "") == selectedUID
        }) {
            microphonePopup.selectItem(at: index)
        } else {
            microphonePopup.selectItem(at: 0)
            if !selectedUID.isEmpty {
                AppSettings.shared.microphoneDeviceUID = nil
            }
        }
    }

    private func startMicrophonePreview() {
        microphoneLevelMonitor.stop()
        microphoneLevelView.level = 0
        microphoneStatusLabel.textColor = .tertiaryLabelColor

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            do {
                try microphoneLevelMonitor.start(deviceUID: AppSettings.shared.microphoneDeviceUID)
                microphoneStatusLabel.stringValue = "Speak to test"
            } catch {
                microphoneStatusLabel.stringValue = "Input unavailable"
                microphoneStatusLabel.textColor = .systemRed
            }
        case .notDetermined:
            microphoneStatusLabel.stringValue = "Waiting for permission…"
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.startMicrophonePreview()
                    } else {
                        self.microphoneStatusLabel.stringValue = "Permission required"
                        self.microphoneStatusLabel.textColor = .systemRed
                    }
                }
            }
        default:
            microphoneStatusLabel.stringValue = "Permission required"
            microphoneStatusLabel.textColor = .systemRed
        }
    }

    private func updateMicrophoneLevel(_ level: Float) {
        microphoneLevelView.level = level

        switch level {
        case ..<0.08:
            microphoneStatusLabel.stringValue = "Speak to test"
            microphoneStatusLabel.textColor = .tertiaryLabelColor
        case ..<0.64:
            microphoneStatusLabel.stringValue = "Good level"
            microphoneStatusLabel.textColor = .systemGreen
        case ..<0.84:
            microphoneStatusLabel.stringValue = "Strong level"
            microphoneStatusLabel.textColor = .systemOrange
        default:
            microphoneStatusLabel.stringValue = "Very loud"
            microphoneStatusLabel.textColor = .systemRed
        }
    }

    @objc private func microphoneSelectionChanged() {
        let uid = microphonePopup.selectedItem?.representedObject as? String ?? ""
        AppSettings.shared.microphoneDeviceUID = uid.isEmpty ? nil : uid
        startMicrophonePreview()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc private func refreshMicrophonesClicked() {
        refreshMicrophoneDevices()
        startMicrophonePreview()
    }

    // MARK: - API key

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
        microphoneLevelMonitor.stop()
        NSApp.setActivationPolicy(.accessory)
    }
}
