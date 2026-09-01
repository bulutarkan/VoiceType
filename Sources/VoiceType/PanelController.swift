import AVFoundation
import Cocoa
import QuartzCore

// MARK: - Recording panel models

enum PanelPurpose {
    case dictation
    case command
}

enum PanelActivity {
    case idle
    case recording
    case processing
    case error
}

private enum RecordingPanelMode {
    case recording
    case processing
    case error
}

// MARK: - Waveform

final class WaveformView: NSView {
    private let halfCount = 18
    private var bars: [CALayer] = []
    private let barWidth: CGFloat = 2.8
    private let gap: CGFloat = 3.0
    private var glowLayers: [CALayer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        for _ in 0..<(halfCount * 2) {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
            bar.cornerRadius = barWidth / 2
            bar.masksToBounds = false
            bar.shadowColor = NSColor.white.withAlphaComponent(0.35).cgColor
            bar.shadowOpacity = 0
            bar.shadowRadius = 4
            bar.shadowOffset = .zero
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ amplitudes: [Float]) {
        let recent = Array(amplitudes.suffix(halfCount))
        let totalWidth = CGFloat(bars.count) * (barWidth + gap) - gap
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.height / 2

        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.065)

        for (index, bar) in bars.enumerated() {
            let distanceFromCenter = index < halfCount
                ? halfCount - 1 - index
                : index - halfCount
            let sourceIndex = recent.count - 1 - distanceFromCenter
            let rawAmplitude = sourceIndex >= 0 ? recent[sourceIndex] : 0
            let amplitude = CGFloat(rawAmplitude)
            // More lively curve
            let height = max(3.0, pow(amplitude, 0.72) * bounds.height * 0.88)

            bar.frame = CGRect(
                x: startX + CGFloat(index) * (barWidth + gap),
                y: centerY - height / 2,
                width: barWidth,
                height: height
            )

            // Alpha + glow based on amplitude
            let alpha: CGFloat
            let glow: Float
            if amplitude > 0.62 {
                alpha = 1.0
                glow = 0.85
            } else if amplitude > 0.30 {
                alpha = 0.78
                glow = 0.45
            } else if amplitude > 0.08 {
                alpha = 0.48
                glow = 0.18
            } else {
                alpha = 0.22
                glow = 0
            }
            bar.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
            bar.opacity = Float(alpha * 0.96 + 0.04)
            bar.shadowOpacity = glow
            bar.cornerRadius = barWidth / 2
        }

        CATransaction.commit()
    }

    func setIdleBreathing(_ active: Bool) {
        // subtle breathing when silent
        for bar in bars {
            bar.removeAnimation(forKey: "breath")
            if active {
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = bar.opacity
                anim.toValue = max(0.14, bar.opacity * 0.6)
                anim.duration = 1.1
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(anim, forKey: "breath")
            }
        }
    }
}

// MARK: - RecordingView

final class RecordingView: NSView {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    var onRetry: (() -> Void)?

    let retryButton = NSButton()

    private let effectView = NSVisualEffectView()
    private let highlightLayer = CALayer()
    private let borderLayer = CALayer()
    private let waveform = WaveformView(frame: .zero)
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let dotView = NSView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private let processingLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton()
    private let confirmButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let errorIcon = NSImageView(frame: .zero)
    private let errorLabel = NSTextField(labelWithString: "")
    private let modeBadge = NSView(frame: .zero)
    private let modeBadgeLabel = NSTextField(labelWithString: "COMMAND")
    private let modeBadgeIcon = NSImageView(frame: .zero)

    private var panelMode: RecordingPanelMode = .recording
    private var purpose: PanelPurpose = .dictation
    private var dotPulse: CABasicAnimation?
    private var isWarming = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        // Unified visual effect — popover material is cleaner than hudWindow
        effectView.material = VTDesign.Material.panel
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = VTDesign.Radius.pill
        effectView.layer?.masksToBounds = true
        addSubview(effectView)

