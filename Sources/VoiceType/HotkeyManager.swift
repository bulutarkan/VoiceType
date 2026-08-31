import Carbon
import Cocoa

private var _hotKeyRef: EventHotKeyRef?
private var _handlerRef: EventHandlerRef?
private var _callback: (() -> Void)?

class HotkeyManager {
    init(callback: @escaping () -> Void) {
        _callback = callback
    }

    func register() {
        unregister()
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in _callback?(); return noErr },
            1, &eventSpec, nil, &_handlerRef
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
