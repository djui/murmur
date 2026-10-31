import AppKit
import MurmurCore
import SwiftUI

/// The speaker color sets people can choose from. Every set has a light and a dark variant.
enum SpeakerScheme: String, CaseIterable, Identifiable {
    case vivid, ink, carbon, tableau, slate, calm, colorBlind, highContrast, earth

    var id: String { rawValue }

    static var current: SpeakerScheme {
        SpeakerScheme(rawValue: UserDefaults.standard.string(forKey: AppSettings.speakerScheme) ?? "") ?? .vivid
    }

    var title: String {
        switch self {
        case .vivid: "Vivid"
        case .ink: "Ink"
        case .carbon: "Carbon"
        case .tableau: "Tableau"
        case .slate: "Slate"
        case .calm: "Calm"
        case .colorBlind: "Color-blind safe"
        case .highContrast: "High contrast"
        case .earth: "Earth"
        }
    }

    var note: String {
        switch self {
        case .vivid: "Bright system colors"
        case .ink: "Navy, steel, teal, burgundy and graphite"
        case .carbon: "IBM Carbon's categorical palette"
        case .tableau: "Tableau 10, the business-chart standard"
        case .slate: "Blues and greys, striped lanes for every other speaker"
        case .calm: "Muted blues and greens"
        case .colorBlind: "Okabe–Ito, distinct for the common kinds of color blindness"
        case .highContrast: "Strong colors, striped lanes for every other speaker"
        case .earth: "Browns, olives and slate"
        }
    }

    /// Stripes on every other speaker's lane, so lanes differ by more than color.
    var isHatched: Bool { self == .highContrast || self == .slate }

    private static var cache: [SpeakerScheme: [Color]] = [:]

    /// Colors for light and dark mode; all but Vivid come from MurmurCore, where tests check
    /// their contrast and that speakers are told apart.
    var colors: [Color] {
        if let cached = Self.cache[self] { return cached }
        let made: [Color] = SpeakerPalettes.schemes[rawValue].map { pairs in
            pairs.map { Color(light: NSColor(hex: $0.light), dark: NSColor(hex: $0.dark)) }
        } ?? [.purple, .orange, .teal, .pink, .green, .brown, .indigo, .mint, .cyan, .yellow]
        Self.cache[self] = made
        return made
    }

    /// Speakers past the first round of colors reuse them; these get a ring and striped lanes.
    func isRepeat(_ index: Int) -> Bool { (index / colors.count) % 2 == 1 }

    /// Striped lane blocks: every other speaker in the striped schemes, and repeated colors.
    func isHatched(_ index: Int) -> Bool { (isHatched && index % 2 == 1) != isRepeat(index) }

    func color(_ index: Int) -> Color {
        let c = colors
        return c[((index % c.count) + c.count) % c.count]
    }

    /// The first five colors as a small image, for menus, which can't show SwiftUI shapes.
    /// Drawn on demand, so the colors follow light and dark mode; the trailing space keeps the name clear.
    var swatch: NSImage {
        let colors = (0..<5).map { NSColor(color($0)) }
        return NSImage(size: NSSize(width: 88, height: 14), flipped: false) { _ in
            for (i, c) in colors.enumerated() {
                c.setFill()
                NSBezierPath(roundedRect: NSRect(x: CGFloat(i) * 17, y: 0, width: 14, height: 14), xRadius: 3, yRadius: 3).fill()
            }
            return true
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Palette {
    static func speaker(_ index: Int) -> Color { SpeakerScheme.current.color(index) }

    static let mark = Color(light: NSColor(srgbRed: 0.79, green: 0.54, blue: 0, alpha: 1),
                            dark: NSColor(srgbRed: 0.96, green: 0.72, blue: 0.18, alpha: 1))
    static let markText = Color(light: NSColor(srgbRed: 0.43, green: 0.29, blue: 0, alpha: 1),
                                dark: NSColor(srgbRed: 0.97, green: 0.82, blue: 0.48, alpha: 1))
    static let silence = Color(nsColor: .tertiaryLabelColor)
    static let well = Color(nsColor: .quaternaryLabelColor).opacity(0.5)
    static let recording = Color(nsColor: .systemRed)
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// A speaker's dot: filled, or a ring when the speaker repeats an earlier speaker's color.
struct SpeakerDot: View {
    let index: Int
    var size: CGFloat = 9

    var body: some View {
        let scheme = SpeakerScheme.current
        if scheme.isRepeat(index) {
            Circle().strokeBorder(scheme.color(index), lineWidth: 2.5).frame(width: size, height: size)
        } else {
            Circle().fill(scheme.color(index)).frame(width: size, height: size)
        }
    }
}

/// A small rounded pill toggle used in toolbars and headers.
struct PillToggle: View {
    let title: String
    let systemImage: String?
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
        }
        .buttonStyle(PillStyle(isOn: isOn))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct PillStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, isOn: isOn)
    }
}

/// Reads isEnabled, which a ButtonStyle itself can't, so disabled pills look disabled.
private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isOn ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isOn ? Color.accentColor : Color(nsColor: .separatorColor))
            )
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

struct Toast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            trailing
        }
    }
}

func languageName(_ code: String?) -> String {
    guard let code else { return "Unknown" }
    return Locale.current.localizedString(forLanguageCode: code) ?? code
}
