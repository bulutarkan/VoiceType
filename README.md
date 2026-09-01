# VoiceType

Native macOS menu bar application for voice-to-text. Trigger a global shortcut, record, and have the transcription pasted directly at your cursor using Groq Whisper.

VoiceType lives in the menu bar, works in any application, and keeps every transcript in the clipboard as a reliable fallback.

## Overview

VoiceType captures audio through `AVAudioEngine`, sends it to Groq (`whisper-large-v3-turbo`), and injects the resulting text into the focused application via Accessibility and simulated `Cmd+V`. If injection is not possible, the transcript remains in the pasteboard and in the in-app history.

Typical flow: press shortcut, speak, confirm, text appears.

## Features

### 1. Menu Bar Integration

- Runs as an accessory application (`NSApp.accessory`), no Dock icon.
- System status item with waveform symbol and tooltip showing current shortcut and mode.
- Menu provides shortcut display, Settings, Recent transcriptions, and Quit.

### 2. Global Shortcut

- Carbon `RegisterEventHotKey` based, system-wide.
- Default is `Option + Space`, configurable in Settings.
- Two modes:
  - Toggle: press to show, press again to hide.
  - Hold to talk: press and hold to record, release to confirm. Toggleable in Settings via `NSSwitch`.

### 3. Recording Panel

- Borderless floating `NSPanel` (520 x 56) centered near bottom of screen, level `.floating`, appears on all spaces.
- Visual effect background (`NSVisualEffectView` with `hudWindow` material), rounded pill, shadow, and fade animation.
- Real-time waveform with 60 bars (`CALayer`, `AVAudioEngine` tap, amplitude smoothing).
- Timer in `m:ss` format.
- Controls for Cancel (`xmark` / `Esc`) and Confirm (`checkmark`).
- Hold mode keeps the same clean waveform layout without an extra instruction line.
- States for recording, transcribing (spinner), and inline error with retry.

### 4. Audio Recording

- `AVAudioEngine` input node tap, 1024 buffer, writes to temporary WAV file in `/tmp` (`vt_*.wav`).
- Microphone permission handled via `AVCaptureDevice`.
- System microphone selection supports Auto (current macOS default) or a manually selected Core Audio input device.
- Waveform amplitudes computed per buffer and streamed to the panel on the main thread.
- Automatic cleanup on cancel or after successful transcription.

### 5. Transcription

- Groq API `POST https://api.groq.com/openai/v1/audio/transcriptions` with `multipart/form-data`.
- Model `whisper-large-v3-turbo`, `response_format` as text.
- Authentication via Bearer token from Settings.
- Temporary files are removed after the request. Errors are surfaced inline in the panel with retry support.

### 6. Text Injection

- Captures the focused `AXUIElement` and frontmost application before the panel steals focus.
- On success, copies transcript to `NSPasteboard` and adds it to history.
- If accessibility is trusted, refocuses the original element and posts `Cmd+V` via `CGEvent`.
- If accessibility is not trusted, shows an alert directing to System Settings and leaves the text in the clipboard for manual paste.

### 7. History

- Last 20 transcriptions stored in `UserDefaults` as JSON through `TranscriptionHistory`.
- Accessible via the menu bar menu under Recent. Each entry shows a 42-character preview and time.
- Actions for Copy Last and Clear History. Updates are broadcast via `NotificationCenter`.

### 8. Settings Window

- Window size 600 x 680, `fullSizeContentView`, transparent title bar, `hudWindow` background.
- Header with application icon, title, and version.
- Cards with rounded corners, border, and shadow:
  - Shortcut card with keycap button, mode indicator, and hold-to-talk switch.
  - Microphone card with Auto/system input selection, device refresh, and a live green/orange/red level meter for speaking tests.
  - Transcription card with secure API key field, show/hide toggle, Save action, and link to `console.groq.com/keys`.
- Footer notes about privacy and usage.

### 9. Application Icon

- Custom squircle icon with dark background, white microphone, and waveform.
- Provided as `Resources/AppIcon.icns` and `Resources/AppIcon.iconset` with all required sizes.
- `CFBundleIconFile` set in `Info.plist`.

## Architecture

### Project Structure

```
Sources/VoiceType/
  main.swift                    # NSApplication bootstrap
  AppDelegate.swift             # Coordination of status bar, hotkey, panel, settings
  AppSettings.swift             # UserDefaults wrapper and ShortcutFormatter
  HotkeyManager.swift           # Carbon hotkey registration for press and release
  StatusBarController.swift     # NSStatusItem, menu, and history submenu
  TranscriptionHistory.swift    # History model, persistence, notifications
  PanelController.swift         # WaveformView, RecordingView, panel lifecycle
  AudioRecorder.swift           # AVAudioEngine recording and metering
  GroqService.swift             # Groq transcription service
  TextInjector.swift            # AX capture, pasteboard, CGEvent injection
  SettingsWindowController.swift # Settings UI
Resources/
  AppIcon.icns
  AppIcon.iconset/
  AppIcon_1024.png
```

### Data Flow

```
HotkeyManager (press)
  -> PanelController.show()
  -> TextInjector.captureTarget()
  -> AudioRecorder.startRecording()
  -> User confirms (click or hold release)
  -> AudioRecorder.stopRecording() -> URL
  -> GroqTranscriptionService.transcribe(audioURL:)
  -> TextInjector.inject(text, target:)
  -> Pasteboard + history + CGEvent Cmd+V
```

