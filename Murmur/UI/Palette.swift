import AppKit
import SwiftUI

enum Palette {
    /// Speaker colors, chosen to stay apart from the system accent and to differ in lightness.
    static let speakers: [Color] = [.purple, .orange, .teal, .pink, .green, .brown, .indigo, .mint, .cyan, .yellow]

    static func speaker(_ index: Int) -> Color { speakers[((index % speakers.count) + speakers.count) % speakers.count] }

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
