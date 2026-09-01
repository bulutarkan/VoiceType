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

    func startRecording() throws {
        guard audioFile == nil else { return }

        // Important: create and own the input graph only while an actual recording
        // is active. Keeping AVAudioEngine.inputNode prepared while VoiceType is idle
        // can force Bluetooth headsets into their hands-free/mono audio profile.
        tearDownEngine()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        try SystemAudioInput.configure(input, deviceUID: AppSettings.shared.microphoneDeviceUID)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneInputError.invalidFormat
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt_\(UUID().uuidString).wav")
        tempFileURL = url
        waveformAmplitudes = Array(repeating: 0, count: Self.waveformHistoryCount)
        recordingTime = 0

        audioEngine = engine
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
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
            tearDownEngine()
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

        // Fully release the input node after every recording/cancel. A stopped but
        // retained AVAudioEngine can still keep Bluetooth audio in hands-free mode.
        tearDownEngine()
    }

    private func removeTapIfNeeded() {
        guard tapInstalled, let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func tearDownEngine() {
        removeTapIfNeeded()
        audioEngine?.stop()
        audioEngine?.reset()
        audioEngine = nil
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
