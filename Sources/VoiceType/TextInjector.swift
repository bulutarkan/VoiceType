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

        // En önemli garanti: transkript her durumda panoda kalsın.
        // Böylece aktif imlece yazamazsak kullanıcı Cmd+V ile direkt basabilir.
        copyToPasteboard(text)

        guard isAccessibilityTrusted else {
            showAccessibilityAlert()
            return
        }

        // Tek güvenilir yol: aktif hedef varsa panodaki metni Cmd+V ile bas.
        // Hedef element yoksa hiçbir yere rastgele yazma; metin zaten panoda kalıyor.
        guard target.element != nil else { return }

        pasteIntoOriginalTarget(target)
    }

    private static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private static func pasteIntoOriginalTarget(_ target: InjectionTarget) {
        // Kayıt paneli kapandıktan sonra orijinal uygulamayı tekrar öne alıyoruz.
        if let app = target.app {
            app.activate(options: [])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            refocus(target.element)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                postCommandV()

                // Bilerek clipboard'u geri almıyoruz.
                // Paste hedefte çalışmazsa transkript panoda kalmalı; Tarkan'ın istediği güvenli fallback bu.
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
        alert.messageText = "Erişilebilirlik İzni Gerekli"
        alert.informativeText = "Transkript panoya kopyalandı. Otomatik yazmak için VoiceType'a Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik izni ver."
        alert.addButton(withTitle: "Ayarları Aç")
        alert.addButton(withTitle: "Tamam")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
