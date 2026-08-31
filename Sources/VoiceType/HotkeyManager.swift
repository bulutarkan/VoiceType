import Carbon
import Cocoa

private var _hotKeyRef: EventHotKeyRef?
private var _handlerRef: EventHandlerRef?
private var _onPress: (() -> Void)?
private var _onRelease: (() -> Void)?

class HotkeyManager {
    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        _onPress = onPress
        _onRelease = onRelease
    }

    // Legacy single-callback initializer for backward compatibility
    convenience init(callback: @escaping () -> Void) {
        self.init(onPress: callback, onRelease: {})
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
                guard let e = event else { return noErr }
                let kind = GetEventKind(e)
                if kind == UInt32(kEventHotKeyPressed) {
                    _onPress?()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    _onRelease?()
                }
                return noErr
            },
            2, &specs, nil, &_handlerRef
        )
        let hkID = EventHotKeyID(signature: 0x56545950, id: 1)
        RegisterEventHotKey(AppSettings.shared.hotkeyKeyCode, AppSettings.shared.hotkeyModifiers, hkID,
                            GetApplicationEventTarget(), 0, &_hotKeyRef)
    }

    func unregister() {
        if let r = _hotKeyRef { UnregisterEventHotKey(r) }
        if let h = _handlerRef { RemoveEventHandler(h) }
        _hotKeyRef = nil
        _handlerRef = nil
    }

    func updateShortcut() {
        register()
    }
}
