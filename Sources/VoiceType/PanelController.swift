import Cocoa
import AVFoundation
import QuartzCore

// MARK: - Waveform

class WaveformView: NSView {
    private var bars: [CALayer] = []
    private let count = 60
    private let bw: CGFloat = 2.6, gap: CGFloat = 1.4

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        for _ in 0..<count {
            let l = CALayer()
            l.backgroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
            l.cornerRadius = bw / 2
            l.masksToBounds = true
            layer?.addSublayer(l); bars.append(l)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ amps: [Float]) {
        let totalW = CGFloat(count) * (bw + gap) - gap
        let sx = (bounds.width - totalW) / 2, cy = bounds.height / 2
        CATransaction.begin(); CATransaction.setDisableActions(false); CATransaction.setAnimationDuration(0.08)
        for (i, bar) in bars.enumerated() {
            let a = CGFloat(i < amps.count ? amps[i] : 0)
            // smoother falloff, minimum 2.5
            let h = max(2.5, pow(a, 0.85) * bounds.height * 0.86)
            bar.frame = CGRect(x: sx + CGFloat(i)*(bw+gap), y: cy-h/2, width: bw, height: h)
            // color intensity by amplitude: quiet = translucent, loud = white + subtle glow
            let alpha: CGFloat = a > 0.55 ? 1.0 : a > 0.22 ? 0.72 : a > 0.05 ? 0.42 : 0.22
            bar.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
            bar.opacity = Float(alpha)
        }
        CATransaction.commit()
    }
}

// MARK: - RecordingView

class RecordingView: NSView {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDismissError: (() -> Void)?

    // Background blur
    private let effectView = NSVisualEffectView()
    private let borderLayer = CALayer()

    let waveform = WaveformView(frame: .zero)
    let timeLabel = NSTextField(labelWithString: "0:00")
    let statusLabel = NSTextField(labelWithString: "")
    let hintLabel = NSTextField(labelWithString: "")
    let cancelBtn = NSButton()
    let confirmBtn = NSButton()
    let retryBtn = NSButton()
    let spinner = NSProgressIndicator()
    let errorLabel = NSTextField(labelWithString: "")

    private var mode: Mode = .recording

    enum Mode { case recording, transcribing, error }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        // Visual effect background
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = frame.height / 2
        effectView.layer?.masksToBounds = true
        addSubview(effectView)

        // Subtle border via CALayer overlay
        borderLayer.cornerRadius = frame.height / 2
        borderLayer.borderWidth = 0.5
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        borderLayer.masksToBounds = true
        layer?.addSublayer(borderLayer)

        // Time / status
        timeLabel.textColor = .white.withAlphaComponent(0.92)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        timeLabel.alignment = .center
        timeLabel.backgroundColor = .clear
        timeLabel.isBezeled = false
        timeLabel.isEditable = false
        addSubview(timeLabel)

        statusLabel.textColor = .white.withAlphaComponent(0.92)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.backgroundColor = .clear
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.isHidden = true
        addSubview(statusLabel)

        // Hint (hold-to-talk)
        hintLabel.textColor = .white.withAlphaComponent(0.52)
        hintLabel.font = .systemFont(ofSize: 10, weight: .regular)
        hintLabel.alignment = .center
        hintLabel.backgroundColor = .clear
        hintLabel.isBezeled = false
        hintLabel.isEditable = false
        hintLabel.isHidden = true
        addSubview(hintLabel)

        // Error label
        errorLabel.textColor = NSColor.systemRed.withAlphaComponent(0.95)
        errorLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        errorLabel.alignment = .center
        errorLabel.backgroundColor = .clear
        errorLabel.isBezeled = false
        errorLabel.isEditable = false
        errorLabel.isHidden = true
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.cell?.wraps = true
        addSubview(errorLabel)

        // Spinner
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.appearance = NSAppearance(named: .vibrantDark)
        spinner.isHidden = true
        addSubview(spinner)

        // Waveform
        addSubview(waveform)

        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        // Cancel — translucent
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 17
        cancelBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        cancelBtn.layer?.borderWidth = 0.5
        cancelBtn.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        cancelBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        cancelBtn.contentTintColor = .white
        addSubview(cancelBtn)

        // Confirm — white pill
        confirmBtn.isBordered = false
        confirmBtn.wantsLayer = true
        confirmBtn.layer?.cornerRadius = 17
        confirmBtn.layer?.backgroundColor = NSColor.white.cgColor
        confirmBtn.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Confirm")?
            .withSymbolConfiguration(.init(pointSize: 12.5, weight: .bold))
        confirmBtn.contentTintColor = .black
        addSubview(confirmBtn)

        // Retry — white as well, but with arrow
        retryBtn.isBordered = false
        retryBtn.wantsLayer = true
        retryBtn.layer?.cornerRadius = 14
        retryBtn.layer?.backgroundColor = NSColor.white.cgColor
        retryBtn.title = "Retry"
        retryBtn.font = .systemFont(ofSize: 11, weight: .semibold)
        retryBtn.contentTintColor = .black
        retryBtn.isHidden = true
        addSubview(retryBtn)

