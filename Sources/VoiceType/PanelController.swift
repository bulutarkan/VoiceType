import AVFoundation
import Cocoa
import QuartzCore

// MARK: - Recording panel models

enum PanelPurpose {
    case dictation
    case command
}

private enum RecordingPanelMode {
    case recording
    case processing
    case error
}

// MARK: - Waveform

final class WaveformView: NSView {
    private var bars: [CALayer] = []
    private let count = 44
    private let barWidth: CGFloat = 2.2
    private let gap: CGFloat = 1.55

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        for _ in 0..<count {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
            bar.cornerRadius = barWidth / 2
            bar.masksToBounds = true
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ amplitudes: [Float]) {
        let totalWidth = CGFloat(count) * (barWidth + gap) - gap
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.height / 2

        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.08)
        for (index, bar) in bars.enumerated() {
            let amplitude = CGFloat(index < amplitudes.count ? amplitudes[index] : 0)
            let height = max(2.5, pow(amplitude, 0.85) * bounds.height * 0.86)
            bar.frame = CGRect(
                x: startX + CGFloat(index) * (barWidth + gap),
                y: centerY - height / 2,
                width: barWidth,
                height: height
            )
            let alpha: CGFloat = amplitude > 0.55 ? 1.0 : amplitude > 0.22 ? 0.72 : amplitude > 0.05 ? 0.42 : 0.22
            bar.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
            bar.opacity = Float(alpha)
        }
        CATransaction.commit()
    }
}

// MARK: - RecordingView

final class RecordingView: NSView {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onRetry: (() -> Void)?

    let retryButton = NSButton()

    private let effectView = NSVisualEffectView()
    private let borderLayer = CALayer()
    private let waveform = WaveformView(frame: .zero)
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let statusLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton()
    private let confirmButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let errorLabel = NSTextField(labelWithString: "")
    private let modeBadge = NSTextField(labelWithString: "")

    private var panelMode: RecordingPanelMode = .recording
    private var purpose: PanelPurpose = .dictation

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 17
        effectView.layer?.masksToBounds = true
        addSubview(effectView)

        borderLayer.cornerRadius = 17
        borderLayer.borderWidth = 0.5
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        borderLayer.masksToBounds = true
        layer?.addSublayer(borderLayer)

        addSubview(waveform)

        timeLabel.textColor = .white.withAlphaComponent(0.92)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.alignment = .center
        addSubview(timeLabel)

        statusLabel.textColor = .white.withAlphaComponent(0.92)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        addSubview(statusLabel)

        modeBadge.font = .systemFont(ofSize: 8.5, weight: .semibold)
        modeBadge.alignment = .center
        modeBadge.textColor = .white.withAlphaComponent(0.68)
        modeBadge.wantsLayer = true
        modeBadge.layer?.cornerRadius = 6
        modeBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        modeBadge.isHidden = true
        addSubview(modeBadge)

        errorLabel.textColor = NSColor.systemRed.withAlphaComponent(0.96)
        errorLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        errorLabel.alignment = .left
        errorLabel.maximumNumberOfLines = 1
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.cell?.wraps = false
        errorLabel.isHidden = true
        addSubview(errorLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.appearance = NSAppearance(named: .vibrantDark)
        spinner.isHidden = true
        addSubview(spinner)

        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        cancelButton.isBordered = false
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 15
        cancelButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        cancelButton.layer?.borderWidth = 0.5
        cancelButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        cancelButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        cancelButton.contentTintColor = .white
        cancelButton.target = self
        cancelButton.action = #selector(didCancel)
        addSubview(cancelButton)

        confirmButton.isBordered = false
        confirmButton.wantsLayer = true
        confirmButton.layer?.cornerRadius = 15
        confirmButton.layer?.backgroundColor = NSColor.white.cgColor
        confirmButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Confirm")?
            .withSymbolConfiguration(.init(pointSize: 11.5, weight: .bold))
        confirmButton.contentTintColor = .black
        confirmButton.target = self
        confirmButton.action = #selector(didConfirm)
        addSubview(confirmButton)

        retryButton.isBordered = false
        retryButton.wantsLayer = true
        retryButton.layer?.cornerRadius = 14
        retryButton.layer?.backgroundColor = NSColor.white.cgColor
        retryButton.title = "Retry"
        retryButton.font = .systemFont(ofSize: 11, weight: .semibold)
        retryButton.contentTintColor = .black
        retryButton.target = self
        retryButton.action = #selector(didRetry)
        retryButton.isHidden = true
        addSubview(retryButton)
    }

