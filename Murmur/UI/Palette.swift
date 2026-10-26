import AppKit
import SwiftUI

/// The speaker color sets people can choose from. Every set has a light and a dark variant.
enum SpeakerScheme: String, CaseIterable, Identifiable {
    case vivid, calm, colorBlind, highContrast, earth

    var id: String { rawValue }

    static var current: SpeakerScheme {
        SpeakerScheme(rawValue: UserDefaults.standard.string(forKey: AppSettings.speakerScheme) ?? "") ?? .vivid
    }

    var title: String {
        switch self {
        case .vivid: "Vivid"
        case .calm: "Calm"
        case .colorBlind: "Color-blind safe"
        case .highContrast: "High contrast"
        case .earth: "Earth"
        }
    }

    var note: String {
        switch self {
        case .vivid: "Bright system colors"
        case .calm: "Muted blues and greens"
        case .colorBlind: "Okabe–Ito, distinct for the common kinds of color blindness"
        case .highContrast: "Strong colors, striped lanes for every other speaker"
        case .earth: "Browns, olives and slate"
        }
    }

    /// Stripes on every other speaker's lane, so lanes differ by more than color.
    var isHatched: Bool { self == .highContrast }

    /// (light, dark) hex pairs.
    private var pairs: [(UInt32, UInt32)] {
        switch self {
        case .vivid: []
        case .calm: [(0x3F6FB5, 0x7FA6E0), (0x4E8F5E, 0x8CC79A), (0xB07A2E, 0xE0B070), (0x6E7380, 0xA9AEBA), (0x7C5DA6, 0xB79BDA), (0xA65252, 0xE08A8A)]
        case .colorBlind: [(0x0072B2, 0x56B4E9), (0xD18F00, 0xE69F00), (0x009E73, 0x2BC79A), (0xB8619A, 0xE8A3C8), (0x3A93C9, 0x9AD3F5), (0xD55E00, 0xF07A2A)]
        case .highContrast: [(0x0040E0, 0x7AA8FF), (0xC40000, 0xFF6666), (0x006B00, 0x4CDB4C), (0x1A1A1A, 0xF2F2F2), (0x7A00B0, 0xD08CFF), (0x8A5A00, 0xFFC24A)]
        case .earth: [(0x8A5A3B, 0xC8916C), (0x5F6E2E, 0xA3B565), (0x3D6A7A, 0x76A7B8), (0x9C7A22, 0xE0BC5C), (0x7A4B6A, 0xB984A8), (0x5C6B73, 0x9AAAB2)]
        }
    }

    private static var cache: [SpeakerScheme: [Color]] = [:]

    var colors: [Color] {
        if let cached = Self.cache[self] { return cached }
        let made: [Color] = pairs.isEmpty
            ? [.purple, .orange, .teal, .pink, .green, .brown, .indigo, .mint, .cyan, .yellow]
            : pairs.map { Color(light: NSColor(hex: $0.0), dark: NSColor(hex: $0.1)) }
        Self.cache[self] = made
        return made
    }

    func color(_ index: Int) -> Color {
        let c = colors
        return c[((index % c.count) + c.count) % c.count]
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
            .opacity(configuration.isPressed ? 0.7 : 1)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
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