        // Top highlight for depth
        highlightLayer.cornerRadius = VTDesign.Radius.pill
        highlightLayer.borderWidth = 0
        highlightLayer.backgroundColor = NSColor.clear.cgColor
        highlightLayer.masksToBounds = true
        layer?.addSublayer(highlightLayer)

        borderLayer.cornerRadius = VTDesign.Radius.pill
        borderLayer.borderWidth = 0.6
        borderLayer.borderColor = VTDesign.Color.panelBorder.cgColor
        borderLayer.masksToBounds = true
        layer?.addSublayer(borderLayer)

        addSubview(waveform)

        // recording dot
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.shadowColor = NSColor.systemRed.withAlphaComponent(0.55).cgColor
        dotView.layer?.shadowRadius = 4
        dotView.layer?.shadowOpacity = 0.9
        dotView.layer?.shadowOffset = .zero
        addSubview(dotView)

        timeLabel.textColor = .white.withAlphaComponent(0.94)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        timeLabel.alignment = .center
        addSubview(timeLabel)

        // processing central label
        processingLabel.textColor = .white.withAlphaComponent(0.88)
        processingLabel.font = .systemFont(ofSize: 12, weight: .medium)
        processingLabel.alignment = .center
        processingLabel.isHidden = true
        addSubview(processingLabel)

        statusLabel.textColor = .white.withAlphaComponent(0.92)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        addSubview(statusLabel)

