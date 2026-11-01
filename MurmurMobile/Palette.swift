import MurmurCore
import SwiftUI
import UIKit

/// The speaker color sets, as in the Mac app's Settings. Every set has a light and a dark variant.
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

    private static var cache: [SpeakerScheme: [Color]] = [:]

    /// All but Vivid come from MurmurCore, where tests check their contrast and that speakers are told apart.
    var colors: [Color] {
        if let cached = Self.cache[self] { return cached }
        let made: [Color] = SpeakerPalettes.schemes[rawValue].map { pairs in
            pairs.map { pair in
                Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: pair.dark) : UIColor(hex: pair.light) })
            }
        } ?? [.purple, .orange, .teal, .pink, .green, .brown, .indigo, .mint, .cyan, .yellow]
        Self.cache[self] = made
        return made
    }

    func color(_ index: Int) -> Color {
        let c = colors
        return c[((index % c.count) + c.count) % c.count]
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// Marks, as in `DESIGN.md`: amber in light, a lighter amber in dark.
    static let mark = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF5B82E) : UIColor(hex: 0xC98A00) })
    static let recordRed = Color(UIColor(hex: 0xFF3B30))
}