        cancelBtn.target = self;  cancelBtn.action  = #selector(didCancel)
        confirmBtn.target = self; confirmBtn.action = #selector(didConfirm)
        retryBtn.target = self;   retryBtn.action   = #selector(didRetry)
    }

    override func layout() {
        super.layout()
        let r = bounds
        effectView.frame = r
        effectView.layer?.cornerRadius = r.height / 2
        borderLayer.frame = r
        borderLayer.cornerRadius = r.height / 2
        layer?.cornerRadius = r.height / 2
        // slight lift shadow is on panel, not here

        let h = r.height, pad: CGFloat = 8, bs: CGFloat = 34

        switch mode {
        case .recording, .transcribing:
            cancelBtn.frame  = CGRect(x: pad, y: (h-bs)/2, width: bs, height: bs)
            confirmBtn.frame = CGRect(x: r.width-pad-bs, y: (h-bs)/2, width: bs, height: bs)
            retryBtn.isHidden = true
            confirmBtn.isHidden = false

            if mode == .transcribing {
                waveform.frame = CGRect(x: cancelBtn.frame.maxX+8, y: 0, width: max(0, r.width - pad*2 - bs*2 - 16), height: h)
                timeLabel.isHidden = true
                statusLabel.isHidden = false
                statusLabel.frame = CGRect(x: waveform.frame.minX, y: (h-16)/2, width: waveform.frame.width, height: 16)
                errorLabel.isHidden = true
                hintLabel.isHidden = true
                spinner.frame = CGRect(x: confirmBtn.frame.minX - 22, y: (h-16)/2, width: 16, height: 16)
            } else {
                let tw: CGFloat = 44
                let tx = confirmBtn.frame.minX - tw - 6
                timeLabel.frame = CGRect(x: tx, y: (h-17)/2, width: tw, height: 17)
                statusLabel.isHidden = true
                spinner.isHidden = true
                errorLabel.isHidden = true
                hintLabel.isHidden = true
                waveform.frame = CGRect(
                    x: cancelBtn.frame.maxX + 8,
                    y: 2,
                    width: max(0, tx - 6 - (cancelBtn.frame.maxX + 8)),
                    height: h - 4
                )
            }

        case .error:
            cancelBtn.frame  = CGRect(x: pad, y: (h-bs)/2, width: bs, height: bs)
            cancelBtn.isHidden = false
            confirmBtn.isHidden = true
            waveform.isHidden = true
            timeLabel.isHidden = true
            statusLabel.isHidden = true
            spinner.isHidden = true
            hintLabel.isHidden = true

            let errW = r.width - pad*2 - bs*2 - 24
            let errX = cancelBtn.frame.maxX + 12
            errorLabel.frame = CGRect(x: errX, y: (h-30)/2, width: errW - 86, height: 30)
            errorLabel.isHidden = false
            retryBtn.frame = CGRect(x: r.width - pad - 72, y: (h-28)/2, width: 72, height: 28)
            retryBtn.isHidden = false
            waveform.isHidden = false // keep but hidden visually
        }
    }

    func update(amps: [Float], time: String) {
        guard mode == .recording else { return }
        waveform.update(amps)
        timeLabel.stringValue = time
    }

    func setTranscribing(_ on: Bool) {
        mode = on ? .transcribing : .recording
        waveform.isHidden = on
        timeLabel.isHidden = on
        statusLabel.isHidden = !on
        spinner.isHidden = !on
        errorLabel.isHidden = true
        retryBtn.isHidden = true
        cancelBtn.isEnabled = !on
        confirmBtn.isEnabled = !on
        if on {
            statusLabel.stringValue = "Transcribing…"
            hintLabel.isHidden = true
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func showError(_ message: String) {
        mode = .error
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        retryBtn.isHidden = false
        statusLabel.isHidden = true
        timeLabel.isHidden = true
        spinner.isHidden = true
        spinner.stopAnimation(nil)
        cancelBtn.isEnabled = true
        confirmBtn.isHidden = true
        waveform.isHidden = true
        hintLabel.isHidden = true
        // update layout
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func hideError() {
        mode = .recording
        errorLabel.isHidden = true
        retryBtn.isHidden = true
        waveform.isHidden = false
        timeLabel.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    @objc private func didCancel()  { onCancel?() }
    @objc private func didConfirm() { onConfirm?() }
    @objc private func didRetry()   { onRetry?() }
}

// MARK: - PanelController

class PanelController: NSObject {
    private var panel: NSPanel?
    private var recordingView: RecordingView?
    private var recorder = AudioRecorder()
    private var displayTimer: Timer?
    private var keyMonitor: Any?
    private var injectionTarget: InjectionTarget?
    private var lastAudioURL: URL?
    private var lastAudioData: Data?
    var isVisible: Bool { panel != nil }
    var isTranscribing: Bool = false

    func show() {
        TextInjector.requestAccessibilityPermissionIfNeeded()
        injectionTarget = TextInjector.captureTarget()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:        DispatchQueue.main.async { self.present() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { if ok { self.present() } else { self.showMicErrorInline() } }
            }
        default: DispatchQueue.main.async { self.showMicErrorInline() }
        }
    }

    private func present() {
        guard panel == nil else { return }
        let sf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let pw: CGFloat = 520, ph: CGFloat = 56
        let rect = NSRect(x: sf.midX-pw/2, y: sf.minY+128, width: pw, height: ph)

        let p = NSPanel(contentRect: rect, styleMask: [.borderless,.nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.animationBehavior = .alertPanel
        // soft shadow
        p.contentView?.wantsLayer = true
        p.contentView?.layer?.shadowColor = NSColor.black.cgColor
        p.contentView?.layer?.shadowOpacity = 0.28
        p.contentView?.layer?.shadowRadius = 18
        p.contentView?.layer?.shadowOffset = CGSize(width: 0, height: -8)

        let rv = RecordingView(frame: NSRect(origin: .zero, size: rect.size))
        rv.onCancel  = { [weak self] in self?.cancel() }
        rv.onConfirm = { [weak self] in self?.confirm() }
        rv.onRetry   = { [weak self] in self?.retry() }
        p.contentView = rv
        panel = p
        recordingView = rv
        isTranscribing = false
        lastAudioURL = nil
        lastAudioData = nil

        p.alphaValue = 0
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
        }

        recorder.startRecording()

        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            s.recordingView?.update(amps: s.recorder.waveformAmplitudes, time: s.recorder.formattedTime)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.cancel(); return nil }; return e
        }
    }

    private func cancel() {
        displayTimer?.invalidate(); displayTimer = nil
        recorder.cancelRecording()
        isTranscribing = false
        // clear retry state
        lastAudioURL = nil
        lastAudioData = nil
        close()
    }

    func confirm() {
        guard !isTranscribing else { return }
        let axTarget = injectionTarget ?? TextInjector.captureTarget()

        displayTimer?.invalidate(); displayTimer = nil
        isTranscribing = true
        recordingView?.setTranscribing(true)

        recorder.stopRecording { [weak self] url in
            guard let self else { return }
            guard let url else {
                self.isTranscribing = false
                self.recordingView?.showError("Recording failed. Please try again.")
                return
            }
            self.lastAudioURL = url
            self.lastAudioData = try? Data(contentsOf: url)
            self.transcribe(url: url, target: axTarget)
        }
    }

    // Called on hotkey release when hold-to-talk is enabled
    func confirmFromHold() {
        if isVisible && !isTranscribing {
            confirm()
        }
    }

    private func transcribe(url: URL, target: InjectionTarget) {
        GroqTranscriptionService.shared.transcribe(audioURL: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                    self.isTranscribing = false
                    self.close()
                    TextInjector.inject(text, target: target)
                case .success:
                    self.isTranscribing = false
                    self.recordingView?.showError("Got empty transcription. Try speaking a bit longer.")
                case .failure(let error):
                    self.isTranscribing = false
                    // Keep panel open, show inline error
                    let msg = error.localizedDescription
                    // truncate long server blobs
                    let short = msg.count > 110 ? String(msg.prefix(110)) + "…" : msg
                    self.recordingView?.showError(short)
                }
            }
        }
    }

    private func retry() {
        guard let data = lastAudioData, !data.isEmpty else {
            recordingView?.showError("No audio to retry. Please record again.")
            return
        }
        // Recreate temp file for retry if original was deleted
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vt_retry_\(Int(Date().timeIntervalSince1970)).wav")
        try? data.write(to: tmp)
        recordingView?.setTranscribing(true)
        isTranscribing = true
        let axTarget = injectionTarget ?? TextInjector.captureTarget()
        transcribe(url: tmp, target: axTarget)
    }

    private func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if let p = panel {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                p.animator().alphaValue = 0
            }, completionHandler: {
                p.orderOut(nil)
            })
        } else {
            panel?.orderOut(nil)
        }
        // delay nil to allow animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.panel = nil
            self?.recordingView = nil
            self?.isTranscribing = false
        }
    }

    func hide() { cancel() }

    private func showMicErrorInline() {
        // If panel not shown, show a lightweight inline panel with mic error
        if panel == nil {
            present()
            // give recorder a moment then show error
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.displayTimer?.invalidate()
                self?.recorder.cancelRecording()
                self?.recordingView?.showError("Microphone access denied. Enable in System Settings → Privacy → Microphone.")
                self?.recordingView?.onRetry = { [weak self] in
                    self?.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                // change retry title to Open Settings via hack: we set retryBtn title already, but for mic we want Open Settings
                self?.recordingView?.retryBtn.title = "Open Settings"
            }
        } else {
            recordingView?.showError("Microphone access denied. Enable in System Settings → Privacy → Microphone.")
        }
    }
}