        // COMMAND badge — capsule with gradient
        modeBadge.wantsLayer = true
        modeBadge.layer?.cornerRadius = VTDesign.Radius.badge
        modeBadge.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.18).cgColor
        modeBadge.layer?.borderWidth = 0.5
        modeBadge.layer?.borderColor = NSColor.systemPurple.withAlphaComponent(0.22).cgColor
        modeBadge.isHidden = true
        modeBadgeIcon.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
        modeBadgeIcon.contentTintColor = NSColor.systemPurple.withAlphaComponent(0.92)
        modeBadge.addSubview(modeBadgeIcon)
        modeBadgeLabel.font = .systemFont(ofSize: 8.5, weight: .bold)
        modeBadgeLabel.textColor = NSColor.white.withAlphaComponent(0.86)
        modeBadgeLabel.alignment = .center
        modeBadge.addSubview(modeBadgeLabel)
        addSubview(modeBadge)

        errorIcon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        errorIcon.contentTintColor = NSColor.systemRed.withAlphaComponent(0.95)
        errorIcon.isHidden = true
        addSubview(errorIcon)

        errorLabel.textColor = NSColor.white.withAlphaComponent(0.96)
        errorLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
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
        startDotPulse()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        cancelButton.isBordered = false
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 16
        cancelButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cancelButton.layer?.borderWidth = 0.5
        cancelButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        cancelButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel")?
            .withSymbolConfiguration(.init(pointSize: 11.5, weight: .semibold))
        cancelButton.contentTintColor = .white
        cancelButton.target = self
        cancelButton.action = #selector(didCancel)
        // hover tracking
        let cancelTracker = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: ["btn": "cancel"])
        cancelButton.addTrackingArea(cancelTracker)
        addSubview(cancelButton)

        confirmButton.isBordered = false
        confirmButton.wantsLayer = true
        confirmButton.layer?.cornerRadius = 16
        confirmButton.layer?.backgroundColor = NSColor.white.cgColor
        confirmButton.layer?.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        confirmButton.layer?.shadowRadius = 6
        confirmButton.layer?.shadowOpacity = 0.9
        confirmButton.layer?.shadowOffset = CGSize(width: 0, height: 2)
        confirmButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Confirm")?
            .withSymbolConfiguration(.init(pointSize: 12.5, weight: .bold))
        confirmButton.contentTintColor = .black
        confirmButton.target = self
        confirmButton.action = #selector(didConfirm)
        addSubview(confirmButton)

        retryButton.isBordered = false
        retryButton.wantsLayer = true
        retryButton.layer?.cornerRadius = 14
        retryButton.layer?.backgroundColor = NSColor.white.cgColor
        retryButton.layer?.shadowColor = NSColor.black.withAlphaComponent(0.16).cgColor
        retryButton.layer?.shadowRadius = 6
        retryButton.layer?.shadowOpacity = 0.8
        retryButton.layer?.shadowOffset = CGSize(width: 0, height: 2)
        retryButton.title = "Retry"
        retryButton.font = .systemFont(ofSize: 12, weight: .semibold)
        retryButton.contentTintColor = .black
        retryButton.target = self
        retryButton.action = #selector(didRetry)
        retryButton.isHidden = true
        addSubview(retryButton)
    }

    private func startDotPulse() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.42
        pulse.duration = 0.85
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotView.layer?.add(pulse, forKey: "pulseScale")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.55
        fade.duration = 0.85
        fade.autoreverses = true
        fade.repeatCount = .infinity
        dotView.layer?.add(fade, forKey: "pulseOpacity")
    }

    func setWarming(_ warming: Bool) {
        isWarming = warming
        if warming {
            waveform.alphaValue = 0.38
            timeLabel.textColor = .white.withAlphaComponent(0.42)
            dotView.alphaValue = 0.45
            timeLabel.stringValue = "…"
        } else {
            waveform.alphaValue = 1.0
            timeLabel.textColor = .white.withAlphaComponent(0.94)
            dotView.alphaValue = 1.0
        }
        needsLayout = true
    }

    func setConfirmEnabled(_ enabled: Bool) {
        confirmButton.isEnabled = enabled
        confirmButton.alphaValue = enabled ? 1.0 : 0.42
        // also dim time while not ready? keep
    }

    func setPurpose(_ purpose: PanelPurpose) {
        self.purpose = purpose
        modeBadge.isHidden = purpose != .command
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let rect = bounds
        effectView.frame = rect
        effectView.layer?.cornerRadius = VTDesign.Radius.pill
        highlightLayer.frame = CGRect(x: 1, y: rect.height - 1.2, width: rect.width - 2, height: 1.2)
        highlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        highlightLayer.cornerRadius = VTDesign.Radius.pill
        borderLayer.frame = rect
        borderLayer.cornerRadius = VTDesign.Radius.pill

        let padding: CGFloat = 9
        let buttonSize: CGFloat = 32
        let centerY = (rect.height - buttonSize) / 2
        cancelButton.frame = CGRect(x: padding, y: centerY, width: buttonSize, height: buttonSize)

        switch panelMode {
        case .recording:
            cancelButton.isHidden = false
            confirmButton.isHidden = false
            retryButton.isHidden = true
            errorLabel.isHidden = true
            errorIcon.isHidden = true
            spinner.isHidden = true
            statusLabel.isHidden = true
            processingLabel.isHidden = true
            waveform.isHidden = false
            timeLabel.isHidden = false
            dotView.isHidden = false
            modeBadge.isHidden = purpose != .command

            confirmButton.frame = CGRect(x: rect.width - padding - buttonSize, y: centerY, width: buttonSize, height: buttonSize)
            let timeWidth: CGFloat = 42
            let timeX = confirmButton.frame.minX - timeWidth - 8
            // dot + time as unit
            dotView.frame = CGRect(x: timeX - 10, y: rect.height/2 - 4, width: 8, height: 8)
            dotView.layer?.cornerRadius = 4
            timeLabel.frame = CGRect(x: timeX, y: (rect.height - 16) / 2, width: timeWidth, height: 16)

            var left = cancelButton.frame.maxX + 12
            if purpose == .command {
                let badgeW: CGFloat = 92
                modeBadge.frame = CGRect(x: left, y: (rect.height - 18) / 2, width: badgeW, height: 18)
                modeBadge.layer?.cornerRadius = 9
                modeBadgeIcon.frame = CGRect(x: 8, y: 3, width: 12, height: 12)
                modeBadgeLabel.frame = CGRect(x: 22, y: 1, width: badgeW - 24, height: 16)
                modeBadgeLabel.stringValue = "COMMAND"
                left = modeBadge.frame.maxX + 10
            }
            let right = (dotView.frame.minX) - 10
            waveform.frame = CGRect(x: left, y: 10, width: max(0, right - left), height: rect.height - 20)

        case .processing:
            cancelButton.isHidden = true
            confirmButton.isHidden = true
            retryButton.isHidden = true
            errorLabel.isHidden = true
            errorIcon.isHidden = true
            waveform.isHidden = true
            timeLabel.isHidden = true
            dotView.isHidden = true
            modeBadge.isHidden = true
            statusLabel.isHidden = true
            spinner.isHidden = false
            processingLabel.isHidden = false
            // center spinner + label
            let totalW: CGFloat = 16 + 6 + processingLabel.intrinsicContentSize.width
            let startX = (rect.width - totalW) / 2
            spinner.frame = CGRect(x: startX, y: (rect.height - 16) / 2, width: 16, height: 16)
            processingLabel.frame = CGRect(x: spinner.frame.maxX + 8, y: (rect.height - 16)/2, width: processingLabel.intrinsicContentSize.width, height: 16)

        case .error:
            cancelButton.isHidden = false
            confirmButton.isHidden = true
            waveform.isHidden = true
            timeLabel.isHidden = true
            dotView.isHidden = true
            statusLabel.isHidden = true
            modeBadge.isHidden = true
            spinner.isHidden = true
            processingLabel.isHidden = true
            errorLabel.isHidden = false
            errorIcon.isHidden = false
            retryButton.isHidden = false
            retryButton.frame = CGRect(x: rect.width - padding - 78, y: (rect.height - 30) / 2, width: 78, height: 30)
            errorIcon.frame = CGRect(x: cancelButton.frame.maxX + 12, y: (rect.height - 14)/2, width: 14, height: 14)
            errorLabel.frame = CGRect(
                x: errorIcon.frame.maxX + 7,
                y: (rect.height - 18) / 2,
                width: max(0, retryButton.frame.minX - errorIcon.frame.maxX - 14),
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
        processingLabel.stringValue = text
        statusLabel.stringValue = text
        cancelButton.isEnabled = false
        spinner.startAnimation(nil)
        needsLayout = true
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

    func resetToRecording() {
        panelMode = .recording
        cancelButton.isEnabled = true
        spinner.stopAnimation(nil)
        needsLayout = true
    }

    @objc private func didCancel() { onCancel?() }
    @objc private func didConfirm() { onConfirm?() }
    @objc private func didRetry() { onRetry?() }

    override func mouseEntered(with event: NSEvent) {
        if let btn = event.trackingArea?.userInfo?["btn"] as? String, btn == "cancel" {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                cancelButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            }
        }
    }
    override func mouseExited(with event: NSEvent) {
        if let btn = event.trackingArea?.userInfo?["btn"] as? String, btn == "cancel" {
            cancelButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        }
    }
}

// MARK: - PanelController

final class PanelController: NSObject {
    private var panel: NSPanel?
    private var recordingView: RecordingView?
    private var recorder = AudioRecorder()
    private var displayTimer: Timer?
    private var injectionTarget: InjectionTarget?
    var onRecordingControlsChanged: ((Bool, Bool) -> Void)?
    var onActivityChanged: ((PanelActivity) -> Void)?
    private var lastAudioData: Data?
    private var lastCommandInstruction: String?
    private var retryOverride: (() -> Void)?
    private var isEngineReady = false
    private var pendingConfirm = false

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
        purpose = requestedPurpose
        lastCommandInstruction = nil
        retryOverride = nil

        if !TextInjector.isAccessibilityTrusted {
            TextInjector.requestAccessibilityPermissionIfNeeded()
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecordingAndPresent()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.startRecordingAndPresent() }
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
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 64
        let frame = NSRect(
            x: screenFrame.midX - panelWidth / 2,
            y: screenFrame.minY + 118,
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
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .alertPanel
        panel.contentView?.wantsLayer = true
        // Double shadow via contentView layer
        panel.contentView?.layer?.shadowColor = NSColor.black.cgColor
        panel.contentView?.layer?.shadowOpacity = 0.26
        panel.contentView?.layer?.shadowRadius = 24
        panel.contentView?.layer?.shadowOffset = CGSize(width: 0, height: -10)
        // inner second shadow via extra shadow path could be added, keep simple

        let view = RecordingView(frame: NSRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        view.setPurpose(purpose)
        view.onCancel = { [weak self] in self?.cancel() }
        view.onConfirm = { [weak self] in self?.confirm() }
        view.onRetry = { [weak self] in self?.retry() }
        panel.contentView = view

        self.panel = panel
        recordingView = view
        panel.alphaValue = 0
        // subtle scale-in
        panel.contentView?.layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = VTDesign.Animation.panelFade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.contentView?.layer?.transform = CATransform3DIdentity
        }

        return view
    }

    private func resizePanel(width: CGFloat, animated: Bool = true) {
        guard let panel else { return }
        let current = panel.frame
        let newFrame = NSRect(
            x: current.midX - width / 2,
            y: current.minY,
            width: width,
            height: current.height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    private func showProcessing(_ text: String) {
        onActivityChanged?(.processing)
        recordingView?.setProcessingStatus(text)
        // measure text width for pill
        let textW = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
        let targetW = min(420, max(200, 16 + 8 + textW + 32))
        resizePanel(width: targetW)
    }

    private func showErrorMessage(_ message: String, retryTitle: String = "Retry") {
        onActivityChanged?(.error)
        resizePanel(width: 480)
        recordingView?.showError(message, retryTitle: retryTitle)
    }

    private func startRecordingAndPresent() {
        guard panel == nil else { return }
        isTranscribing = false
        lastAudioData = nil
        isEngineReady = false
        pendingConfirm = false

        // Capture the AX target before the panel steals focus — must be fast.
        let target = TextInjector.captureTarget()
        injectionTarget = target

        if purpose == .command {
            let selected = target.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !selected.isEmpty else {
                presentErrorOnly("Select some text first, then press the Command shortcut.")
                return
            }
        }

        guard let view = makePanel() else {
            return
        }

        view.resetToRecording()
        view.setWarming(true)
        view.setConfirmEnabled(false)
        onActivityChanged?(.recording)
        onRecordingControlsChanged?(true, !AppSettings.shared.holdToTalkEnabled)

        // Show panel immediately; waveform stays dimmed until the engine is actually
        // capturing. This makes the hotkey feel instant even though CoreAudio
        // needs ~300-900ms to bring the input node up.
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isEngineReady {
                view.update(amplitudes: self.recorder.waveformAmplitudes, time: self.recorder.formattedTime)
            } else {
                // Keep timer at 0:00 while warming so the user sees "ready" only when we are truly recording
                view.update(amplitudes: Array(repeating: 0, count: 18), time: "0:00")
            }
        }

        // Start the audio graph on the next run-loop turn. Because the panel is
        // already on screen the 0.5-1.5s CoreAudio bring-up no longer feels like
        // a frozen hotkey.
        let startTime = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // User may have hit Esc / Cmd+Q while we were warming.
            guard self.panel != nil, self.recordingView != nil else { return }
            do {
                try self.recorder.startRecording()
                self.isEngineReady = true
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                // Keep the warmup cue visible for at least 160ms so it doesn't flash.
                let minWarmup: Double = 0.16
                let delay = max(0, minWarmup - elapsed)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.panel != nil else { return }
                    self.recordingView?.setWarming(false)
                    self.recordingView?.setConfirmEnabled(true)
                    if self.pendingConfirm {
                        self.pendingConfirm = false
                        self.confirm()
                    }
                }
            } catch {
                self.isEngineReady = false
                self.displayTimer?.invalidate()
                self.displayTimer = nil
                self.onRecordingControlsChanged?(false, false)
                self.presentErrorOnly("Could not start the microphone. Please try again.")
            }
        }
    }

    private func presentErrorOnly(_ message: String) {
        guard makePanel() != nil else { return }
        isTranscribing = false
        retryOverride = { [weak self] in self?.close() }
        showErrorMessage(message, retryTitle: "Dismiss")
    }

    private func presentMicrophoneError() {
        guard makePanel() != nil else { return }
        retryOverride = { [weak self] in
            self?.close()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
        showErrorMessage("Microphone access is required to record.", retryTitle: "Settings")
    }

    func confirm() {
        guard isVisible, !isTranscribing else { return }
        // If the audio graph hasn't finished starting yet, queue the confirm.
        // This makes hold-to-talk feel instant even if the user releases the
        // key during the ~0.5s CoreAudio bring-up.
        if !isEngineReady {
            pendingConfirm = true
            recordingView?.setWarming(true)
            // Keep the orange indicator and timer visible until we actually stop
            return
        }
        let target = injectionTarget ?? TextInjector.captureTarget()

        displayTimer?.invalidate()
        displayTimer = nil
        onRecordingControlsChanged?(false, false)
        isTranscribing = true
        isEngineReady = false
        pendingConfirm = false
        showProcessing(purpose == .command ? "Transcribing command…" : "Transcribing…")

        recorder.stopRecording { [weak self] url in
            guard let self else { return }
            guard let url else {
                self.isTranscribing = false
                self.showErrorMessage("Recording failed. Please try again.")
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
                        self.showErrorMessage("Got an empty transcription. Try speaking a little longer.")
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
                    self.showErrorMessage(message.count > 120 ? String(message.prefix(120)) + "…" : message)
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
        showProcessing("\(mode.rawValue) processing…")
        GroqLLMService.shared.processTranscript(transcript, mode: mode) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let processed):
                    self.finishAndInject(processed, target: target, kind: .dictation)
                case .failure:
                    self.finishAndInject(transcript, target: target, kind: .dictation)
                }
            }
        }
    }

    private func applyCommand(instruction: String, target: InjectionTarget) {
        guard let selectedText = target.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !selectedText.isEmpty else {
            isTranscribing = false
            showErrorMessage("The selected text is no longer available. Select it again and retry.")
            return
        }

        lastCommandInstruction = instruction
        showProcessing("Applying command…")
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
                        self.showProcessing("Applying command…")
                        self.applyCommand(instruction: instruction, target: target)
                    }
                    self.showErrorMessage(message.count > 120 ? String(message.prefix(120)) + "…" : message)
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
            showErrorMessage("No audio is available to retry. Record again.")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vt_retry_\(UUID().uuidString).wav")
        do {
            try data.write(to: url)
        } catch {
            showErrorMessage("Could not prepare the retry audio.")
            return
        }

        isTranscribing = true
        showProcessing(purpose == .command ? "Transcribing command…" : "Transcribing…")
        let target = injectionTarget ?? TextInjector.captureTarget()
        transcribe(url: url, target: target)
    }

    private func cancel() {
        displayTimer?.invalidate()
        displayTimer = nil
        onRecordingControlsChanged?(false, false)
        isEngineReady = false
        pendingConfirm = false
        recorder.cancelRecording()
        isTranscribing = false
        close()
    }

    func hide() { cancel() }

    private func close() {
        displayTimer?.invalidate()
        displayTimer = nil
        onRecordingControlsChanged?(false, false)
        onActivityChanged?(.idle)
        isEngineReady = false
        pendingConfirm = false

        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.contentView?.layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        }, completionHandler: { panel.orderOut(nil) })

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
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
