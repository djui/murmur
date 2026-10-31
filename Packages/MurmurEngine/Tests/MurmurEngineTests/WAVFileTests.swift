import Foundation
import MurmurEngine
import Testing

struct WAVFileTests {
    @Test func header() {
        let data = WAVFile.data([0, 1, -1, 0.5], sampleRate: 16_000)
        #expect(data.count == 44 + 8)
        #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
        func u32(_ at: Int) -> UInt32 { data[at..<at + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } }
        #expect(u32(4) == 36 + 8)
        #expect(u32(24) == 16_000)
        #expect(u32(40) == 8)
    }

    @Test func samplesClampAndRound() {
        let data = WAVFile.data([2, -2, 0.5], sampleRate: 8_000)
        func i16(_ at: Int) -> Int16 { Int16(bitPattern: UInt16(data[at]) | UInt16(data[at + 1]) << 8) }
        #expect(i16(44) == Int16.max)
        #expect(i16(46) == -Int16.max)
        #expect(i16(48) == 16384)
    }

    @Test func requiredModelsRunEverywhere() {
        #expect(ModelKind.available.filter(\.isRequired).count == 4)
    }
}
