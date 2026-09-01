import Cocoa

struct InjectionTarget {
    let element: AXUIElement?
    let app: NSRunningApplication?
    let selectedText: String?
}

enum InjectionKind: String {
    case dictation = "Dictation"
    case command = "Command"
}

final class TextInjector {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermissionIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func captureTarget() -> InjectionTarget {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedElement: AXUIElement?

        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedRef {
            focusedElement = (focusedRef as! AXUIElement)
        } else {
            focusedElement = nil
        }

        var selectedText: String?
        if let focusedElement {
            var selectedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
               let value = selectedRef as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedText = value
            }
        }

        return InjectionTarget(
            element: focusedElement,
            app: NSWorkspace.shared.frontmostApplication,
            selectedText: selectedText
        )
    }

    static func inject(_ rawText: String, target: InjectionTarget, kind: InjectionKind = .dictation) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        copyToPasteboard(text)
        TranscriptionHistory.shared.add(text, appName: target.app?.localizedName, kind: kind.rawValue)

        guard isAccessibilityTrusted else {
            showAccessibilityAlert()
            return
        }
        guard target.element != nil else { return }
        pasteIntoOriginalTarget(target)
    }

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func pasteIntoOriginalTarget(_ target: InjectionTarget) {
        target.app?.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            refocus(target.element)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                postCommandV()
            }
        }
    }

    private static func refocus(_ element: AXUIElement?) {
        guard let element else { return }
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyV: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Text was copied to the clipboard. To enable auto-paste, grant VoiceType access in System Settings → Privacy & Security → Accessibility."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
