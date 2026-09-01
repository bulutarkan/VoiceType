import AVFoundation
import Cocoa

final class SettingsWindowController: NSWindowController {
    var onShortcutChanged: (() -> Void)?
    var onAPIKeyChanged: (() -> Void)?

    private enum ShortcutCapture {
        case dictation
        case command
    }

    private enum SettingsTab: Int, CaseIterable {
        case general = 0
        case intelligence = 1
        case api = 2

        var title: String {
            switch self {
            case .general: return "General"
            case .intelligence: return "Intelligence"
            case .api: return "Groq & API"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .intelligence: return "sparkles"
            case .api: return "key.fill"
            }
        }
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
    private var selectedTab: SettingsTab = .general

    private var generalContainer: NSView!
    private var intelligenceContainer: NSView!
    private var apiContainer: NSView!
    private var sidebarButtons: [NSButton] = []
    private var contentHost: NSView!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
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
        // Do not start microphone here — mic must only be active when the Settings
        // window is actually visible and the General tab is selected. Starting it
        // in init() causes the orange mic indicator at app launch (see bug report).
        selectTab(.general, manageMicrophone: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshAllControls()
        // Ensure the correct tab UI is applied without auto-starting mic before the
        // window is visible, then start mic only if General is the active tab.
        selectTab(selectedTab, manageMicrophone: false)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Window is now visible — start preview only for General.
        if selectedTab == .general {
            startMicrophonePreview()
        } else {
            microphoneLevelMonitor.stop()
        }
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
        effect.material = VTDesign.Material.settingsBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        content.addSubview(effect)

        setupHeader(in: effect)

        // Sidebar
        let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 200, height: content.bounds.height - 88))
        sidebar.autoresizingMask = [.height, .maxXMargin]
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        // separator line on right
        let sep = NSView(frame: NSRect(x: 199.5, y: 0, width: 0.5, height: sidebar.bounds.height))
        sep.autoresizingMask = [.height, .minXMargin]
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sidebar.addSubview(sep)
        effect.addSubview(sidebar)

        // Sidebar buttons
        for (idx, tab) in SettingsTab.allCases.enumerated() {
            let btn = NSButton(title: "", target: self, action: #selector(sidebarClicked(_:)))
            btn.tag = idx
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 8
            btn.frame = NSRect(x: 12, y: sidebar.bounds.height - 56 - CGFloat(idx)*44, width: 176, height: 36)
            btn.autoresizingMask = [.minYMargin, .width]

            let ico = NSImageView(frame: NSRect(x: 10, y: 10, width: 16, height: 16))
            ico.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            ico.tag = 100
            btn.addSubview(ico)

            let lbl = NSTextField(labelWithString: tab.title)
            lbl.font = .systemFont(ofSize: 13, weight: .medium)
            lbl.frame = NSRect(x: 34, y: 9, width: 120, height: 18)
            lbl.tag = 101
            btn.addSubview(lbl)

            sidebar.addSubview(btn)
            sidebarButtons.append(btn)
        }

        // Footer hint in sidebar
        let hint = NSTextField(labelWithString: "VoiceType lives in the\nmenu bar. No Dock icon.")
        hint.font = .systemFont(ofSize: 10, weight: .regular)
        hint.textColor = .tertiaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.frame = NSRect(x: 16, y: 18, width: 168, height: 30)
        hint.autoresizingMask = [.maxYMargin]
        sidebar.addSubview(hint)

        // Content host on right of sidebar
        contentHost = NSView(frame: NSRect(x: 200, y: 0, width: 560, height: content.bounds.height - 88))
        contentHost.autoresizingMask = [.width, .height]
        effect.addSubview(contentHost)

        // Create containers
        let containerFrame = NSRect(x: 0, y: 0, width: 560, height: 572)
        generalContainer = makeGeneralView(frame: containerFrame)
        intelligenceContainer = makeIntelligenceView(frame: containerFrame)
        apiContainer = makeAPIView(frame: containerFrame)

        for v in [generalContainer, intelligenceContainer, apiContainer] {
            v?.frame = containerFrame
            v?.autoresizingMask = [.width, .height]
            v?.isHidden = true
            contentHost.addSubview(v!)
        }
    }

