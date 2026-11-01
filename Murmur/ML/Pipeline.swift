import Align
import Clear
import Ear
import Foundation
import MurmurCore
import Tongue
import Uhm
import Voz
import Who

struct PipelineStep: Identifiable, Equatable {
    enum State: Equatable { case pending, running, done, skipped, failed }

    let id: String
    var title: String
    var detail: String
    var state: State = .pending
    var fraction: Double?
    var seconds: Double?
}

struct LanguagePrompt: Identifiable {
    let id = UUID()
    var language: String
    var confidence: Double
    var appleSupports: Bool
}

enum LanguageChoice {
    case apple(String)
    case voz(String)
    case cancel
}

/// What the pipeline reports back while it works.
@MainActor
protocol PipelineDelegate: AnyObject {
    func update(step id: String, _ change: (inout PipelineStep) -> Void)
    func peaksReady(_ peaks: [Float], duration: Double)
    /// Words so far, before the later steps refine them: first all from one speaker, then split by speaker.
    func wordsReady(_ words: [MurmurCore.Word], speakers: [Speaker], language: String)
    func chooseLanguage(_ prompt: LanguagePrompt) async -> LanguageChoice
}

/// Turns a media file (or a two-track recording) into speaker-labelled words.
enum Pipeline {
    struct Input: Sendable {
        var media: URL
        var micStem: URL?
        var systemStem: URL?
        var enhance: Bool
        var fillers: Bool
        var summarize: Bool
        var language: String?
        var cache: URL
    }

    struct Output: Sendable {
        var duration: Double
        var peaks: [Float]
        var words: [MurmurCore.Word]
        var speakers: [Speaker]
        var language: String
        var confidence: Double?
        var transcriber: String
        var warning: String?
        var title: String?
        var summary: String?
    }

    struct Cancelled: Error {}

    static func steps(for input: Input) -> [PipelineStep] {
        var steps = [
            PipelineStep(id: "read", title: "Reading audio", detail: "Decoding to 16 kHz mono"),
            PipelineStep(id: "models", title: "Loading models", detail: "Voz, Who, Ear, Align"),
            PipelineStep(id: "language", title: "Detecting language", detail: "Ear"),
        ]
        if input.enhance { steps.append(PipelineStep(id: "enhance", title: "Enhancing audio", detail: "Clear · for transcription, playback and export")) }
        steps += [
            PipelineStep(id: "transcribe", title: "Transcribing", detail: "Voz"),
            PipelineStep(id: "speakers", title: "Finding speakers", detail: "Who"),
            PipelineStep(id: "align", title: "Tightening word timing", detail: "Align"),
        ]
        if input.fillers { steps.append(PipelineStep(id: "fillers", title: "Marking fillers", detail: "Uhm")) }
        if input.summarize { steps.append(PipelineStep(id: "title", title: "Naming the project", detail: "Title and short summary")) }
        return steps
    }