    func setPurpose(_ purpose: PanelPurpose) {
        self.purpose = purpose
        modeBadge.stringValue = "COMMAND"
        modeBadge.isHidden = purpose != .command
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let rect = bounds
        effectView.frame = rect
        effectView.layer?.cornerRadius = 17
        borderLayer.frame = rect
        borderLayer.cornerRadius = 17

        let padding: CGFloat = 8
        let buttonSize: CGFloat = 30
        let centerY = (rect.height - buttonSize) / 2
        cancelButton.frame = CGRect(x: padding, y: centerY, width: buttonSize, height: buttonSize)

        switch panelMode {
        case .recording:
            confirmButton.isHidden = false
            retryButton.isHidden = true
            errorLabel.isHidden = true
            spinner.isHidden = true
            statusLabel.isHidden = true
            waveform.isHidden = false
            timeLabel.isHidden = false
            modeBadge.isHidden = purpose != .command

            confirmButton.frame = CGRect(x: rect.width - padding - buttonSize, y: centerY, width: buttonSize, height: buttonSize)
            let timeWidth: CGFloat = 38
            let timeX = confirmButton.frame.minX - timeWidth - 7
            timeLabel.frame = CGRect(x: timeX, y: (rect.height - 16) / 2, width: timeWidth, height: 16)

            var left = cancelButton.frame.maxX + 10
            if purpose == .command {
                modeBadge.frame = CGRect(x: left, y: (rect.height - 15) / 2, width: 62, height: 15)
                left = modeBadge.frame.maxX + 8
            }
            let right = timeX - 8
            waveform.frame = CGRect(x: left, y: 8, width: max(0, right - left), height: rect.height - 16)

        case .processing:
            confirmButton.isHidden = true
            retryButton.isHidden = true
            errorLabel.isHidden = true
            waveform.isHidden = true
            timeLabel.isHidden = true
            modeBadge.isHidden = true
            statusLabel.isHidden = false
            spinner.isHidden = false
            spinner.frame = CGRect(x: cancelButton.frame.maxX + 16, y: (rect.height - 14) / 2, width: 14, height: 14)
            statusLabel.frame = CGRect(x: spinner.frame.maxX + 8, y: (rect.height - 17) / 2, width: rect.width - spinner.frame.maxX - 24, height: 17)

        case .error:
            confirmButton.isHidden = true
            waveform.isHidden = true
            timeLabel.isHidden = true
            statusLabel.isHidden = true
            modeBadge.isHidden = true
            spinner.isHidden = true
            errorLabel.isHidden = false
            retryButton.isHidden = false
            retryButton.frame = CGRect(x: rect.width - padding - 72, y: (rect.height - 28) / 2, width: 72, height: 28)
            errorLabel.frame = CGRect(
                x: cancelButton.frame.maxX + 11,
                y: (rect.height - 18) / 2,
                width: max(0, retryButton.frame.minX - cancelButton.frame.maxX - 20),
                height: 18
            )
        }
    }

    func update(amplitudes: [Float], time: String) {
        guard panelMode == .recording else { return }
        waveform.update(amplitudes)
        timeLabel.stringValue = time
    }

