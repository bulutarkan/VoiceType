import AVFoundation
import Cocoa

final class SettingsWindowController: NSWindowController {
    var onShortcutChanged: (() -> Void)?
    var onAPIKeyChanged: (() -> Void)?

    private enum ShortcutCapture {
        case dictation
        case command
    }

    private let dictationShortcutButton = NSButton(title: "", target: nil, action: nil)
    private let commandShortcutButton = NSButton(title: "", target: nil, action: nil)
    private let shortcutStatusLabel = NSTextField(labelWithString: "")
    private let holdSwitch = NSSwitch()

    private let microphonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let microphoneRefreshButton = NSButton()
    private let microphoneLevelView = MicrophoneLevelView(frame: .zero)
    private let microphoneStatusLabel = NSTextField(labelWithString: "Speak to test")
    private let microphoneLevelMonitor = MicrophoneLevelMonitor()

    private let smartProcessingSwitch = NSSwitch()
    private let smartModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let smartModeDescription = NSTextField(labelWithString: "")
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let apiKeyField = NSSecureTextField()
    private let apiVisibleField = NSTextField()
    private let toggleVisibilityButton = NSButton()
    private let saveAPIKeyButton = NSButton(title: "Save", target: nil, action: nil)
    private let apiStatusLabel = NSTextField(labelWithString: "")

    private var keyMonitor: Any?
    private var activeShortcutCapture: ShortcutCapture?
    private var isAPIKeyVisible = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceType Settings"
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
        refreshAllControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshAllControls()
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

    // MARK: - Layout

    private func setupView() {
        guard let content = window?.contentView else { return }

        let effect = NSVisualEffectView(frame: content.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        content.addSubview(effect)

        setupHeader(in: effect)

        let tabs = NSTabView(frame: NSRect(x: 24, y: 24, width: 632, height: 486))
        tabs.tabViewType = .topTabsBezelBorder
        tabs.autoresizingMask = [.width, .height]

        let general = NSTabViewItem(identifier: "general")
        general.label = "General"
        general.view = makeGeneralTab(frame: tabs.contentRect)
        tabs.addTabViewItem(general)

        let intelligence = NSTabViewItem(identifier: "intelligence")
        intelligence.label = "Intelligence"
        intelligence.view = makeIntelligenceTab(frame: tabs.contentRect)
        tabs.addTabViewItem(intelligence)

        let account = NSTabViewItem(identifier: "account")
        account.label = "Groq & API"
        account.view = makeAPITab(frame: tabs.contentRect)
        tabs.addTabViewItem(account)

        effect.addSubview(tabs)
    }

    private func setupHeader(in parent: NSView) {
        let icon = NSImageView(frame: NSRect(x: 28, y: 528, width: 58, height: 58))
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            icon.image = image
        } else {
            icon.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)
        }
        icon.imageScaling = .scaleProportionallyDown
        parent.addSubview(icon)

        let title = NSTextField(labelWithString: "VoiceType")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        title.frame = NSRect(x: 104, y: 554, width: 250, height: 28)
        parent.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Fast dictation, smart editing, anywhere on macOS")
        subtitle.font = .systemFont(ofSize: 11.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 105, y: 533, width: 360, height: 18)
        parent.addSubview(subtitle)

