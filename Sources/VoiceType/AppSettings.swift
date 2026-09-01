import Carbon
import Cocoa

// MARK: - Intelligence settings

enum SmartProcessingMode: String, CaseIterable {
    case raw = "Raw"
    case clean = "Clean"
    case polished = "Polished"

    var detail: String {
        switch self {
        case .raw: return "Correct spelling, casing and proper names while preserving your exact wording."
        case .clean: return "Also remove fillers, repetitions and obvious false starts."
        case .polished: return "Create fluent, send-ready text while preserving the original meaning."
        }
    }
}

enum GroqTextModel: String, CaseIterable {
    case gptOSS20B = "openai/gpt-oss-20b"
    case llama8B = "llama-3.1-8b-instant"
    case llama70B = "llama-3.3-70b-versatile"

    var title: String {
        switch self {
        case .gptOSS20B: return "GPT-OSS 20B — Fastest"
        case .llama8B: return "Llama 3.1 8B — Fast"
        case .llama70B: return "Llama 3.3 70B — Quality"
        }
    }
}

final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let commandHotkeyKeyCode = "commandHotkeyKeyCode"
        static let commandHotkeyModifiers = "commandHotkeyModifiers"
        static let groqAPIKey = "groqAPIKey"
        static let holdToTalk = "holdToTalkEnabled"
        static let microphoneDeviceUID = "microphoneDeviceUID"
        static let smartProcessingEnabled = "smartProcessingEnabled"
        static let smartProcessingMode = "smartProcessingMode"
        static let groqTextModel = "groqTextModel"
    }

    private let defaults = UserDefaults.standard

    var hotkeyKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Key.hotkeyKeyCode) == nil { return UInt32(kVK_Space) }
            return UInt32(defaults.integer(forKey: Key.hotkeyKeyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: Key.hotkeyModifiers) == nil { return UInt32(optionKey) }
            return UInt32(defaults.integer(forKey: Key.hotkeyModifiers))
        }
        set { defaults.set(Int(newValue), forKey: Key.hotkeyModifiers) }
    }

    var hotkeyDisplayString: String {
        ShortcutFormatter.displayString(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    var commandHotkeyKeyCode: UInt32 {
        get {
            if defaults.object(forKey: Key.commandHotkeyKeyCode) == nil { return UInt32(kVK_Space) }
            return UInt32(defaults.integer(forKey: Key.commandHotkeyKeyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.commandHotkeyKeyCode) }
    }

    var commandHotkeyModifiers: UInt32 {
        get {
            if defaults.object(forKey: Key.commandHotkeyModifiers) == nil {
                return UInt32(controlKey) | UInt32(optionKey)
            }
            return UInt32(defaults.integer(forKey: Key.commandHotkeyModifiers))
        }
        set { defaults.set(Int(newValue), forKey: Key.commandHotkeyModifiers) }
    }

    var commandHotkeyDisplayString: String {
        ShortcutFormatter.displayString(keyCode: commandHotkeyKeyCode, modifiers: commandHotkeyModifiers)
    }

    var groqAPIKey: String {
        get { defaults.string(forKey: Key.groqAPIKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.groqAPIKey) }
    }

    var holdToTalkEnabled: Bool {
        get { defaults.bool(forKey: Key.holdToTalk) }
        set { defaults.set(newValue, forKey: Key.holdToTalk) }
    }

    var microphoneDeviceUID: String? {
        get {
            guard let value = defaults.string(forKey: Key.microphoneDeviceUID), !value.isEmpty else { return nil }
            return value
        }
        set {
            if let newValue, !newValue.isEmpty { defaults.set(newValue, forKey: Key.microphoneDeviceUID) }
            else { defaults.removeObject(forKey: Key.microphoneDeviceUID) }
        }
    }

    // Off by default so the current low-latency transcription path stays unchanged.
    var smartProcessingEnabled: Bool {
        get { defaults.bool(forKey: Key.smartProcessingEnabled) }
        set { defaults.set(newValue, forKey: Key.smartProcessingEnabled) }
    }

    var smartProcessingMode: SmartProcessingMode {
        get { SmartProcessingMode(rawValue: defaults.string(forKey: Key.smartProcessingMode) ?? "") ?? .clean }
        set { defaults.set(newValue.rawValue, forKey: Key.smartProcessingMode) }
    }

    var groqTextModel: GroqTextModel {
        get { GroqTextModel(rawValue: defaults.string(forKey: Key.groqTextModel) ?? "") ?? .gptOSS20B }
        set { defaults.set(newValue.rawValue, forKey: Key.groqTextModel) }
    }

}

enum ShortcutFormatter {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let char = keyEquivalent(for: keyCode), !char.isEmpty { return char.uppercased() }
            return "Key \(keyCode)"
        }
    }

    private static func keyEquivalent(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }

        let data = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
