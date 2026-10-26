import Testing
@testable import MurmurCore

@Suite struct PaletteTests {
    /// Backgrounds the colors sit on: the light lane well and the dark window.
    static let lightBackground: UInt32 = 0xF2F2F2
    static let darkBackground: UInt32 = 0x1E1E1E

    @Test(arguments: Array(SpeakerPalettes.schemes.keys))
    func contrastOnBothBackgrounds(scheme: String) {
        for pair in SpeakerPalettes.schemes[scheme]! {
            #expect(ColorMath.contrast(pair.light, Self.lightBackground) >= 3, "\(scheme) light \(String(pair.light, radix: 16))")
            #expect(ColorMath.contrast(pair.dark, Self.darkBackground) >= 3, "\(scheme) dark \(String(pair.dark, radix: 16))")
        }
    }

    @Test(arguments: Array(SpeakerPalettes.schemes.keys))
    func speakersAreTellApart(scheme: String) {
        let pairs = SpeakerPalettes.schemes[scheme]!
        for i in pairs.indices {
            for j in pairs.indices where j > i {
                #expect(ColorMath.distance(pairs[i].light, pairs[j].light) >= 0.06, "\(scheme) light \(i)/\(j)")
                #expect(ColorMath.distance(pairs[i].dark, pairs[j].dark) >= 0.06, "\(scheme) dark \(i)/\(j)")
            }
        }
    }

    @Test func mathMatchesKnownValues() {
        #expect(abs(ColorMath.contrast(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(ColorMath.distance(0x123456, 0x123456) == 0)
    }
}
