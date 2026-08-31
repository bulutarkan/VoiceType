import Cocoa
import AVFoundation
import QuartzCore

class WaveformView: NSView {
    private var bars: [CALayer] = []
    private let count = 60
    private let bw: CGFloat = 2.5, gap: CGFloat = 1.5

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<count {
            let l = CALayer()
            l.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
            l.cornerRadius = bw / 2
            layer?.addSublayer(l); bars.append(l)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ amps: [Float]) {
        let totalW = CGFloat(count) * (bw + gap) - gap
        let sx = (bounds.width - totalW) / 2, cy = bounds.height / 2
        CATransaction.begin(); CATransaction.setAnimationDuration(0.07)
        for (i, bar) in bars.enumerated() {
            let a = CGFloat(i < amps.count ? amps[i] : 0)
            let h = max(3, a * bounds.height * 0.88)
            bar.frame = CGRect(x: sx + CGFloat(i)*(bw+gap), y: cy-h/2, width: bw, height: h)
            bar.backgroundColor = NSColor.white.withAlphaComponent(a > 0.5 ? 1.0 : a > 0.15 ? 0.72 : 0.35).cgColor
        }
        CATransaction.commit()
    }
}

class RecordingView: NSView {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    let waveform = WaveformView(frame: .zero)
    let timeLabel = NSTextField(labelWithString: "0:00")
    let cancelBtn = NSButton()
    let confirmBtn = NSButton()
    let spinner = NSProgressIndicator()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red:0.12,green:0.12,blue:0.12,alpha:0.97).cgColor
        layer?.cornerRadius = frame.height / 2
        setupButtons(); addSubview(waveform)
        timeLabel.textColor = .white.withAlphaComponent(0.82)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.alignment = .center; addSubview(timeLabel)
        spinner.style = .spinning; spinner.controlSize = .small
        spinner.isHidden = true; addSubview(spinner)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        for (btn, icon, bg, tint) in [
            (cancelBtn,  "xmark",     NSColor.white.withAlphaComponent(0.18), NSColor.white),
            (confirmBtn, "checkmark", NSColor.white,                           NSColor.black)
        ] {
            btn.isBordered = false; btn.wantsLayer = true
            btn.layer?.cornerRadius = 17
            btn.layer?.backgroundColor = bg.cgColor
            btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
            btn.contentTintColor = tint; addSubview(btn)
        }
        cancelBtn.target = self;  cancelBtn.action  = #selector(didCancel)
        confirmBtn.target = self; confirmBtn.action = #selector(didConfirm)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let h = bounds.height, pad: CGFloat = 10, bs: CGFloat = 34
        cancelBtn.frame  = CGRect(x: pad, y: (h-bs)/2, width: bs, height: bs)
        confirmBtn.frame = CGRect(x: bounds.width-pad-bs, y: (h-bs)/2, width: bs, height: bs)
        let tw: CGFloat = 38, tx = confirmBtn.frame.minX - tw - 5
        timeLabel.frame = CGRect(x: tx, y: (h-17)/2, width: tw, height: 17)
        spinner.frame   = CGRect(x: tx+(tw-16)/2, y: (h-16)/2, width: 16, height: 16)
        waveform.frame  = CGRect(x: cancelBtn.frame.maxX+8, y: 0, width: max(0, tx-5-(cancelBtn.frame.maxX+8)), height: h)
    }

    func update(amps: [Float], time: String) { waveform.update(amps); timeLabel.stringValue = time }
    func setTranscribing(_ on: Bool) {
        timeLabel.isHidden = on; spinner.isHidden = !on
        cancelBtn.isEnabled = !on; confirmBtn.isEnabled = !on
        on ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }
    @objc private func didCancel()  { onCancel?() }
    @objc private func didConfirm() { onConfirm?() }
}

class PanelController: NSObject {
    private var panel: NSPanel?
    private var recordingView: RecordingView?
    private var recorder = AudioRecorder()
    private var displayTimer: Timer?
    private var keyMonitor: Any?
    private var injectionTarget: InjectionTarget?
    private(set) var isVisible = false

    func show() {
        TextInjector.requestAccessibilityPermissionIfNeeded()
        injectionTarget = TextInjector.captureTarget()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:        DispatchQueue.main.async { self.present() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { if ok { self.present() } }
            }
        default: DispatchQueue.main.async { self.showPermAlert() }
        }
    }

    private func present() {
        guard !isVisible else { return }
        let sf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let pw: CGFloat = 480, ph: CGFloat = 52
        let rect = NSRect(x: sf.midX-pw/2, y: sf.minY+130, width: pw, height: ph)

        let p = NSPanel(contentRect: rect, styleMask: [.borderless,.nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating; p.isOpaque = false; p.backgroundColor = .clear
        p.hasShadow = true; p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rv = RecordingView(frame: NSRect(origin: .zero, size: rect.size))
        rv.onCancel  = { [weak self] in self?.cancel() }
        rv.onConfirm = { [weak self] in self?.confirm() }
        p.contentView = rv; panel = p; recordingView = rv; isVisible = true
        p.orderFront(nil)
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
        recorder.cancelRecording(); close()
    }

    private func confirm() {
        let axTarget = injectionTarget ?? TextInjector.captureTarget()

        displayTimer?.invalidate(); displayTimer = nil
        recordingView?.setTranscribing(true)
        recorder.stopRecording { [weak self] url in
            self?.close()
            guard let url = url else { return }
            GroqTranscriptionService.shared.transcribe(audioURL: url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text) where !text.isEmpty:
                        TextInjector.inject(text, target: axTarget)
                    case .success:
                        self?.showTranscriptionAlert("Transkripsiyon boş döndü.")
                    case .failure(let error):
                        self?.showTranscriptionAlert(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        panel?.orderOut(nil); panel = nil; recordingView = nil; isVisible = false
    }
    func hide() { cancel() }

    private func showPermAlert() {
        let a = NSAlert()
        a.messageText = "Mikrofon İzni Gerekli"
        a.informativeText = "Sistem Ayarları → Gizlilik → Mikrofon'dan izin ver."
        a.addButton(withTitle: "Sistem Ayarlarını Aç"); a.addButton(withTitle: "İptal")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func showTranscriptionAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Transkripsiyon Alınamadı"
        alert.informativeText = message
        alert.addButton(withTitle: "Tamam")
        alert.runModal()
    }
}
