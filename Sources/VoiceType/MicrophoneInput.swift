import AVFoundation
import AudioToolbox
import Cocoa
import CoreAudio

struct SystemAudioInputDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum MicrophoneInputError: LocalizedError {
    case deviceUnavailable
    case configurationFailed(OSStatus)
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "The selected microphone is no longer available."
        case .configurationFailed(let status):
            return "Could not use the selected microphone (Core Audio \(status))."
        case .invalidFormat:
            return "The selected microphone did not provide a usable audio format."
        }
    }
}

enum SystemAudioInput {
    static func devices() -> [SystemAudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        let status = deviceIDs.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard inputChannelCount(for: deviceID) > 0,
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID),
                  let name = stringProperty(kAudioObjectPropertyName, deviceID: deviceID) else {
                return nil
            }
            return SystemAudioInputDevice(id: deviceID, uid: uid, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    static func device(uid: String) -> SystemAudioInputDevice? {
        devices().first { $0.uid == uid }
    }

    static func configure(_ inputNode: AVAudioInputNode, deviceUID: String?) throws {
        guard let deviceUID, !deviceUID.isEmpty else {
            // Auto mode intentionally leaves AVAudioEngine on the current macOS default input.
            return
        }
        guard let selected = device(uid: deviceUID) else {
            throw MicrophoneInputError.deviceUnavailable
        }
        guard let audioUnit = inputNode.audioUnit else {
            throw MicrophoneInputError.deviceUnavailable
        }

        var deviceID = selected.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw MicrophoneInputError.configurationFailed(status)
        }
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }

        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + $1.mNumberChannels }
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }
}

final class MicrophoneLevelMonitor {
    var onLevel: ((Float) -> Void)?

    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var smoothedLevel: Float = 0

    func start(deviceUID: String?) throws {
        stop()

        let engine = AVAudioEngine()
        self.engine = engine

        do {
            let input = engine.inputNode
            try SystemAudioInput.configure(input, deviceUID: deviceUID)
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw MicrophoneInputError.invalidFormat
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self, let channelData = buffer.floatChannelData else { return }
                let frames = Int(buffer.frameLength)
                let channels = Int(buffer.format.channelCount)
                guard frames > 0, channels > 0 else { return }

                var sumSquares: Float = 0
                for channel in 0..<channels {
                    let samples = channelData[channel]
                    for frame in 0..<frames {
                        let sample = samples[frame]
                        sumSquares += sample * sample
                    }
                }

                let rms = sqrt(sumSquares / Float(frames * channels))
                let decibels = 20 * log10(max(rms, 0.000_001))
                let normalized = min(max((decibels + 55) / 52, 0), 1)
                self.smoothedLevel = max(normalized, self.smoothedLevel * 0.82)
                let output = self.smoothedLevel

                DispatchQueue.main.async { [weak self] in
                    self?.onLevel?(output)
                }
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let engine, tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
        }
        engine?.stop()
        engine = nil
        tapInstalled = false
        smoothedLevel = 0
    }

    deinit {
        stop()
    }
}

final class MicrophoneLevelView: NSView {
    var level: Float = 0 {
        didSet {
            level = min(max(level, 0), 1)
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let segmentCount = 20
        let gap: CGFloat = 2.5
        let segmentWidth = max(2, (bounds.width - gap * CGFloat(segmentCount - 1)) / CGFloat(segmentCount))
        let activeSegments = Int(round(level * Float(segmentCount)))

        for index in 0..<segmentCount {
            let x = CGFloat(index) * (segmentWidth + gap)
            let rect = NSRect(x: x, y: 1, width: segmentWidth, height: max(2, bounds.height - 2))
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)

            let baseColor: NSColor
            if index < 13 {
                baseColor = .systemGreen
            } else if index < 17 {
                baseColor = .systemOrange
            } else {
                baseColor = .systemRed
            }

            baseColor.withAlphaComponent(index < activeSegments ? 0.95 : 0.14).setFill()
            path.fill()
        }
    }
}