    static func run(_ input: Input, delegate: PipelineDelegate) async throws -> Output {
        let engines = Engines.shared
        let rate = 16_000.0

        // Read
        var clock = ContinuousClock.now
        await delegate.update(step: "read") { $0.state = .running }
        let mixed = try await AudioDecoder.decode(input.media, sampleRate: rate)
        let duration = Double(mixed.count) / rate
        let peaks = Peaks.normalize(Peaks.compute(mixed, sampleRate: rate))
        await delegate.peaksReady(peaks, duration: duration)
        let mic = try await input.micStem.asyncMap { try await AudioDecoder.decode($0, sampleRate: rate) }
        let system = try await input.systemStem.asyncMap { try await AudioDecoder.decode($0, sampleRate: rate) }
        await finish("read", clock, delegate) { $0.detail = "\(Timecode.short(duration)) of audio" }

        // Models: the first use after installing prepares them for the Neural Engine.
        clock = .now
        await delegate.update(step: "models") { $0.state = .running }
        var needed: [ModelKind] = [.ear, .voz, .who, .align]
        if input.fillers { needed.append(.uhm) }
        if input.enhance { needed.append(.clear) }
        let cold = needed.filter { !engines.isWarm($0) }
        for (i, kind) in cold.enumerated() {
            await delegate.update(step: "models") {
                $0.detail = "Preparing \(kind.engine) (\(i + 1) of \(cold.count))"
                $0.fraction = Double(i) / Double(max(1, cold.count))
            }
            await engines.warmUp(kind)
        }
        let loadSeconds = (ContinuousClock.now - clock).components.seconds
        await finish("models", clock, delegate) {
            $0.detail = loadSeconds >= 10 ? "First use: models prepared for the Neural Engine" : "Ready"
        }

        // Language
        clock = .now
        await delegate.update(step: "language") { $0.state = .running }
        var language = input.language ?? "en"
        var confidence: Double?
        var useApple = false
        if input.language == nil {
            let detection = try await engines.ear.identify(samples: mixed, sampleRate: rate)
            language = detection.language ?? "en"
            confidence = detection.confidence
            // Ear unsure, or naming a language Voz lacks: Voz needs no language to transcribe, so read
            // a sample and let Tongue name the language of the text. Trust it when it's clear-cut.
            if !detection.isReliable || detection.confidence < 0.8 || !Voz.supportedLanguages.contains(language),
               let tongue = engines.tongue, Engines.shared.isDownloaded(.voz) {
                let sample = Array(mixed.prefix(Int(rate * 90)))
                if let text = try? await engines.voz().transcribe(samples: sample, sampleRate: rate).text, text.count > 40 {
                    let check = tongue.detect(text)
                    if let found = check.language, Voz.supportedLanguages.contains(found), !check.isTooCloseToCall,
                       (check.candidates.first?.probability ?? 0) > 0.8 {
                        language = found
                        confidence = check.candidates.first?.probability
                    }
                }
            }
        }
        if !Voz.supportedLanguages.contains(language) {
            if input.language != nil {
                // Chosen by hand: use Apple's transcriber when it knows the language.
                useApple = await AppleTranscriber.supports(language)
            } else {
                let detected = language
                let prompt = LanguagePrompt(language: language, confidence: confidence ?? 0,
                                            appleSupports: await AppleTranscriber.supports(language))
                switch await delegate.chooseLanguage(prompt) {
                case .cancel: throw Cancelled()
                case .apple(let l): language = l; useApple = true
                case .voz(let l):
                    language = l
                    // "Another language" that Voz also lacks goes to Apple; "anyway" stays with Voz.
                    if l != detected, !Voz.supportedLanguages.contains(l) { useApple = await AppleTranscriber.supports(l) }
                }
            }
        }
        let name = Locale.current.localizedString(forLanguageCode: language) ?? language
        await finish("language", clock, delegate) {
            $0.detail = "Ear · \(name)" + (confidence.map { ", \(Int($0 * 100))%" } ?? " (chosen)")
        }

        // Enhance
        var asrMixed = mixed, asrMic = mic, asrSystem = system
        if input.enhance {
            clock = .now
            await delegate.update(step: "enhance") { $0.state = .running }
            let options = Clear.Options(sampleRate: rate)
            asrMixed = try await engines.clear.enhance(samples: mixed, sampleRate: rate, options: options).samples
            if let m = mic { asrMic = try await engines.clear.enhance(samples: m, sampleRate: rate, options: options).samples }
            if let s = system { asrSystem = try await engines.clear.enhance(samples: s, sampleRate: rate, options: options).samples }
            let playback = input.cache.appendingPathComponent("enhanced.m4a")
            try? FileManager.default.removeItem(at: playback)
            try await engines.clear.enhance(path: input.media.path, to: playback.path)
            await finish("enhance", clock, delegate) { _ in }
        }

        // Transcribe and diarize in parallel
        await delegate.update(step: "transcribe") { $0.state = .running; $0.detail = useApple ? "Apple on-device transcriber" : "Voz" }
        let transcribeClock = ContinuousClock.now
        let isRecording = input.micStem != nil || input.systemStem != nil

        // Fixed copies for the concurrently running closure below.
        let (appleASR, asrLanguage, mixedASR, micASR, systemASR) = (useApple, language, asrMixed, asrMic, asrSystem)
        async let transcription: (mic: [MurmurCore.Word], other: [MurmurCore.Word]) = {
            func transcribe(_ samples: [Float], share: Double, offset: Double) async throws -> [MurmurCore.Word] {
                guard samples.count > Int(rate / 2) else { return [] }
                if appleASR { return try await AppleTranscriber.transcribe(samples: samples, sampleRate: rate, language: asrLanguage) }
                let voz = try await engines.voz()
                let result = try await voz.transcribe(samples: samples, sampleRate: rate) { p in
                    Task { @MainActor in delegate.update(step: "transcribe") { $0.fraction = offset + p.fractionCompleted * share } }
                }
                return result.words.map { MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end) }
            }
            if isRecording {
                let m = try await transcribe(micASR ?? [], share: 0.5, offset: 0)
                let o = try await transcribe(systemASR ?? [], share: 0.5, offset: 0.5)
                return (m, o)
            }
            return ([], try await transcribe(mixedASR, share: 1, offset: 0))
        }()

