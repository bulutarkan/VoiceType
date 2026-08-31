import Cocoa

struct InjectionTarget {
    let element: AXUIElement?
    let app: NSRunningApplication?
}

class TextInjector {

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermissionIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // Panel açılmadan önce hedefi yakalıyoruz; button click / overlay focus'u bozmasın.
    static func captureTarget() -> InjectionTarget {
        let sys = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        let focusedElement: AXUIElement?

        if AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
           let r = ref {
            focusedElement = (r as! AXUIElement)
        } else {
            focusedElement = nil
        }

        return InjectionTarget(element: focusedElement, app: NSWorkspace.shared.frontmostApplication)
    }

    static func inject(_ rawText: String, target: InjectionTarget) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Core guarantee: transcript is always copied to the pasteboard.
        // If injection fails, user can still press Cmd+V manually.
        copyToPasteboard(text)
        TranscriptionHistory.shared.add(text)

        guard isAccessibilityTrusted else {
            showAccessibilityAlert()
            return
        }

        // Only paste if we captured a valid focused element; otherwise keep it in clipboard.
        guard target.element != nil else { return }

        pasteIntoOriginalTarget(target)
    }

    private static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private static func pasteIntoOriginalTarget(_ target: InjectionTarget) {
        // Bring the original app back to front after the recording panel closes.
        if let app = target.app {
            app.activate(options: [])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            refocus(target.element)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                postCommandV()
                // Intentionally keep clipboard — if paste fails, transcript remains available.
            }
        }
    }

    private static func refocus(_ element: AXUIElement?) {
        guard let element else { return }
        _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    private static func postCommandV() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }

        let keyV: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false)

        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Transcript copied to clipboard. To enable auto-paste, grant VoiceType access in System Settings → Privacy & Security → Accessibility."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
