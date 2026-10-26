import Foundation

/// Speaker color schemes as (light, dark) sRGB hex pairs. Every scheme is checked by the tests:
/// each color has at least 3:1 contrast against light and dark backgrounds (WCAG non-text
/// contrast), and any two colors of a scheme differ by at least 0.06 in OKLab.
public enum SpeakerPalettes {
    public static let schemes: [String: [(light: UInt32, dark: UInt32)]] = [
        "ink": [(0x1F3A5F, 0x8FB0DA), (0x4A6FA5, 0x6F9BD8), (0x2A7F7F, 0x5CC2BE), (0x7A2E3B, 0xE08A97), (0x5B5F66, 0xB7BCC4), (0x8A6A2A, 0xD9B66A)],
        "carbon": [(0x6929C4, 0xA56EFF), (0x1180C8, 0x33B1FF), (0x005D5D, 0x08BDBA), (0x9F1853, 0xFF7EB6), (0xA2191F, 0xFA4D56), (0x198038, 0x6FDC8C)],
        "tableau": [(0x4E79A7, 0x7EA6D6), (0xC56A12, 0xF28E2B), (0xC63D40, 0xFF7B7E), (0x3F8737, 0x7FC36F), (0x8F5A84, 0xD6A0C8), (0x2F8C88, 0x8FD0CB)],
        "slate": [(0x0B3C5D, 0xA8CCEA), (0x2A7AB0, 0x4F9AD8), (0x6F7F8C, 0x8A9AA8), (0x2B2F33, 0xE2E6EA), (0x3F8FA0, 0x62BFD0), (0x5A4E8C, 0x9A8FD0)],
        "calm": [(0x3F6FB5, 0x7FA6E0), (0x4E8F5E, 0x8CC79A), (0xB07A2E, 0xE0B070), (0x6E7380, 0xA9AEBA), (0x7C5DA6, 0xB79BDA), (0xA65252, 0xE08A8A)],
        "colorBlind": [(0x0072B2, 0x56B4E9), (0xB07800, 0xE69F00), (0x00876A, 0x2BC79A), (0xA8508A, 0xE8A3C8), (0x857A00, 0xF0E442), (0xC05000, 0xF07A2A)],
        "highContrast": [(0x0040E0, 0x7AA8FF), (0xC40000, 0xFF6666), (0x006B00, 0x4CDB4C), (0x1A1A1A, 0xF2F2F2), (0x7A00B0, 0xD08CFF), (0x8A5A00, 0xFFC24A)],
        "earth": [(0x8A5A3B, 0xC8916C), (0x5F6E2E, 0xA3B565), (0x3D6A7A, 0x76A7B8), (0x8C6C1C, 0xE0BC5C), (0x7A4B6A, 0xB984A8), (0x4A463E, 0xC9C2B2)],
    ]
}

/// Color science for the checks: WCAG contrast and distance in OKLab.
public enum ColorMath {
    static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

    static func channels(_ hex: UInt32) -> (Double, Double, Double) {
        (linear(Double((hex >> 16) & 0xFF) / 255), linear(Double((hex >> 8) & 0xFF) / 255), linear(Double(hex & 0xFF) / 255))
    }

    public static func luminance(_ hex: UInt32) -> Double {
        let (r, g, b) = channels(hex)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    public static func oklab(_ hex: UInt32) -> (Double, Double, Double) {
        let (r, g, b) = channels(hex)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    public static func distance(_ a: UInt32, _ b: UInt32) -> Double {
        let x = oklab(a), y = oklab(b)
        return ((x.0 - y.0) * (x.0 - y.0) + (x.1 - y.1) * (x.1 - y.1) + (x.2 - y.2) * (x.2 - y.2)).squareRoot()
    }
}