        // Diarize after transcribing: both use the Neural Engine and contend when run together.
        var (micWords, otherWords) = try await transcription
        await finish("transcribe", transcribeClock, delegate) { _ in }
        let unsplit = merge(mic: micWords, other: otherWords, turns: [], isRecording: isRecording)
        await delegate.wordsReady(unsplit.words, speakers: unsplit.speakers, language: language)
        let speakersClock = ContinuousClock.now
        await delegate.update(step: "speakers") { $0.state = .running }
        let turns: [SpeakerTurn] = try await {
            let samples = isRecording ? (system ?? []) : mixed
            guard samples.count > Int(rate) else { return [] }
            let result = try await engines.who.diarize(samples: samples, sampleRate: rate)
            return result.turns.map { SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker) }
        }()
        let speakerCount = Set(turns.map(\.speaker)).count
        await finish("speakers", speakersClock, delegate) {
            $0.detail = "Who · \(speakerCount) \(speakerCount == 1 ? "speaker" : "speakers")" + (isRecording ? " besides you" : "")
        }
        let split = merge(mic: micWords, other: otherWords, turns: turns, isRecording: isRecording)
        await delegate.wordsReady(split.words, speakers: split.speakers, language: language)

        // Align
        clock = .now
        await delegate.update(step: "align") { $0.state = .running }
        if (try? await engines.align.isSupported(languageCode: language)) == true {
            micWords = try await refine(micWords, audio: mic ?? [], language: language)
            otherWords = try await refine(otherWords, audio: isRecording ? (system ?? []) : mixed, language: language)
            await finish("align", clock, delegate) { _ in }
        } else {
            await delegate.update(step: "align") { $0.state = .skipped; $0.detail = "Align · not available for \(name)" }
        }

        // Merge
        let merged = merge(mic: micWords, other: otherWords, turns: turns, isRecording: isRecording)
        var words = merged.words
        let speakers = merged.speakers

        // Fillers
        if input.fillers {
            clock = .now
            await delegate.update(step: "fillers") { $0.state = .running }
            let result = try await engines.uhm.analyze(samples: mixed, sampleRate: Int(rate))
            let spans = result.fillers.map { FillerSpan(start: $0.start, end: $0.end, label: $0.type.map(label) ?? "um") }
            words = Merge.markFillers(words, fillers: spans)
            await finish("fillers", clock, delegate) { $0.detail = "Uhm · \(spans.count) found" }
        }

        // Check that the text is in the language we think it is.
        let text = Merge.join(words.filter { !$0.isFiller })
        var warning: String?
        if let tongue = engines.tongue, text.count > 30 {
            let detection = tongue.detect(String(text.prefix(2000)))
            if let found = detection.language, found != language, !detection.isTooCloseToCall,
               (detection.candidates.first?.probability ?? 0) > 0.8 {
                let foundName = Locale.current.localizedString(forLanguageCode: found) ?? found
                warning = "The transcript reads like \(foundName), not \(name). Try transcribing again as \(foundName)."
            }
        }

        // Title and summary
        var title: String?, summary: String?
        if input.summarize {
            clock = .now
            await delegate.update(step: "title") { $0.state = .running }
            if let card = try? await Summarizer.card(for: text) {
                title = card.title
                summary = card.summary
                await finish("title", clock, delegate) { $0.detail = card.title }
            } else {
                await delegate.update(step: "title") { $0.state = .skipped; $0.detail = "Apple Intelligence is not available" }
            }
        }

        return Output(duration: duration, peaks: peaks, words: words, speakers: speakers, language: language,
                      confidence: confidence, transcriber: useApple ? "apple" : "voz", warning: warning,
                      title: title, summary: summary)
    }

    /// One word list in time order with its speakers: in a recording you are speaker 0 and the others
    /// follow; without turns everyone else is one speaker.
    static func merge(mic: [MurmurCore.Word], other: [MurmurCore.Word], turns: [SpeakerTurn],
                      isRecording: Bool) -> (words: [MurmurCore.Word], speakers: [Speaker]) {
        var speakers: [Speaker] = []
        var words: [MurmurCore.Word]
        if isRecording {
            let mine = Merge.removeEcho(mic: mic, system: other).map { var w = $0; w.speaker = 0; return w }
            let others = Merge.assign(other, turns: turns, firstId: 1)
            words = (mine + others).sorted { $0.start < $1.start }
            speakers.append(Speaker(id: 0, isMe: true))
            for id in Set(others.map(\.speaker)).sorted() { speakers.append(Speaker(id: id)) }
        } else {
            words = Merge.assign(other, turns: turns)
            for id in Set(words.map(\.speaker)).sorted() { speakers.append(Speaker(id: id)) }
        }
        if speakers.isEmpty { speakers = [Speaker(id: 0)] }
        return (words, speakers)
    }

    /// Re-times words against the audio with Align; words it cannot improve keep their timing.
    static func refine(_ words: [MurmurCore.Word], audio: [Float], language: String) async throws -> [MurmurCore.Word] {
        guard !words.isEmpty, !audio.isEmpty else { return words }
        let timings = words.map { WordTiming(text: $0.text, start: $0.start, end: $0.end) }
        let refined = try await Engines.shared.align.refine(timings, audio: audio, sampleRate: 16_000, languageCode: language)
        guard refined.count == words.count else { return words }
        return Merge.monotonic(zip(words, refined).map { word, timing in
            var w = word
            w.start = timing.start
            w.end = max(timing.start, timing.end)
            return w
        })
    }

    static func label(_ type: Uhm.FillerType) -> String {
        switch type {
        case .uh: "uh"
        case .um: "um"
        case .hmm: "hmm"
        case .and: "and"
        case .other: "um"
        }
    }

    @MainActor
    private static func finish(_ id: String, _ start: ContinuousClock.Instant, _ delegate: PipelineDelegate,
                               _ change: (inout PipelineStep) -> Void) {
        let elapsed = ContinuousClock.now - start
        delegate.update(step: id) {
            $0.state = .done
            $0.fraction = nil
            $0.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            change(&$0)
        }
    }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
