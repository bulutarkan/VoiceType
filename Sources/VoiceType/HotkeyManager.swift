import Carbon
import Cocoa

private var _dictationHotKeyRef: EventHotKeyRef?
private var _commandHotKeyRef: EventHotKeyRef?
private var _recordingCancelHotKeyRef: EventHotKeyRef?
private var _recordingConfirmHotKeyRef: EventHotKeyRef?
private var _handlerRef: EventHandlerRef?
private var _onDictationPress: (() -> Void)?
private var _onDictationRelease: (() -> Void)?
private var _onCommandPress: (() -> Void)?
private var _onRecordingCancel: (() -> Void)?
private var _onRecordingConfirm: (() -> Void)?

final class HotkeyManager {
    init(
        onDictationPress: @escaping () -> Void,
        onDictationRelease: @escaping () -> Void,
        onCommandPress: @escaping () -> Void,
        onRecordingCancel: @escaping () -> Void,
        onRecordingConfirm: @escaping () -> Void
    ) {
        _onDictationPress = onDictationPress
        _onDictationRelease = onDictationRelease
        _onCommandPress = onCommandPress
        _onRecordingCancel = onRecordingCancel
        _onRecordingConfirm = onRecordingConfirm
    }

    func register() {
        unregister()

        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let kind = GetEventKind(event)
                switch hotKeyID.id {
                case 1:
                    if kind == UInt32(kEventHotKeyPressed) { _onDictationPress?() }
                    else if kind == UInt32(kEventHotKeyReleased) { _onDictationRelease?() }
                case 2:
                    if kind == UInt32(kEventHotKeyPressed) { _onCommandPress?() }
                case 3:
                    if kind == UInt32(kEventHotKeyPressed) { _onRecordingCancel?() }
                case 4:
                    if kind == UInt32(kEventHotKeyPressed) { _onRecordingConfirm?() }
                default:
                    break
                }
                return noErr
            },
            2,
            &specs,
            nil,
            &_handlerRef
        )

        let dictationID = EventHotKeyID(signature: 0x56545950, id: 1)
        RegisterEventHotKey(
            AppSettings.shared.hotkeyKeyCode,
            AppSettings.shared.hotkeyModifiers,
            dictationID,
            GetApplicationEventTarget(),
            0,
            &_dictationHotKeyRef
        )

        let commandID = EventHotKeyID(signature: 0x56545950, id: 2)
        RegisterEventHotKey(
            AppSettings.shared.commandHotkeyKeyCode,
            AppSettings.shared.commandHotkeyModifiers,
            commandID,
            GetApplicationEventTarget(),
            0,
            &_commandHotKeyRef
        )
    }

    func setRecordingControlsActive(_ active: Bool, enterEnabled: Bool) {
        unregisterRecordingControls()
        guard active else { return }

        let escapeID = EventHotKeyID(signature: 0x56545950, id: 3)
        RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            escapeID,
            GetApplicationEventTarget(),
            0,
            &_recordingCancelHotKeyRef
        )

        guard enterEnabled else { return }
        let enterID = EventHotKeyID(signature: 0x56545950, id: 4)
        RegisterEventHotKey(
            UInt32(kVK_Return),
            0,
            enterID,
            GetApplicationEventTarget(),
            0,
            &_recordingConfirmHotKeyRef
        )
    }

    func unregister() {
        unregisterRecordingControls()
        if let ref = _dictationHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = _commandHotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = _handlerRef { RemoveEventHandler(handler) }
        _dictationHotKeyRef = nil
        _commandHotKeyRef = nil
        _handlerRef = nil
    }

    func updateShortcuts() {
        register()
    }

    private func unregisterRecordingControls() {
        if let ref = _recordingCancelHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = _recordingConfirmHotKeyRef { UnregisterEventHotKey(ref) }
        _recordingCancelHotKeyRef = nil
        _recordingConfirmHotKeyRef = nil
    }
}
