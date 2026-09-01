import AVFoundation

final class AudioRecorder: NSObject {
    private static let waveformHistoryCount = 18
    // Keep the engine warm for a few seconds after stopping so the next
    // dictation is instant. A fully torn-down engine needs 0.5-1.2s to
    // re-bring CoreAudio up — that's the 1-2s delay the user feels.
    private static let keepAliveSeconds: TimeInterval = 7.0

    var waveformAmplitudes: [Float] = Array(repeating: 0, count: waveformHistoryCount)
    var recordingTime: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var timer: Timer?
    private var tapInstalled = false
    private var keepAliveWorkItem: DispatchWorkItem?
    private var cachedFormat: AVAudioFormat?

    func startRecording() throws {
        guard audioFile == nil else { return }

        // Cancel any pending keep-alive teardown from the previous session.
        keepAliveWorkItem?.cancel()
        keepAliveWorkItem = nil

        let engine: AVAudioEngine
        let format: AVAudioFormat
        let shouldReuse = audioEngine != nil

        if let existing = audioEngine, shouldReuse {
            // Reuse the warm engine left over from the last recording (within 7s).
            // This skips ~400-800ms of CoreAudio bring-up.
            engine = existing
            // Engine was stopped but not torn down — input node is still valid.
            let input = engine.inputNode
            // Re-apply device selection only if it changed (fast path skips CoreAudio query).
            try SystemAudioInput.configure(input, deviceUID: AppSettings.shared.microphoneDeviceUID)
            format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw MicrophoneInputError.invalidFormat
            }
        } else {
            // Cold start — pay the CoreAudio bring-up cost once, then keep warm.
            let newEngine = AVAudioEngine()
            let input = newEngine.inputNode
            try SystemAudioInput.configure(input, deviceUID: AppSettings.shared.microphoneDeviceUID)
            let f = input.outputFormat(forBus: 0)
            guard f.sampleRate > 0, f.channelCount > 0 else {
                throw MicrophoneInputError.invalidFormat
            }
            engine = newEngine
            format = f
            audioEngine = engine
            cachedFormat = format
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt_\(UUID().uuidString).wav")
        tempFileURL = url
        waveformAmplitudes = Array(repeating: 0, count: Self.waveformHistoryCount)
        recordingTime = 0

        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let input = engine.inputNode
        // Ensure no stale tap before installing.
        if tapInstalled { input.removeTap(onBus: 0); tapInstalled = false }
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)

            let data = buffer.floatChannelData?[0]
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count { sum += abs(data?[index] ?? 0) }
            let average = min(sum / Float(max(count, 1)) * 18, 1.0)

            DispatchQueue.main.async {
                guard !self.waveformAmplitudes.isEmpty else { return }
                self.waveformAmplitudes.removeFirst()
                self.waveformAmplitudes.append(average)
            }
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeTapIfNeeded()
            audioFile = nil
            tempFileURL = nil
            scheduleKeepAliveTeardown(immediate: true)
            throw error
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingTime += 0.1
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        let url = tempFileURL
        cleanupRecordingState()
        completion(url)
    }

    func cancelRecording() {
        let url = tempFileURL
        cleanupRecordingState()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func cleanupRecordingState() {
        timer?.invalidate()
        timer = nil
        removeTapIfNeeded()
        audioFile = nil
        waveformAmplitudes = Array(repeating: 0, count: Self.waveformHistoryCount)
        recordingTime = 0
        tempFileURL = nil

        // Stop the graph immediately so the orange mic indicator disappears,
        // but keep the AVAudioEngine instance warm for a few seconds so the
        // next hotkey is instant. After the keep-alive window we fully tear
        // down to restore the Bluetooth headset profile.
        audioEngine?.stop()
        audioEngine?.reset()
        scheduleKeepAliveTeardown(immediate: false)
    }

    private func removeTapIfNeeded() {
        guard tapInstalled, let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func scheduleKeepAliveTeardown(immediate: Bool) {
        keepAliveWorkItem?.cancel()
        if immediate {
            tearDownEngine()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.tearDownEngine()
        }
        keepAliveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keepAliveSeconds, execute: work)
    }

    private func tearDownEngine() {
        keepAliveWorkItem?.cancel()
        keepAliveWorkItem = nil
        removeTapIfNeeded()
        audioEngine?.stop()
        audioEngine?.reset()
        audioEngine = nil
        cachedFormat = nil
    }

    var formattedTime: String {
        let total = Int(recordingTime)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    deinit {
        timer?.invalidate()
        tearDownEngine()
    }
}