Panel state is tracked via `isVisible` and `isTranscribing`. Transcription keeps the panel open and shows progress or inline error with retry that reuses the last audio data.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 15 or later, Swift 5.9.
- Groq API key. Create one at https://console.groq.com/keys.

Linked frameworks, defined in `Package.swift:11-16`:

- Carbon
- AVFoundation
- Cocoa
- QuartzCore
- ApplicationServices

## Installation

### 1. Clone

```bash
git clone https://github.com/bulutarkan/VoiceType.git
cd VoiceType
```

### 2. Build

Swift Package Manager executable:

```bash
swift build -c release
.build/release/VoiceType
```

To open in Xcode:

```bash
open Package.swift
```

Then Run with Cmd+R.

### 3. Application Bundle

The repository includes a prebuilt bundle at `/Applications/VoiceType.app` when installed locally. The bundle is constructed from the release binary and `Resources/AppIcon.icns`:

```bash
swift build -c release
cp .build/release/VoiceType /Applications/VoiceType.app/Contents/MacOS/VoiceType
cp Resources/AppIcon.icns /Applications/VoiceType.app/Contents/Resources/AppIcon.icns
codesign --force --deep --sign - /Applications/VoiceType.app
touch /Applications/VoiceType.app
open /Applications/VoiceType.app
```

`Info.plist` values:

- `CFBundleIdentifier` `com.tarkanbulut.voicetype`
- `CFBundleExecutable` `VoiceType`
- `LSUIElement` `true`
- `NSMicrophoneUsageDescription` descriptive string
- `CFBundleIconFile` `AppIcon`

## First Run

1. Open VoiceType from the menu bar and select Settings.
2. Enter the Groq API key, starting with `gsk_`, and select Save.
3. Adjust the global shortcut if needed. The default is `Option + Space`.
4. Enable Hold to talk if a press-and-hold workflow is preferred.
5. Grant system permissions:
   - Microphone: System Settings > Privacy and Security > Microphone
   - Accessibility: System Settings > Privacy and Security > Accessibility

If permissions are not granted, transcription still succeeds and the text remains in the clipboard. Manual paste with `Cmd+V` is always available.

To reset permissions after a re-sign:

```bash
tccutil reset Microphone com.tarkanbulut.voicetype
tccutil reset Accessibility com.tarkanbulut.voicetype
xattr -cr /Applications/VoiceType.app
```

Then relaunch the application.

## Usage

1. Place the cursor in any text field.
2. Press the global shortcut. The recording panel appears.
3. Speak. Waveform and timer provide feedback.
4. Select Confirm or release the shortcut in hold mode. Transcription starts.
5. On success the panel closes and text is pasted. On failure an inline error appears with Retry.

Menu bar actions:

- Shortcut display is read-only and reflects `AppSettings`.
- Settings opens the settings window.
- Recent lists up to 20 previous transcriptions. Selecting an entry copies it to the clipboard.
- Clear History removes all entries.

Keyboard:

- `Esc` cancels recording and discards the temporary file.
- Confirm can be triggered by the checkmark button or by releasing the hold shortcut.

## Configuration

All settings are persisted in `UserDefaults`.

| Key | Default | Description |
| --- | --- | --- |
| `hotkeyKeyCode` | `kVK_Space` (49) | Carbon virtual key code |
| `hotkeyModifiers` | `optionKey` (2048) | Carbon modifier mask |
| `groqAPIKey` | `""` | Groq API key |
| `holdToTalkEnabled` | `false` | Hold versus toggle mode |
| `transcriptionHistory` | `[]` | JSON encoded array of history items |

`ShortcutFormatter.displayString(keyCode:modifiers:)` renders modifiers as `Ctrl`, `Opt`, `Shift`, `Cmd` symbols. `keyName(for:)` covers Space, Return, Tab, Esc, arrows, function keys, and falls back to `UCKeyTranslate` for the current layout.

## Permissions and Security

- Microphone is required for recording. Authorization is queried with `AVCaptureDevice.authorizationStatus(for: .audio)` and requested with `requestAccess(for:)`.
- Accessibility (`AXIsProcessTrusted`) is required for automatic paste. The application prompts with `AXIsProcessTrustedWithOptions` when needed.
- The API key is stored in `UserDefaults` as plain text. For hardened deployment, move it to the Keychain.
- Temporary audio files are written to the system temporary directory and removed after transcription or on cancel.
- The application is currently signed ad hoc (`codesign -s -`). For distribution, sign with a Developer ID and notarize.

## Package Details

`Package.swift`:

- `swift-tools-version: 5.9`
- `platforms: [.macOS(.v14)]`
- Single `executableTarget` named `VoiceType` at `Sources/VoiceType`
- Linker settings for the five frameworks listed above

There is no `Package.resolved` checked in. The `.build` directory is ignored.

## Roadmap

- Keychain storage for the API key
- Language selection for Groq transcription
- Post-processing for punctuation and filler word removal
- Local Whisper fallback for offline use
- Provider abstraction for Groq, OpenAI, and local engines
- Launch at login and update mechanism
- DMG and Homebrew distribution

## License

MIT. See `LICENSE` if present. You are free to use, modify, and distribute the software.

---

Maintained by Tarkan Bulut. Built with Swift, AVFoundation, and Carbon on macOS.