        let version = NSTextField(labelWithString: "v1.1 • Groq Whisper")
        version.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        version.textColor = .tertiaryLabelColor
        version.alignment = .right
        version.frame = NSRect(x: 470, y: 544, width: 180, height: 18)
        parent.addSubview(version)
    }

    private func makeGeneralTab(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        let shortcutsCard = makeCard(frame: NSRect(x: 16, y: 260, width: 600, height: 174))
        view.addSubview(shortcutsCard)
        addSectionHeader("SHORTCUTS", symbol: "keyboard", to: shortcutsCard, y: 144)

        addLabel("Dictation", size: 13, weight: .semibold, to: shortcutsCard, frame: NSRect(x: 20, y: 108, width: 180, height: 20))
        addSecondaryLabel("Record and paste speech at the cursor.", to: shortcutsCard, frame: NSRect(x: 20, y: 88, width: 310, height: 17))
        styleShortcutButton(dictationShortcutButton, frame: NSRect(x: 390, y: 92, width: 184, height: 36), tag: 1, in: shortcutsCard)

        addLabel("Command Mode", size: 13, weight: .semibold, to: shortcutsCard, frame: NSRect(x: 20, y: 57, width: 180, height: 20))
        addSecondaryLabel("Select text, speak an instruction, replace it instantly.", to: shortcutsCard, frame: NSRect(x: 20, y: 37, width: 330, height: 17))
        styleShortcutButton(commandShortcutButton, frame: NSRect(x: 390, y: 42, width: 184, height: 36), tag: 2, in: shortcutsCard)

        shortcutStatusLabel.font = .systemFont(ofSize: 10, weight: .regular)
        shortcutStatusLabel.textColor = .tertiaryLabelColor
        shortcutStatusLabel.frame = NSRect(x: 20, y: 10, width: 340, height: 15)
        shortcutsCard.addSubview(shortcutStatusLabel)

        let holdLabel = NSTextField(labelWithString: "Hold to talk")
        holdLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        holdLabel.frame = NSRect(x: 390, y: 10, width: 120, height: 16)
        shortcutsCard.addSubview(holdLabel)
        holdSwitch.target = self
        holdSwitch.action = #selector(toggleHoldToTalk)
        holdSwitch.controlSize = .small
        holdSwitch.frame = NSRect(x: 544, y: 8, width: 30, height: 20)
        shortcutsCard.addSubview(holdSwitch)

        let micCard = makeCard(frame: NSRect(x: 16, y: 70, width: 600, height: 172))
        view.addSubview(micCard)
        addSectionHeader("MICROPHONE", symbol: "mic.fill", to: micCard, y: 142)
        addLabel("Input device", size: 13, weight: .semibold, to: micCard, frame: NSRect(x: 20, y: 108, width: 180, height: 20))
        addSecondaryLabel("Auto follows the macOS default input, or choose a microphone manually.", to: micCard, frame: NSRect(x: 20, y: 88, width: 470, height: 17))

        microphonePopup.target = self
        microphonePopup.action = #selector(microphoneSelectionChanged)
        microphonePopup.controlSize = .small
        microphonePopup.frame = NSRect(x: 20, y: 47, width: 330, height: 30)
        micCard.addSubview(microphonePopup)

        microphoneRefreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh microphones")
        microphoneRefreshButton.bezelStyle = .inline
        microphoneRefreshButton.isBordered = false
        microphoneRefreshButton.target = self
        microphoneRefreshButton.action = #selector(refreshMicrophonesClicked)
        microphoneRefreshButton.frame = NSRect(x: 356, y: 48, width: 28, height: 28)
        micCard.addSubview(microphoneRefreshButton)

        let live = NSTextField(labelWithString: "LIVE INPUT")
        live.font = .systemFont(ofSize: 9.5, weight: .semibold)
        live.textColor = .tertiaryLabelColor
        live.frame = NSRect(x: 410, y: 67, width: 120, height: 14)
        micCard.addSubview(live)

        microphoneLevelView.frame = NSRect(x: 410, y: 48, width: 164, height: 14)
        micCard.addSubview(microphoneLevelView)
        microphoneStatusLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        microphoneStatusLabel.textColor = .tertiaryLabelColor
        microphoneStatusLabel.frame = NSRect(x: 410, y: 29, width: 164, height: 14)
        micCard.addSubview(microphoneStatusLabel)

        addSecondaryLabel("Changes apply to the next recording immediately.", to: micCard, frame: NSRect(x: 20, y: 16, width: 340, height: 16))

        return view
    }

    private func makeIntelligenceTab(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        let smartCard = makeCard(frame: NSRect(x: 16, y: 254, width: 600, height: 180))
        view.addSubview(smartCard)
        addSectionHeader("SMART PROCESSING", symbol: "sparkles", to: smartCard, y: 150)
        addLabel("Polish after transcription", size: 13.5, weight: .semibold, to: smartCard, frame: NSRect(x: 20, y: 116, width: 260, height: 20))
        addSecondaryLabel("Optional second Groq pass. Off keeps the original fastest paste path.", to: smartCard, frame: NSRect(x: 20, y: 96, width: 450, height: 17))

        smartProcessingSwitch.target = self
        smartProcessingSwitch.action = #selector(toggleSmartProcessing)
        smartProcessingSwitch.frame = NSRect(x: 544, y: 112, width: 30, height: 20)
        smartCard.addSubview(smartProcessingSwitch)

        let modeLabel = NSTextField(labelWithString: "Mode")
        modeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        modeLabel.frame = NSRect(x: 20, y: 61, width: 80, height: 17)
        smartCard.addSubview(modeLabel)

        smartModePopup.target = self
        smartModePopup.action = #selector(smartModeChanged)
        smartModePopup.frame = NSRect(x: 92, y: 54, width: 190, height: 30)
        for mode in SmartProcessingMode.allCases {
            smartModePopup.addItem(withTitle: mode.rawValue)
            smartModePopup.lastItem?.representedObject = mode.rawValue
        }
        smartCard.addSubview(smartModePopup)

        smartModeDescription.font = .systemFont(ofSize: 10.5, weight: .regular)
        smartModeDescription.textColor = .secondaryLabelColor
        smartModeDescription.maximumNumberOfLines = 2
        smartModeDescription.lineBreakMode = .byWordWrapping
        smartModeDescription.frame = NSRect(x: 300, y: 48, width: 274, height: 38)
        smartCard.addSubview(smartModeDescription)

        addSecondaryLabel("Raw = casing/proper names only • Clean = fillers/repeats • Polished = send-ready flow", to: smartCard, frame: NSRect(x: 20, y: 18, width: 554, height: 17))

        let behaviorCard = makeCard(frame: NSRect(x: 16, y: 102, width: 600, height: 134))
        view.addSubview(behaviorCard)
        addSectionHeader("AI MODEL", symbol: "cpu", to: behaviorCard, y: 104)

        addLabel("Groq text model", size: 12.5, weight: .medium, to: behaviorCard, frame: NSRect(x: 20, y: 65, width: 170, height: 18))
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        modelPopup.frame = NSRect(x: 300, y: 58, width: 274, height: 30)
        for model in GroqTextModel.allCases {
            modelPopup.addItem(withTitle: model.title)
            modelPopup.lastItem?.representedObject = model.rawValue
        }
        behaviorCard.addSubview(modelPopup)
        addSecondaryLabel("Used by Smart Processing and Command Mode. Final speech transcription always uses Groq Whisper.", to: behaviorCard, frame: NSRect(x: 20, y: 27, width: 554, height: 17))

        return view
    }

    private func makeAPITab(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        let card = makeCard(frame: NSRect(x: 16, y: 176, width: 600, height: 258))
        view.addSubview(card)
        addSectionHeader("GROQ", symbol: "key.fill", to: card, y: 228)
        addLabel("API key", size: 14, weight: .semibold, to: card, frame: NSRect(x: 20, y: 192, width: 200, height: 21))
        addSecondaryLabel("One key powers Whisper transcription, Smart Processing and Command Mode.", to: card, frame: NSRect(x: 20, y: 170, width: 470, height: 17))

        let link = NSButton(title: "Open Groq Console →", target: self, action: #selector(openGroqConsole))
        link.bezelStyle = .inline
        link.isBordered = false
        link.contentTintColor = .systemBlue
        link.frame = NSRect(x: 420, y: 193, width: 154, height: 18)
        card.addSubview(link)

        apiKeyField.placeholderString = "gsk_..."
        apiKeyField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        apiKeyField.frame = NSRect(x: 20, y: 117, width: 438, height: 32)
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        card.addSubview(apiKeyField)

        apiVisibleField.isHidden = true
        apiVisibleField.placeholderString = "gsk_..."
        apiVisibleField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        apiVisibleField.frame = apiKeyField.frame
        apiVisibleField.stringValue = AppSettings.shared.groqAPIKey
        card.addSubview(apiVisibleField)

        toggleVisibilityButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Show API key")
        toggleVisibilityButton.bezelStyle = .inline
        toggleVisibilityButton.isBordered = false
        toggleVisibilityButton.target = self
        toggleVisibilityButton.action = #selector(toggleAPIKeyVisibility)
        toggleVisibilityButton.frame = NSRect(x: 464, y: 119, width: 28, height: 28)
        card.addSubview(toggleVisibilityButton)

        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKey)
        saveAPIKeyButton.bezelStyle = .rounded
        saveAPIKeyButton.font = .systemFont(ofSize: 12, weight: .semibold)
        saveAPIKeyButton.frame = NSRect(x: 500, y: 117, width: 74, height: 32)
        card.addSubview(saveAPIKeyButton)

        apiStatusLabel.stringValue = "Audio files are temporary and deleted after transcription. Smart Processing is off by default."
        apiStatusLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        apiStatusLabel.textColor = .secondaryLabelColor
        apiStatusLabel.maximumNumberOfLines = 2
        apiStatusLabel.frame = NSRect(x: 20, y: 74, width: 554, height: 34)
        card.addSubview(apiStatusLabel)

        let privacy = NSTextField(labelWithString: "The final transcript is always copied to the clipboard. Accessibility permission enables automatic paste back into the original app.")
        privacy.font = .systemFont(ofSize: 10.5, weight: .regular)
        privacy.textColor = .tertiaryLabelColor
        privacy.maximumNumberOfLines = 2
        privacy.lineBreakMode = .byWordWrapping
        privacy.frame = NSRect(x: 20, y: 26, width: 554, height: 36)
        card.addSubview(privacy)

        return view
    }

    private func makeCard(frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.borderWidth = 0.5
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor.withAlphaComponent(0.82)
        box.cornerRadius = 13
        box.wantsLayer = true
        box.shadow = NSShadow()
        box.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.08)
        box.shadow?.shadowBlurRadius = 14
        box.shadow?.shadowOffset = NSSize(width: 0, height: 4)
        return box
    }

    private func addSectionHeader(_ text: String, symbol: String, to parent: NSView, y: CGFloat) {
        let image = NSImageView(frame: NSRect(x: 20, y: y, width: 14, height: 14))
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10.5, weight: .medium))
        image.contentTintColor = .secondaryLabelColor
        parent.addSubview(image)

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 39, y: y - 1, width: 180, height: 15)
        parent.addSubview(label)
    }

    private func addLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, to parent: NSView, frame: NSRect) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.frame = frame
        parent.addSubview(label)
    }

    private func addSecondaryLabel(_ text: String, to parent: NSView, frame: NSRect) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10.5, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.frame = frame
        parent.addSubview(label)
    }

    private func styleShortcutButton(_ button: NSButton, frame: NSRect, tag: Int, in parent: NSView) {
        button.tag = tag
        button.target = self
        button.action = #selector(startRecordingShortcut(_:))
        button.bezelStyle = .rounded
        button.font = .monospacedSystemFont(ofSize: 13.5, weight: .semibold)
        button.frame = frame
        parent.addSubview(button)
    }

    // MARK: - Refresh

    private func refreshAllControls() {
        dictationShortcutButton.title = AppSettings.shared.hotkeyDisplayString
        commandShortcutButton.title = AppSettings.shared.commandHotkeyDisplayString
        holdSwitch.state = AppSettings.shared.holdToTalkEnabled ? .on : .off
        smartProcessingSwitch.state = AppSettings.shared.smartProcessingEnabled ? .on : .off
        smartModePopup.selectItem(withTitle: AppSettings.shared.smartProcessingMode.rawValue)
        modelPopup.selectItem(at: GroqTextModel.allCases.firstIndex(of: AppSettings.shared.groqTextModel) ?? 0)
        smartModePopup.isEnabled = AppSettings.shared.smartProcessingEnabled
        smartModeDescription.stringValue = AppSettings.shared.smartProcessingMode.detail
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        apiVisibleField.stringValue = AppSettings.shared.groqAPIKey
        shortcutStatusLabel.stringValue = activeShortcutCapture == nil
            ? (AppSettings.shared.holdToTalkEnabled ? "Esc cancels • Release shortcut to transcribe." : "Esc cancels • Enter transcribes and pastes.")
            : "Press a new shortcut. Esc cancels."
        refreshMicrophoneDevices()
    }

    // MARK: - Shortcut handling

    @objc private func startRecordingShortcut(_ sender: NSButton) {
        stopRecordingShortcut()
        activeShortcutCapture = sender.tag == 2 ? .command : .dictation
        shortcutStatusLabel.stringValue = "Press a new shortcut with at least one modifier. Esc cancels."
        sender.title = "Press shortcut…"
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleShortcutEvent(event)
            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        activeShortcutCapture = nil
        dictationShortcutButton.title = AppSettings.shared.hotkeyDisplayString
        commandShortcutButton.title = AppSettings.shared.commandHotkeyDisplayString
        shortcutStatusLabel.stringValue = AppSettings.shared.holdToTalkEnabled
            ? "Esc cancels • Release shortcut to transcribe."
            : "Esc cancels • Enter transcribes and pastes."
    }

    private func handleShortcutEvent(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecordingShortcut()
            return
        }
        guard let activeShortcutCapture else { return }
        let modifiers = ShortcutFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            shortcutStatusLabel.stringValue = "Add ⌘, ⌥, ⌃, or ⇧ to the shortcut."
            return
        }

        let keyCode = UInt32(event.keyCode)
        let conflictsWithOther: Bool
        switch activeShortcutCapture {
        case .dictation:
            conflictsWithOther = keyCode == AppSettings.shared.commandHotkeyKeyCode && modifiers == AppSettings.shared.commandHotkeyModifiers
        case .command:
            conflictsWithOther = keyCode == AppSettings.shared.hotkeyKeyCode && modifiers == AppSettings.shared.hotkeyModifiers
        }
        guard !conflictsWithOther else {
            shortcutStatusLabel.stringValue = "Dictation and Command Mode need different shortcuts."
            return
        }

        switch activeShortcutCapture {
        case .dictation:
            AppSettings.shared.hotkeyKeyCode = keyCode
            AppSettings.shared.hotkeyModifiers = modifiers
        case .command:
            AppSettings.shared.commandHotkeyKeyCode = keyCode
            AppSettings.shared.commandHotkeyModifiers = modifiers
        }
        stopRecordingShortcut()
        onShortcutChanged?()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc private func toggleHoldToTalk() {
        AppSettings.shared.holdToTalkEnabled = holdSwitch.state == .on
        shortcutStatusLabel.stringValue = AppSettings.shared.holdToTalkEnabled
            ? "Esc cancels • Release shortcut to transcribe."
            : "Esc cancels • Enter transcribes and pastes."
        onShortcutChanged?()
    }

    // MARK: - Intelligence

    @objc private func toggleSmartProcessing() {
        AppSettings.shared.smartProcessingEnabled = smartProcessingSwitch.state == .on
        smartModePopup.isEnabled = AppSettings.shared.smartProcessingEnabled
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    @objc private func smartModeChanged() {
        guard let raw = smartModePopup.selectedItem?.representedObject as? String,
              let mode = SmartProcessingMode(rawValue: raw) else { return }
        AppSettings.shared.smartProcessingMode = mode
        smartModeDescription.stringValue = mode.detail
    }

    @objc private func modelChanged() {
        guard let raw = modelPopup.selectedItem?.representedObject as? String,
              let model = GroqTextModel(rawValue: raw) else { return }
        AppSettings.shared.groqTextModel = model
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
            let suffix = device.id == defaultID ? " • Default" : ""
            microphonePopup.addItem(withTitle: device.name + suffix)
            microphonePopup.lastItem?.representedObject = device.uid
        }

        if let index = microphonePopup.itemArray.firstIndex(where: { ($0.representedObject as? String ?? "") == selectedUID }) {
            microphonePopup.selectItem(at: index)
        } else {
            microphonePopup.selectItem(at: 0)
            if !selectedUID.isEmpty { AppSettings.shared.microphoneDeviceUID = nil }
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
                    if granted { self?.startMicrophonePreview() }
                    else {
                        self?.microphoneStatusLabel.stringValue = "Permission required"
                        self?.microphoneStatusLabel.textColor = .systemRed
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
            toggleVisibilityButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Hide API key")
            apiVisibleField.becomeFirstResponder()
        } else {
            apiKeyField.stringValue = apiVisibleField.stringValue
            apiKeyField.isHidden = false
            apiVisibleField.isHidden = true
            toggleVisibilityButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Show API key")
            apiKeyField.becomeFirstResponder()
        }
    }

    @objc private func saveAPIKey() {
        let value = (isAPIKeyVisible ? apiVisibleField.stringValue : apiKeyField.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.shared.groqAPIKey = value
        apiKeyField.stringValue = value
        apiVisibleField.stringValue = value
        onAPIKeyChanged?()
        apiStatusLabel.stringValue = value.isEmpty ? "API key cleared." : "API key saved. Whisper, Smart Processing and Command Mode are ready."
        NSSound(named: .init("Tink"))?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.apiStatusLabel.stringValue = "Audio files are temporary and deleted after transcription. Smart Processing is off by default."
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