    func setProcessingStatus(_ text: String) {
        panelMode = .processing
        statusLabel.stringValue = text
        cancelButton.isEnabled = false
        spinner.startAnimation(nil)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func showError(_ message: String, retryTitle: String = "Retry") {
        panelMode = .error
        errorLabel.stringValue = message
        retryButton.title = retryTitle
        cancelButton.isEnabled = true
        spinner.stopAnimation(nil)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    @objc private func didCancel() { onCancel?() }
    @objc private func didConfirm() { onConfirm?() }
    @objc private func didRetry() { onRetry?() }
}

// MARK: - PanelController

final class PanelController: NSObject {
    private var panel: NSPanel?
    private var recordingView: RecordingView?
    private var recorder = AudioRecorder()
    private var displayTimer: Timer?
    private var injectionTarget: InjectionTarget?
    var onRecordingControlsChanged: ((Bool, Bool) -> Void)?
    private var lastAudioData: Data?
    private var lastCommandInstruction: String?
    private var retryOverride: (() -> Void)?

    private(set) var purpose: PanelPurpose = .dictation
    var isVisible: Bool { panel != nil }
    var isTranscribing = false

    func showDictation() {
        show(.dictation)
    }

    func toggleCommandMode() {
        if isVisible {
            if purpose == .command, !isTranscribing {
                confirm()
            }
            return
        }
        show(.command)
    }

    private func show(_ requestedPurpose: PanelPurpose) {
        TextInjector.requestAccessibilityPermissionIfNeeded()
        let target = TextInjector.captureTarget()
        injectionTarget = target
        purpose = requestedPurpose
        lastCommandInstruction = nil
        retryOverride = nil

        if requestedPurpose == .command {
            let selected = target.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !selected.isEmpty else {
                presentErrorOnly("Select some text first, then press the Command shortcut.")
                return
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            presentRecordingPanel()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.presentRecordingPanel() }
                    else { self.presentMicrophoneError() }
                }
            }
        default:
            presentMicrophoneError()
        }
    }

    private func makePanel() -> RecordingView? {
        guard panel == nil else { return recordingView }
        let screenFrame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 54
        let frame = NSRect(
            x: screenFrame.midX - panelWidth / 2,
            y: screenFrame.minY + 112,
            width: panelWidth,
            height: panelHeight
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .alertPanel
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.shadowColor = NSColor.black.cgColor
        panel.contentView?.layer?.shadowOpacity = 0.22
        panel.contentView?.layer?.shadowRadius = 14
        panel.contentView?.layer?.shadowOffset = CGSize(width: 0, height: -5)

        let view = RecordingView(frame: NSRect(origin: .zero, size: frame.size))
        view.setPurpose(purpose)
        view.onCancel = { [weak self] in self?.cancel() }
        view.onConfirm = { [weak self] in self?.confirm() }
        view.onRetry = { [weak self] in self?.retry() }
        panel.contentView = view

        self.panel = panel
        recordingView = view
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        return view
    }

    private func presentRecordingPanel() {
        guard let view = makePanel() else { return }
        isTranscribing = false
        lastAudioData = nil

        recorder.startRecording()
        onRecordingControlsChanged?(true, !AppSettings.shared.holdToTalkEnabled)

        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            view.update(amplitudes: self.recorder.waveformAmplitudes, time: self.recorder.formattedTime)
        }
    }

    private func presentErrorOnly(_ message: String) {
        guard let view = makePanel() else { return }
        isTranscribing = false
        retryOverride = { [weak self] in self?.close() }
        view.showError(message, retryTitle: "Dismiss")
    }

