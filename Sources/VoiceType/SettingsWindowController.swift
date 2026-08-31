import Cocoa

final class SettingsWindowController: NSWindowController {
    var onShortcutChanged: (() -> Void)?
    var onAPIKeyChanged: (() -> Void)?

    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let apiKeyField = NSSecureTextField()
    private let saveAPIKeyButton = NSButton(title: "Kaydet", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private var keyMonitor: Any?
    private var isRecordingShortcut = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceType Ayarları"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        setupView()
        refreshShortcut()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refreshShortcut()
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

        let title = NSTextField(labelWithString: "Kısayol")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.frame = NSRect(x: 28, y: 220, width: 200, height: 24)
        contentView.addSubview(title)

        let description = NSTextField(labelWithString: "VoiceType kayıt panelini açıp kapatacak global kısayolu seç.")
        description.textColor = .secondaryLabelColor
        description.frame = NSRect(x: 28, y: 195, width: 400, height: 20)
        contentView.addSubview(description)

        shortcutButton.target = self
        shortcutButton.action = #selector(startRecordingShortcut)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        shortcutButton.frame = NSRect(x: 28, y: 150, width: 190, height: 36)
        contentView.addSubview(shortcutButton)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 28, y: 122, width: 400, height: 18)
        contentView.addSubview(statusLabel)

        let apiTitle = NSTextField(labelWithString: "Groq API Anahtarı")
        apiTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        apiTitle.frame = NSRect(x: 28, y: 82, width: 220, height: 24)
        contentView.addSubview(apiTitle)

        apiKeyField.placeholderString = "gsk_..."
        apiKeyField.frame = NSRect(x: 28, y: 42, width: 310, height: 28)
        apiKeyField.stringValue = AppSettings.shared.groqAPIKey
        contentView.addSubview(apiKeyField)

        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKey)
        saveAPIKeyButton.bezelStyle = .rounded
        saveAPIKeyButton.frame = NSRect(x: 350, y: 41, width: 82, height: 30)
        contentView.addSubview(saveAPIKeyButton)
    }

    private func refreshShortcut() {
        shortcutButton.title = AppSettings.shared.hotkeyDisplayString
        statusLabel.stringValue = "Değiştirmek için kısayol düğmesine bas."
    }

    @objc private func startRecordingShortcut() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutButton.title = "Yeni kısayol..."
        statusLabel.stringValue = "En az bir modifier ile istediğin tuşa bas. Esc iptal eder."

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
            statusLabel.stringValue = "Lütfen ⌘, ⌥, ⌃ veya ⇧ ile birlikte bir tuş seç."
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
        statusLabel.stringValue = "API anahtarı kaydedildi."
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopRecordingShortcut()
        NSApp.setActivationPolicy(.accessory)
    }
}