    private func setupHeader(in parent: NSView) {
        // Header bar with subtle blur + separator
        let header = NSVisualEffectView(frame: NSRect(x: 0, y: parent.bounds.height - 88, width: parent.bounds.width, height: 88))
        header.autoresizingMask = [.width, .minYMargin]
        header.material = .headerView
        header.blendingMode = .withinWindow
        header.state = .active
        parent.addSubview(header)

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: header.bounds.width, height: 0.5))
        sep.autoresizingMask = [.width]
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        header.addSubview(sep)

        let icon = NSImageView(frame: NSRect(x: 22, y: 22, width: 52, height: 52))
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: iconURL) {
            icon.image = image
        } else {
            icon.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)
        }
        icon.imageScaling = .scaleProportionallyDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 12
        icon.layer?.masksToBounds = true
        icon.shadow = VTDesign.Shadow.cardShadow()
        header.addSubview(icon)

        let title = NSTextField(labelWithString: "VoiceType")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.frame = NSRect(x: 88, y: 46, width: 240, height: 26)
        header.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Fast dictation, smart editing, anywhere on macOS")
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 89, y: 26, width: 360, height: 18)
        header.addSubview(subtitle)

        let version = NSTextField(labelWithString: "v1.1 • Groq Whisper")
        version.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        version.textColor = .tertiaryLabelColor
        version.alignment = .right
        version.frame = NSRect(x: parent.bounds.width - 200, y: 36, width: 180, height: 16)
        version.autoresizingMask = [.minXMargin]
        header.addSubview(version)
    }

    @objc private func sidebarClicked(_ sender: NSButton) {
        guard let tab = SettingsTab(rawValue: sender.tag) else { return }
        selectTab(tab)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private func selectTab(_ tab: SettingsTab, manageMicrophone: Bool = true) {
        selectedTab = tab
        for (idx, btn) in sidebarButtons.enumerated() {
            let isSel = idx == tab.rawValue
            btn.layer?.backgroundColor = isSel ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor : NSColor.clear.cgColor
            if let ico = btn.viewWithTag(100) as? NSImageView {
                ico.contentTintColor = isSel ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
            }
            if let lbl = btn.viewWithTag(101) as? NSTextField {
                lbl.textColor = isSel ? NSColor.controlAccentColor : NSColor.labelColor
                lbl.font = .systemFont(ofSize: 13, weight: isSel ? .semibold : .medium)
            }
        }
        generalContainer.isHidden = tab != .general
        intelligenceContainer.isHidden = tab != .intelligence
        apiContainer.isHidden = tab != .api

        guard manageMicrophone else { return }
        // Only manage microphone when the window is actually on screen.
        // This prevents the orange mic indicator at app launch.
        let windowVisible = window?.isVisible == true
        if tab == .general, windowVisible {
            startMicrophonePreview()
        } else {
            // Leaving General or window not visible → stop to release the mic
            // and turn off the system orange indicator.
            microphoneLevelMonitor.stop()
            microphoneLevelView.level = 0
            if tab != .general {
                microphoneStatusLabel.stringValue = "Select General to test"
                microphoneStatusLabel.textColor = .tertiaryLabelColor
            }
        }
    }

    // MARK: - General / Mic / Shortcuts

    private func makeGeneralView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: frame.width - 16, height: 520))
        scroll.documentView = doc
        view.addSubview(scroll)

        // Shortcuts card — taller, more breathing
        let shortcutsCard = makeModernCard(frame: NSRect(x: 16, y: 286, width: 528, height: 202))
        doc.addSubview(shortcutsCard)
        addSectionHeader("SHORTCUTS", symbol: "keyboard", to: shortcutsCard, y: 172)

        addLabel("Dictation", size: 13, weight: .semibold, to: shortcutsCard, frame: NSRect(x: 20, y: 128, width: 180, height: 20))
        addSecondaryLabel("Record and paste speech at the cursor.", to: shortcutsCard, frame: NSRect(x: 20, y: 110, width: 310, height: 17))
        styleShortcutButton(dictationShortcutButton, frame: NSRect(x: 324, y: 110, width: 184, height: 38), tag: 1, in: shortcutsCard)

        addLabel("Command Mode", size: 13, weight: .semibold, to: shortcutsCard, frame: NSRect(x: 20, y: 74, width: 180, height: 20))
        addSecondaryLabel("Select text, speak an instruction, replace it instantly.", to: shortcutsCard, frame: NSRect(x: 20, y: 54, width: 330, height: 17))
        styleShortcutButton(commandShortcutButton, frame: NSRect(x: 324, y: 54, width: 184, height: 38), tag: 2, in: shortcutsCard)

        shortcutStatusLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        shortcutStatusLabel.textColor = .tertiaryLabelColor
        shortcutStatusLabel.frame = NSRect(x: 20, y: 18, width: 300, height: 15)
        shortcutsCard.addSubview(shortcutStatusLabel)

        let holdLabel = NSTextField(labelWithString: "Hold to talk")
        holdLabel.font = .systemFont(ofSize: 12, weight: .medium)
        holdLabel.frame = NSRect(x: 324, y: 16, width: 120, height: 16)
        shortcutsCard.addSubview(holdLabel)
        holdSwitch.target = self
        holdSwitch.action = #selector(toggleHoldToTalk)
        holdSwitch.controlSize = .small
        holdSwitch.frame = NSRect(x: 474, y: 14, width: 30, height: 20)
        shortcutsCard.addSubview(holdSwitch)

        // Mic card — larger level view
        let micCard = makeModernCard(frame: NSRect(x: 16, y: 26, width: 528, height: 238))
        doc.addSubview(micCard)
        addSectionHeader("MICROPHONE", symbol: "mic.fill", to: micCard, y: 208)
        addLabel("Input device", size: 13, weight: .semibold, to: micCard, frame: NSRect(x: 20, y: 174, width: 180, height: 20))
        addSecondaryLabel("Auto follows the macOS default input, or choose a microphone manually.", to: micCard, frame: NSRect(x: 20, y: 156, width: 470, height: 17))

        microphonePopup.target = self
        microphonePopup.action = #selector(microphoneSelectionChanged)
        microphonePopup.controlSize = .regular
        microphonePopup.frame = NSRect(x: 20, y: 108, width: 360, height: 28)
        micCard.addSubview(microphonePopup)

        microphoneRefreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh microphones")
        microphoneRefreshButton.bezelStyle = .inline
        microphoneRefreshButton.isBordered = false
        microphoneRefreshButton.target = self
        microphoneRefreshButton.action = #selector(refreshMicrophonesClicked)
        microphoneRefreshButton.frame = NSRect(x: 386, y: 109, width: 28, height: 28)
        microphoneRefreshButton.contentTintColor = .secondaryLabelColor
        micCard.addSubview(microphoneRefreshButton)

        // Live input section — more prominent
        let liveBox = NSBox(frame: NSRect(x: 20, y: 38, width: 488, height: 56))
        liveBox.boxType = .custom
        liveBox.borderWidth = 0.5
        liveBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.5)
        liveBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55)
        liveBox.cornerRadius = 10
        micCard.addSubview(liveBox)

        let live = NSTextField(labelWithString: "LIVE INPUT")
        live.font = .systemFont(ofSize: 9, weight: .semibold)
        live.textColor = .tertiaryLabelColor
        live.frame = NSRect(x: 12, y: 32, width: 100, height: 12)
        liveBox.addSubview(live)

        microphoneLevelView.frame = NSRect(x: 12, y: 14, width: 340, height: 16)
        liveBox.addSubview(microphoneLevelView)

        microphoneStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        microphoneStatusLabel.textColor = .tertiaryLabelColor
        microphoneStatusLabel.frame = NSRect(x: 364, y: 16, width: 112, height: 14)
        microphoneStatusLabel.alignment = .right
        liveBox.addSubview(microphoneStatusLabel)

        addSecondaryLabel("Changes apply to the next recording immediately.", to: micCard, frame: NSRect(x: 20, y: 14, width: 340, height: 16))

        return view
    }

    private func makeIntelligenceView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: frame.width - 16, height: 520))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = doc
        view.addSubview(scroll)

        let smartCard = makeModernCard(frame: NSRect(x: 16, y: 272, width: 528, height: 210))
        doc.addSubview(smartCard)
        addSectionHeader("SMART PROCESSING", symbol: "sparkles", to: smartCard, y: 180)
        addLabel("Polish after transcription", size: 13.5, weight: .semibold, to: smartCard, frame: NSRect(x: 20, y: 144, width: 280, height: 20))
        addSecondaryLabel("Optional second Groq pass. Off keeps the original fastest paste path.", to: smartCard, frame: NSRect(x: 20, y: 124, width: 450, height: 17))

        smartProcessingSwitch.target = self
        smartProcessingSwitch.action = #selector(toggleSmartProcessing)
        smartProcessingSwitch.controlSize = .small
        smartProcessingSwitch.frame = NSRect(x: 474, y: 142, width: 30, height: 20)
        smartCard.addSubview(smartProcessingSwitch)

        let modeLabel = NSTextField(labelWithString: "Mode")
        modeLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        modeLabel.frame = NSRect(x: 20, y: 78, width: 60, height: 17)
        smartCard.addSubview(modeLabel)

        smartModePopup.target = self
        smartModePopup.action = #selector(smartModeChanged)
        smartModePopup.controlSize = .small
        smartModePopup.frame = NSRect(x: 20, y: 48, width: 200, height: 28)
        for mode in SmartProcessingMode.allCases {
            smartModePopup.addItem(withTitle: mode.rawValue)
            smartModePopup.lastItem?.representedObject = mode.rawValue
        }
        smartCard.addSubview(smartModePopup)

        smartModeDescription.font = .systemFont(ofSize: 11, weight: .regular)
        smartModeDescription.textColor = .secondaryLabelColor
        smartModeDescription.maximumNumberOfLines = 3
        smartModeDescription.lineBreakMode = .byWordWrapping
        smartModeDescription.frame = NSRect(x: 240, y: 36, width: 268, height: 52)
        smartCard.addSubview(smartModeDescription)

        addSecondaryLabel("Raw = casing only  •  Clean = fillers removed  •  Polished = send-ready", to: smartCard, frame: NSRect(x: 20, y: 16, width: 488, height: 16))

        let behaviorCard = makeModernCard(frame: NSRect(x: 16, y: 86, width: 528, height: 164))
        doc.addSubview(behaviorCard)
        addSectionHeader("AI MODEL", symbol: "cpu", to: behaviorCard, y: 134)

        addLabel("Groq text model", size: 12.5, weight: .medium, to: behaviorCard, frame: NSRect(x: 20, y: 96, width: 170, height: 18))
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        modelPopup.controlSize = .small
        modelPopup.frame = NSRect(x: 20, y: 58, width: 280, height: 28)
        for model in GroqTextModel.allCases {
            modelPopup.addItem(withTitle: model.title)
            modelPopup.lastItem?.representedObject = model.rawValue
        }
        behaviorCard.addSubview(modelPopup)

        let modelHint = NSTextField(labelWithString: "Used by Smart Processing and Command Mode.\nFinal speech transcription always uses Groq Whisper.")
        modelHint.font = .systemFont(ofSize: 10.5, weight: .regular)
        modelHint.textColor = .secondaryLabelColor
        modelHint.maximumNumberOfLines = 2
        modelHint.frame = NSRect(x: 316, y: 54, width: 192, height: 32)
        behaviorCard.addSubview(modelHint)

        return view
    }

    private func makeAPIView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        let card = makeModernCard(frame: NSRect(x: 16, y: 180, width: 528, height: 320))
        view.addSubview(card)
        addSectionHeader("GROQ", symbol: "key.fill", to: card, y: 286)
        addLabel("API key", size: 15, weight: .semibold, to: card, frame: NSRect(x: 20, y: 250, width: 200, height: 21))
        addSecondaryLabel("One key powers Whisper, Smart Processing and Command Mode.", to: card, frame: NSRect(x: 20, y: 228, width: 470, height: 17))

        let link = NSButton(title: "Open Groq Console →", target: self, action: #selector(openGroqConsole))
        link.bezelStyle = .inline
        link.isBordered = false
        link.contentTintColor = .systemBlue
        link.font = .systemFont(ofSize: 11, weight: .medium)
        link.frame = NSRect(x: 360, y: 251, width: 154, height: 18)
        card.addSubview(link)

        // API field container with inline eye
        let fieldBox = NSView(frame: NSRect(x: 20, y: 160, width: 488, height: 42))
        fieldBox.wantsLayer = true
        fieldBox.layer?.cornerRadius = 10
        fieldBox.layer?.borderWidth = 0.5
        fieldBox.layer?.borderColor = NSColor.separatorColor.cgColor
        fieldBox.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        card.addSubview(fieldBox)

        apiKeyField.placeholderString = "gsk_..."
        apiKeyField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        apiKeyField.isBordered = false
        apiKeyField.backgroundColor = .clear
        apiKeyField.focusRingType = .none
        apiKeyField.frame = NSRect(x: 12, y: 8, width: 380, height: 26)
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        fieldBox.addSubview(apiKeyField)

        apiVisibleField.isHidden = true
        apiVisibleField.placeholderString = "gsk_..."
        apiVisibleField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        apiVisibleField.isBordered = false
        apiVisibleField.backgroundColor = .clear
        apiVisibleField.focusRingType = .none
        apiVisibleField.frame = apiKeyField.frame
        apiVisibleField.stringValue = AppSettings.shared.groqAPIKey
        fieldBox.addSubview(apiVisibleField)

        toggleVisibilityButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Show API key")
        toggleVisibilityButton.bezelStyle = .inline
        toggleVisibilityButton.isBordered = false
        toggleVisibilityButton.target = self
        toggleVisibilityButton.action = #selector(toggleAPIKeyVisibility)
        toggleVisibilityButton.frame = NSRect(x: 400, y: 7, width: 28, height: 28)
        toggleVisibilityButton.contentTintColor = .secondaryLabelColor
        fieldBox.addSubview(toggleVisibilityButton)

        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKey)
        saveAPIKeyButton.bezelStyle = .rounded
        saveAPIKeyButton.keyEquivalent = "\r"
        saveAPIKeyButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        saveAPIKeyButton.frame = NSRect(x: 432, y: 6, width: 48, height: 30)
        saveAPIKeyButton.wantsLayer = true
        saveAPIKeyButton.layer?.cornerRadius = 8
        fieldBox.addSubview(saveAPIKeyButton)

        // status with icon
        let statusIcon = NSImageView(frame: NSRect(x: 20, y: 124, width: 14, height: 14))
        statusIcon.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        statusIcon.contentTintColor = .secondaryLabelColor
        card.addSubview(statusIcon)

        apiStatusLabel.stringValue = "Audio files are temporary and deleted after transcription. Smart Processing is off by default."
        apiStatusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        apiStatusLabel.textColor = .secondaryLabelColor
        apiStatusLabel.maximumNumberOfLines = 2
        apiStatusLabel.frame = NSRect(x: 38, y: 112, width: 470, height: 34)
        card.addSubview(apiStatusLabel)

        let privacy = NSTextField(labelWithString: "The final transcript is always copied to the clipboard. Accessibility permission enables automatic paste back into the original app.")
        privacy.font = .systemFont(ofSize: 11, weight: .regular)
        privacy.textColor = .tertiaryLabelColor
        privacy.maximumNumberOfLines = 2
        privacy.lineBreakMode = .byWordWrapping
        privacy.frame = NSRect(x: 20, y: 24, width: 488, height: 36)
        card.addSubview(privacy)

        // Tip card below main card
        let tip = makeModernCard(frame: NSRect(x: 16, y: 62, width: 528, height: 96))
        view.addSubview(tip)
        addSectionHeader("TIP", symbol: "lightbulb", to: tip, y: 66)
        let tipText = NSTextField(labelWithString: "Create a Groq key at console.groq.com/keys, paste it above, and press Save. Your key stays on this Mac and is never sent elsewhere except to Groq for transcription.")
        tipText.font = .systemFont(ofSize: 11.5, weight: .regular)
        tipText.textColor = .secondaryLabelColor
        tipText.maximumNumberOfLines = 3
        tipText.lineBreakMode = .byWordWrapping
        tipText.frame = NSRect(x: 20, y: 16, width: 488, height: 44)
        tip.addSubview(tipText)

        return view
    }

    private func makeModernCard(frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.borderWidth = 0.6
        box.borderColor = VTDesign.Color.cardBorder
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.88)
        box.cornerRadius = VTDesign.Radius.card
        box.wantsLayer = true
        box.shadow = VTDesign.Shadow.cardShadow()
        return box
    }

    private func addSectionHeader(_ text: String, symbol: String, to parent: NSView, y: CGFloat) {
        let image = NSImageView(frame: NSRect(x: 20, y: y, width: 15, height: 15))
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        image.contentTintColor = .secondaryLabelColor
        parent.addSubview(image)

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 40, y: y - 1, width: 180, height: 15)
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
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.frame = frame
        parent.addSubview(label)
    }

    private func styleShortcutButton(_ button: NSButton, frame: NSRect, tag: Int, in parent: NSView) {
        button.tag = tag
        button.target = self
        button.action = #selector(startRecordingShortcut(_:))
        button.bezelStyle = .rounded
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.layer?.borderWidth = 0.5
        button.layer?.borderColor = NSColor.separatorColor.cgColor
        button.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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
        sender.layer?.borderColor = NSColor.controlAccentColor.cgColor
        sender.layer?.borderWidth = 1.2
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
        dictationShortcutButton.layer?.borderWidth = 0.5
        dictationShortcutButton.layer?.borderColor = NSColor.separatorColor.cgColor
        commandShortcutButton.layer?.borderWidth = 0.5
        commandShortcutButton.layer?.borderColor = NSColor.separatorColor.cgColor
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
        // subtle enable/disable animation
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            smartModePopup.animator().alphaValue = AppSettings.shared.smartProcessingEnabled ? 1.0 : 0.45
            smartModeDescription.animator().alphaValue = AppSettings.shared.smartProcessingEnabled ? 1.0 : 0.45
        }
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            microphoneRefreshButton.animator().layer?.transform = CATransform3DMakeRotation(.pi, 0, 0, 1)
        }
        refreshMicrophoneDevices()
        startMicrophonePreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            self.microphoneRefreshButton.layer?.transform = CATransform3DIdentity
        }
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
        apiStatusLabel.textColor = value.isEmpty ? .systemRed : .systemGreen
        NSSound(named: .init("Tink"))?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.apiStatusLabel.stringValue = "Audio files are temporary and deleted after transcription. Smart Processing is off by default."
            self?.apiStatusLabel.textColor = .secondaryLabelColor
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

    func windowDidBecomeKey(_ notification: Notification) {
        // Resume live preview only when General is active — avoids orange indicator otherwise.
        if selectedTab == .general, window?.isVisible == true {
            startMicrophonePreview()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Pause preview when settings loses focus to release the mic in background.
        microphoneLevelMonitor.stop()
        microphoneLevelView.level = 0
    }

    func windowDidMiniaturize(_ notification: Notification) {
        microphoneLevelMonitor.stop()
        microphoneLevelView.level = 0
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if selectedTab == .general, window?.isVisible == true {
            startMicrophonePreview()
        }
    }
}