    private func presentMicrophoneError() {
        guard let view = makePanel() else { return }
        retryOverride = { [weak self] in
            self?.close()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
        view.showError("Microphone access is required to record.", retryTitle: "Settings")
    }

    func confirm() {
        guard isVisible, !isTranscribing else { return }
        let target = injectionTarget ?? TextInjector.captureTarget()

        displayTimer?.invalidate()
        displayTimer = nil
        onRecordingControlsChanged?(false, false)
        isTranscribing = true
        recordingView?.setProcessingStatus(purpose == .command ? "Transcribing command…" : "Transcribing…")

        recorder.stopRecording { [weak self] url in
            guard let self else { return }
            guard let url else {
                self.isTranscribing = false
                self.recordingView?.showError("Recording failed. Please try again.")
                return
            }
            self.lastAudioData = try? Data(contentsOf: url)
            self.transcribe(url: url, target: target)
        }
    }

    func confirmFromHold() {
        if isVisible, purpose == .dictation, !isTranscribing { confirm() }
    }

    func cancelFromKeyboard() {
        guard isVisible, !isTranscribing else { return }
        cancel()
    }

    func confirmFromKeyboard() {
        guard isVisible, !isTranscribing, !AppSettings.shared.holdToTalkEnabled else { return }
        confirm()
    }

    private func transcribe(url: URL, target: InjectionTarget) {
        retryOverride = nil
        GroqTranscriptionService.shared.transcribe(audioURL: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        self.isTranscribing = false
                        self.recordingView?.showError("Got an empty transcription. Try speaking a little longer.")
                        return
                    }
                    if self.purpose == .command {
                        self.applyCommand(instruction: trimmed, target: target)
                    } else {
                        self.finishDictation(transcript: trimmed, target: target)
                    }

                case .failure(let error):
                    self.isTranscribing = false
                    let message = error.localizedDescription
                    self.recordingView?.showError(message.count > 120 ? String(message.prefix(120)) + "…" : message)
                }
            }
        }
    }

    private func finishDictation(transcript: String, target: InjectionTarget) {
        guard AppSettings.shared.smartProcessingEnabled else {
            finishAndInject(transcript, target: target, kind: .dictation)
            return
        }

        let mode = AppSettings.shared.smartProcessingMode
        recordingView?.setProcessingStatus("\(mode.rawValue) processing…")
        GroqLLMService.shared.processTranscript(transcript, mode: mode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let processed):
                    self.finishAndInject(processed, target: target, kind: .dictation)
                case .failure:
                    // Smart processing is intentionally fail-open: dictation should never be lost because the optional LLM pass failed.
                    self.finishAndInject(transcript, target: target, kind: .dictation)
                }
            }
        }
    }

    private func applyCommand(instruction: String, target: InjectionTarget) {
        guard let selectedText = target.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !selectedText.isEmpty else {
            isTranscribing = false
            recordingView?.showError("The selected text is no longer available. Select it again and retry.")
            return
        }

        lastCommandInstruction = instruction
        recordingView?.setProcessingStatus("Applying command…")
        GroqLLMService.shared.applyCommand(to: selectedText, instruction: instruction) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let replacement):
                    self.finishAndInject(replacement, target: target, kind: .command)
                case .failure(let error):
                    self.isTranscribing = false
                    let message = error.localizedDescription
                    self.retryOverride = { [weak self] in
                        guard let self, let instruction = self.lastCommandInstruction else { return }
                        self.isTranscribing = true
                        self.recordingView?.setProcessingStatus("Applying command…")
                        self.applyCommand(instruction: instruction, target: target)
                    }
                    self.recordingView?.showError(message.count > 120 ? String(message.prefix(120)) + "…" : message)
                }
            }
        }
    }

    private func finishAndInject(_ text: String, target: InjectionTarget, kind: InjectionKind) {
        isTranscribing = false
        close()
        TextInjector.inject(text, target: target, kind: kind)
    }

    private func retry() {
        if let retryOverride {
            retryOverride()
            return
        }
        guard let data = lastAudioData, !data.isEmpty else {
            recordingView?.showError("No audio is available to retry. Record again.")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vt_retry_\(UUID().uuidString).wav")
        do {
            try data.write(to: url)
        } catch {
            recordingView?.showError("Could not prepare the retry audio.")
            return
        }

        isTranscribing = true
        recordingView?.setProcessingStatus(purpose == .command ? "Transcribing command…" : "Transcribing…")
        let target = injectionTarget ?? TextInjector.captureTarget()
        transcribe(url: url, target: target)
    }

    private func cancel() {
        displayTimer?.invalidate()
        displayTimer = nil
        onRecordingControlsChanged?(false, false)
        recorder.cancelRecording()
        isTranscribing = false
        close()
    }

    func hide() { cancel() }

    private func close() {
        displayTimer?.invalidate()
        displayTimer = nil
        onRecordingControlsChanged?(false, false)

        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.13
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.panel = nil
            self?.recordingView = nil
            self?.injectionTarget = nil
            self?.lastAudioData = nil
            self?.lastCommandInstruction = nil
            self?.retryOverride = nil
            self?.isTranscribing = false
        }
    }
}
