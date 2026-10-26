import AVFoundation
import CoreMedia
import Foundation
import MurmurCore
import Speech

/// Apple's on-device transcriber, the fallback for languages Voz does not cover.
enum AppleTranscriber {
    static func supports(_ language: String) async -> Bool {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) != nil
    }

    /// Transcribes 16 kHz mono samples. Downloads the language assets first if needed.
    static func transcribe(samples: [Float], sampleRate: Double, language: String) async throws -> [MurmurCore.Word] {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw TranscriberError.unsupported(language)
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        // SpeechAnalyzer reads files, so hand it the samples as a temporary CAF.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCAF(samples, sampleRate: sampleRate, to: url)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () -> [MurmurCore.Word] in
            var words: [MurmurCore.Word] = []
            for try await result in transcriber.results {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let start = CMTimeGetSeconds(range.start)
                    for piece in text.split(whereSeparator: \.isWhitespace) {
                        words.append(MurmurCore.Word(text: String(piece), start: start, end: start + CMTimeGetSeconds(range.duration)))
                    }
                }
            }
            return words
        }
        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value
    }

    static func writeCAF(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TranscriberError.audio
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    enum TranscriberError: LocalizedError {
        case unsupported(String), audio
        var errorDescription: String? {
            switch self {
            case .unsupported(let l): "Apple’s transcriber doesn’t support \(Locale.current.localizedString(forLanguageCode: l) ?? l)."
            case .audio: "The audio could not be prepared."
            }
        }
    }
}
