import AVFoundation

class AudioRecorder: NSObject {
    var waveformAmplitudes: [Float] = Array(repeating: 0, count: 60)
    var recordingTime: TimeInterval = 0
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var timer: Timer?

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt_\(Int(Date().timeIntervalSince1970)).wav")
        tempFileURL = url
        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        audioFile = try? AVAudioFile(forWriting: url, settings: fmt.settings)

        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            try? self?.audioFile?.write(from: buf)
            let data = buf.floatChannelData?[0]
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += abs(data?[i] ?? 0) }
            let avg = min(sum / Float(max(n, 1)) * 18, 1.0)
            DispatchQueue.main.async {
                self?.waveformAmplitudes.removeFirst()
                self?.waveformAmplitudes.append(avg)
            }
        }
        try? engine.start()
        recordingTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingTime += 0.1
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        cleanup()
        completion(tempFileURL)
    }

    func cancelRecording() {
        let url = tempFileURL
        cleanup()
        if let u = url { try? FileManager.default.removeItem(at: u) }
    }

    private func cleanup() {
        timer?.invalidate(); timer = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop(); audioEngine = nil
        audioFile = nil
        waveformAmplitudes = Array(repeating: 0, count: 60)
        recordingTime = 0
    }

    var formattedTime: String {
        let t = Int(recordingTime)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
