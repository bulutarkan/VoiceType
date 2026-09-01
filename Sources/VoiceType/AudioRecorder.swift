import AVFoundation

final class AudioRecorder: NSObject {
    private static let waveformHistoryCount = 18

    var waveformAmplitudes: [Float] = Array(repeating: 0, count: waveformHistoryCount)
    var recordingTime: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var timer: Timer?
    private var tapInstalled = false
    private var preparedDeviceUID: String?
    private var preparedFormat: AVAudioFormat?

    override init() {
        super.init()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            prewarm()
        }
    }

    /// Prepares the audio graph without starting the microphone. This removes most
    /// of the one-time AVAudioEngine setup cost from the hotkey press path.
    func prewarm() {
        try? prepareEngineIfNeeded()
    }

    func startRecording() throws {
        guard audioFile == nil else { return }
        try prepareEngineIfNeeded()

        guard let engine = audioEngine, let format = preparedFormat else {
            throw MicrophoneInputError.invalidFormat
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt_\(UUID().uuidString).wav")
        tempFileURL = url
        waveformAmplitudes = Array(repeating: 0, count: Self.waveformHistoryCount)
        recordingTime = 0

        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let input = engine.inputNode
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

    private func prepareEngineIfNeeded() throws {
        let requestedUID = AppSettings.shared.microphoneDeviceUID
        if audioEngine != nil,
           preparedFormat != nil,
           preparedDeviceUID == requestedUID {
            return
        }

        tearDownEngine()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        try SystemAudioInput.configure(input, deviceUID: requestedUID)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneInputError.invalidFormat
        }

        engine.prepare()
        audioEngine = engine
        preparedFormat = format
        preparedDeviceUID = requestedUID
    }

    private func cleanupRecordingState() {
        timer?.invalidate()
        timer = nil
        removeTapIfNeeded()
        audioEngine?.stop()
        audioFile = nil
        waveformAmplitudes = Array(repeating: 0, count: Self.waveformHistoryCount)
        recordingTime = 0
        tempFileURL = nil
    }

    private func removeTapIfNeeded() {
        guard tapInstalled, let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func tearDownEngine() {
        removeTapIfNeeded()
        audioEngine?.stop()
        audioEngine = nil
        preparedFormat = nil
        preparedDeviceUID = nil
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
