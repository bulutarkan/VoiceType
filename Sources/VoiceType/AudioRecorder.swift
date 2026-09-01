import AVFoundation

final class AudioRecorder: NSObject {
    var waveformAmplitudes: [Float] = Array(repeating: 0, count: 60)
    var recordingTime: TimeInterval = 0
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var timer: Timer?

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt_\(UUID().uuidString).wav")
        tempFileURL = url

        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        try? SystemAudioInput.configure(input, deviceUID: AppSettings.shared.microphoneDeviceUID)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        audioFile = try? AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            let data = buffer.floatChannelData?[0]
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count { sum += abs(data?[index] ?? 0) }
            let average = min(sum / Float(max(count, 1)) * 18, 1.0)
            DispatchQueue.main.async {
                self.waveformAmplitudes.removeFirst()
                self.waveformAmplitudes.append(average)
            }
        }

        engine.prepare()
        try? engine.start()
        recordingTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingTime += 0.1
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        let url = tempFileURL
        cleanup()
        completion(url)
    }

    func cancelRecording() {
        let url = tempFileURL
        cleanup()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        audioFile = nil
        waveformAmplitudes = Array(repeating: 0, count: 60)
        recordingTime = 0
        tempFileURL = nil
    }

    var formattedTime: String {
        let total = Int(recordingTime)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
