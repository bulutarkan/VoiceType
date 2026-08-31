# VoiceType 🎙️

macOS menü çubuğunda yaşayan, global kısayolla ses kaydı alıp Groq Whisper ile yazıya çeviren ve metni aktif uygulamaya otomatik yazan native Swift uygulaması.

> Konuş → Kaydet → Onayla → Metin imlecin olduğu yere yapışsın. Olmadıysa bile pano'da hazır.

## ✨ Özellikler

- **Menü Çubuğu Uygulaması** — Dock'ta görünmez (`NSApp.accessory`), sadece menü çubuğunda `mic.fill` ikonu.
- **Global Kısayol** — Varsayılan `⌥ + Space`, Ayarlar'dan değiştirilebilir. Carbon `RegisterEventHotKey` ile sistem genelinde çalışır.
- **Kayıt Paneli** — Ekran altında floating `NSPanel` (480×52), yuvarlak koyu kapsül, içinde:
  - Gerçek zamanlı waveform (60 bar, `CALayer` + `AVAudioEngine` tap)
  - Kronometre (`0:00` format)
  - İptal (`xmark` / `Esc`) ve Onayla (`checkmark`) butonları
  - Transkripsiyon sırasında spinner
- **Ses Kaydı** — `AVAudioEngine` + `installTap`, geçici `.wav` dosyası (`/tmp/vt_*.wav`), mikrofon izni yönetimi (`AVCaptureDevice`).
- **Transkripsiyon** — [Groq API](https://console.groq.com) `whisper-large-v3-turbo`, `multipart/form-data` upload, API key `UserDefaults`'ta saklanır.
- **Metin Enjeksiyonu** — En güvenilir yol:
  1. Metin her durumda panoya kopyalanır (`NSPasteboard`) — fallback garantisi
  2. Erişilebilirlik izni varsa orijinal `AXUIElement` refocus edilip `Cmd+V` (`CGEvent`) ile yapıştırılır
  3. İzin yoksa kullanıcıyı `Sistem Ayarları > Erişilebilirlik`'e yönlendiren alert
- **Ayarlar Penceresi** — `⌘ + ,` veya menüden açılır:
  - Kısayol kaydedici (modifier + keyCode yakalama)
  - Groq API Key (`gsk_...`) giriş ve kaydetme
- **Akıllı Davranış** — Panel açılmadan önce aktif odak (`kAXFocusedUIElement`) yakalanır, panel kapanınca orijinal uygulama `activate` edilir.

## 🏗️ Mimari

```
Sources/VoiceType/
├── main.swift                  # NSApplication bootstrap
├── AppDelegate.swift           # StatusBar + Hotkey + Panel + Settings orkestrasyonu
├── AppSettings.swift           # UserDefaults wrapper + ShortcutFormatter
├── StatusBarController.swift   # NSStatusItem + NSMenu
├── HotkeyManager.swift         # Carbon global hotkey register/unregister
├── PanelController.swift       # NSPanel + WaveformView + RecordingView + AudioRecorder entegrasyonu
├── AudioRecorder.swift         # AVAudioEngine tap, waveformAmplitudes, timer
├── GroqService.swift           # GroqTranscriptionService (whisper-large-v3-turbo)
├── TextInjector.swift          # AXUIElement capture + pasteboard + CGEvent Cmd+V
└── SettingsWindowController.swift # Kısayol + API key UI
```

**Akış:** `HotkeyManager` → `PanelController.show()` → `TextInjector.captureTarget()` → `AudioRecorder.startRecording()` → kullanıcı Onayla → `stopRecording` → `GroqService.transcribe()` → `TextInjector.inject()`

## 🛠️ Gereksinimler

- macOS 14 Sonoma+
- Xcode 15+ / Swift 5.9+
- Groq API Key ([console.groq.com/keys](https://console.groq.com/keys))

**Linklenen Framework'ler:** `Carbon`, `AVFoundation`, `Cocoa`, `QuartzCore`, `ApplicationServices` (`Package.swift:14-20`)

## 🚀 Kurulum ve Çalıştırma

```bash
# 1. Klonla
git clone https://github.com/bulutarkan/VoiceType.git
cd VoiceType

# 2. Build & Run (SPM executable)
swift build -c release
.build/release/VoiceType

# veya Xcode ile açıp Run (⌘R)
open Package.swift
```

### İlk Çalıştırma

1. Menü çubuğunda **VoiceType** ikonuna tıkla → **Ayarlar...**
2. Groq API anahtarını (`gsk_...`) gir → **Kaydet**
3. Gerekirse kısayolu değiştir (varsayılan `⌥ Space`)
4. Sistem izinlerini ver:
   - **Mikrofon:** `Sistem Ayarları > Gizlilik ve Güvenlik > Mikrofon`
   - **Erişilebilirlik:** `Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik` (otomatik yazma için)

> İzin yoksa da transkript panoya kopyalanır, `⌘V` ile manuel yapıştırabilirsin.

## ⌨️ Kullanım

1. Herhangi bir metin alanında imleci konumlandır (Notlar, Chrome, Slack, vs.)
2. `⌥ + Space` (veya ayarladığın kısayol) → kayıt paneli açılır, konuşmaya başla
3. **Onayla** (`✓`) → Groq transkripsiyon → metin otomatik yapışır + panoda kalır
4. **İptal** (`✕` veya `Esc`) → kayıt silinir, hiçbir şey yazılmaz

Menü: `Kısayol: ⌥Space` bilgisi, `Ayarlar...`, `Çıkış`

## ⚙️ Yapılandırma

`AppSettings.swift:6-35` içindeki `UserDefaults` anahtarları:

| Key | Varsayılan | Açıklama |
|-----|------------|----------|
| `hotkeyKeyCode` | `kVK_Space` (49) | Carbon keyCode |
| `hotkeyModifiers` | `optionKey` (2048) | Carbon modifier mask |
| `groqAPIKey` | `""` | Groq API anahtarı |

Kısayol formatlaması `ShortcutFormatter.displayString` ile `⌃⌥⇧⌘` sembollerine çevrilir.

## 🔒 İzinler & Güvenlik

- **Mikrofon:** Kayıt için zorunlu, `AVCaptureDevice.authorizationStatus` ile kontrol.
- **Erişilebilirlik (AXIsProcessTrusted):** Otomatik `Cmd+V` için gerekli. Yoksa sadece pano fallback'i çalışır, veri kaybı olmaz.
- **API Anahtarı:** `UserDefaults.standard` içinde düz metin saklanır. İhtiyaç olursa Keychain'e taşınabilir.
- Geçici ses dosyaları transcription sonrası silinir (`FileManager.removeItem`).

## 🧩 Paket

`Package.swift:7-24` — `swift-tools-version: 5.9`, `platforms: [.macOS(.v14)]`, tek `executableTarget` (`Sources/VoiceType`).

```swift
.linkedFramework("Carbon"),
.linkedFramework("AVFoundation"),
.linkedFramework("Cocoa"),
.linkedFramework("QuartzCore"),
.linkedFramework("ApplicationServices"),
```

## 🗺️ Yol Haritası

- [ ] Keychain ile güvenli API key saklama
- [ ] Dil seçimi (Groq `language` parametresi)
- [ ] Otomatik noktalama / düzeltme
- [ ] Kayıt geçmişi
- [ ] DMG / Homebrew cask dağıtımı

## 📄 Lisans

MIT — dilediğin gibi kullan, değiştir, dağıt.

---

Made with ❤️ in Swift — Tarkan Bulut
