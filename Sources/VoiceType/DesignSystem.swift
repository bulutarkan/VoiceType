import Cocoa

// MARK: - VoiceType Design System
// Single source for colors, radii, shadows, typography, materials.
// Light/Dark aware via NSColor dynamic providers where needed.

enum VTDesign {
    // MARK: Radii
    enum Radius {
        static let card: CGFloat = 14
        static let pill: CGFloat = 20
        static let button: CGFloat = 12
        static let badge: CGFloat = 8
        static let field: CGFloat = 10
    }

    // MARK: Colors
    enum Color {
        // Dynamic label colors are reused, but accents are custom
        static let accent = NSColor.systemBlue
        static let accentSoft = NSColor.systemBlue.withAlphaComponent(0.14)
        static let success = NSColor.systemGreen
        static let warning = NSColor.systemOrange
        static let danger = NSColor.systemRed

        // Card / surface
        static var cardBackground: NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor.white.withAlphaComponent(0.07)
                    : NSColor.white.withAlphaComponent(0.86)
            }
        }

        static var cardBorder: NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor.white.withAlphaComponent(0.09)
                    : NSColor.black.withAlphaComponent(0.07)
            }
        }

        static var panelBorder: NSColor { NSColor.white.withAlphaComponent(0.11) }
        static var panelHighlight: NSColor { NSColor.white.withAlphaComponent(0.14) }

        // Waveform
        static let waveformInactive = NSColor.white.withAlphaComponent(0.20)
        static let waveformActive = NSColor.white
        static let waveformGlow = NSColor.white.withAlphaComponent(0.42)
    }

    // MARK: Typography
    enum Font {
        static func title(_ size: CGFloat = 24) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
        static func headline(_ size: CGFloat = 13) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
        static func body(_ size: CGFloat = 12) -> NSFont { .systemFont(ofSize: size, weight: .regular) }
        static func mono(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont { .monospacedSystemFont(ofSize: size, weight: weight) }
        static func caption(_ size: CGFloat = 10.5) -> NSFont { .systemFont(ofSize: size, weight: .regular) }
        static func captionSemibold(_ size: CGFloat = 10) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
    }

    // MARK: Shadows
    enum Shadow {
        static func cardShadow() -> NSShadow {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.10)
            s.shadowBlurRadius = 18
            s.shadowOffset = NSSize(width: 0, height: 8)
            return s
        }

        static func panelOuter() -> (ambient: NSShadow, key: NSShadow) {
            let ambient = NSShadow()
            ambient.shadowColor = NSColor.black.withAlphaComponent(0.18)
            ambient.shadowBlurRadius = 28
            ambient.shadowOffset = NSSize(width: 0, height: 14)
            let key = NSShadow()
            key.shadowColor = NSColor.black.withAlphaComponent(0.14)
            key.shadowBlurRadius = 8
            key.shadowOffset = NSSize(width: 0, height: 3)
            return (ambient, key)
        }

        static func buttonShadow() -> NSShadow {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.16)
            s.shadowBlurRadius = 8
            s.shadowOffset = NSSize(width: 0, height: 2)
            return s
        }
    }

    // MARK: Materials
    enum Material {
        static let panel: NSVisualEffectView.Material = .popover
        static let settingsBackground: NSVisualEffectView.Material = .sidebar
        static let card: NSVisualEffectView.Material = .hudWindow
    }

    // MARK: Animation
    enum Animation {
        static let panelFade: TimeInterval = 0.20
        static let cardHover: TimeInterval = 0.18
        static let waveform: TimeInterval = 0.065
    }
}

// MARK: - Helpers

extension NSView {
    func vt_applyCardStyle(corner: CGFloat = VTDesign.Radius.card) {
        wantsLayer = true
        layer?.cornerRadius = corner
        layer?.masksToBounds = false
        layer?.borderWidth = 0.5
        layer?.borderColor = VTDesign.Color.cardBorder.cgColor
        layer?.backgroundColor = VTDesign.Color.cardBackground.cgColor
        shadow = VTDesign.Shadow.cardShadow()
    }

    func vt_applyPanelShadow(to host: NSView? = nil) {
        let target = host ?? self
        target.wantsLayer = true
        // Two-layer shadow via sublayers for panel
        target.layer?.shadowColor = NSColor.black.cgColor
        target.layer?.shadowOpacity = 0.22
        target.layer?.shadowRadius = 22
        target.layer?.shadowOffset = CGSize(width: 0, height: 10)
    }
}

extension NSBezierPath {
    static func vt_roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

extension NSColor {
    var vt_cg: CGColor { cgColor }
}

// MARK: - Keycap pill helper

final class VTKeycapView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.stringValue = text
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    override var intrinsicContentSize: NSSize {
        let s = (label.stringValue as NSString).size(withAttributes: [.font: label.font!])
        return NSSize(width: s.width + 12, height: 20)
    }
}

// MARK: - Relative time

enum VTTime {
    static func relativeString(from date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds/60))m ago" }
        if seconds < 86400 { return "\(Int(seconds/3600))h ago" }
        if Calendar.current.isDateInToday(date) { return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short) }
        if Calendar.current.isDateInYesterday(date) { return "yesterday \(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}
