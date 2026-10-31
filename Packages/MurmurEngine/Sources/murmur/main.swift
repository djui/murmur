import Foundation
import MurmurCore
import MurmurEngine
import Voz

// The engine as a command: the Windows app runs it with `--events` and reads one JSON object per line
// from stdout; without `--events` it prints for people.
//
//     murmur process <media> [--language xx] [--enhance] [--no-fillers] [--title] [--redact]
//                            [--stems mic,system] [--cache dir] [--out project.json] [--events]
//     murmur models [--events]
//     murmur download required|<kind>[,<kind>…] [--events]
//     murmur render <project.json> --format plain|timestamps|markdown|srt|vtt|json
//                            [--keep-fillers] [--no-names] [--relative]
//     murmur redact <project.json>             finds personal details and writes them into the project
//     murmur decode <media> --out audio.wav    16 kHz mono, to check decoding
//
// Events: {"type":"steps"|"step"|"peaks"|"models"|"download"|"chooseLanguage"|"done"|"error", …}.
// On "chooseLanguage" the caller answers on stdin with one line: {"choice":"voz"|"cancel","language":"xx"}.

struct Arguments {
    static let valued: Set<String> = ["language", "stems", "cache", "out", "format"]

    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ args: ArraySlice<String>) {
        var it = args.makeIterator()
        while let arg = it.next() {
            guard arg.hasPrefix("--") else { positional.append(arg); continue }
            let key = String(arg.dropFirst(2))
            if Self.valued.contains(key), let value = it.next() { options[key] = value } else { flags.insert(key) }
        }
    }

    func url(_ key: String) -> URL? { options[key].map { URL(fileURLWithPath: $0) } }
}

enum Output {
    nonisolated(unsafe) static var events = false

    static func emit(_ type: String, _ payload: [String: Any] = [:]) {
        var object = payload
        object["type"] = type
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    static func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

    static func print(_ s: String) { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        if events { emit("error", ["message": message]) } else { log(message) }
        exit(code)
    }

    static func json(_ project: Project) throws -> Any {
        try JSONSerialization.jsonObject(with: project.encoded())
    }
}

@MainActor
final class Reporter: PipelineDelegate {
    var steps: [String: PipelineStep] = [:]
    var sent: [String: Double] = [:]

    init(_ steps: [PipelineStep]) {
        for step in steps { self.steps[step.id] = step }
        if Output.events { Output.emit("steps", ["steps": steps.map(Self.json)]) }
    }

    static func json(_ step: PipelineStep) -> [String: Any] {
        var out: [String: Any] = ["id": step.id, "title": step.title, "detail": step.detail, "state": step.state.rawValue]
        if let f = step.fraction { out["fraction"] = f }
        if let s = step.seconds { out["seconds"] = s }
        return out
    }

    func update(step id: String, _ change: (inout PipelineStep) -> Void) {
        var step = steps[id] ?? PipelineStep(id: id, title: id, detail: "")
        let before = step
        change(&step)
        steps[id] = step
        if Output.events {
            // Progress arrives often; a percent is enough to draw.
            if step.state == before.state, step.detail == before.detail, let f = step.fraction,
               abs(f - (sent[id] ?? -1)) < 0.01 { return }
            sent[id] = step.fraction ?? -1
            Output.emit("step", ["step": Self.json(step)])
        } else if step.state != before.state, step.state == .done || step.state == .skipped {
            Output.log("· \(step.title): \(step.detail)\(step.seconds.map { String(format: " (%.2f s)", $0) } ?? "")")
        }
    }

    func peaksReady(_ peaks: [Float], duration: Double) {
        if Output.events { Output.emit("peaks", ["duration": duration, "peaks": peaks.map { (Double($0) * 10_000).rounded() / 10_000 }]) }
    }

    func chooseLanguage(_ prompt: LanguagePrompt) async -> LanguageChoice {
        guard Output.events else {
            Output.log("Voz does not support \(prompt.language); transcribing with Voz anyway.")
            return .voz(prompt.language)
        }
        Output.emit("chooseLanguage", ["language": prompt.language, "confidence": prompt.confidence,
                                        "supported": Array(Voz.supportedLanguages).sorted()])
        let line = await Task.detached { readLine() }.value
        guard let data = line?.data(using: .utf8),
              let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              answer["choice"] as? String == "voz" else { return .cancel }
        return .voz(answer["language"] as? String ?? prompt.language)
    }
}

func ensure(_ kinds: [ModelKind]) async throws {
    for kind in kinds where !Engines.shared.isDownloaded(kind) {
        if !Output.events { Output.log("Downloading \(kind.engine)…") }
        let sent = Progress()
        try await Engines.shared.download(kind) { fraction in
            guard Output.events, sent.advance(to: fraction) else { return }
            Output.emit("download", ["kind": kind.rawValue, "fraction": fraction])
        }
        if Output.events { Output.emit("download", ["kind": kind.rawValue, "fraction": 1.0]) }
    }
}

/// The last download fraction reported, so progress goes out in whole percents.
final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0

    func advance(to fraction: Double) -> Bool {
        lock.withLock {
            guard fraction - last >= 0.01 else { return false }
            last = fraction
            return true
        }
    }
}

func models() -> [[String: Any]] {
    ModelKind.allCases.map { kind in
        var out: [String: Any] = ["kind": kind.rawValue, "title": kind.title, "engine": kind.engine, "detail": kind.detail,
                                  "required": kind.isRequired, "available": kind.isAvailable,
                                  "downloaded": kind.isAvailable && Engines.shared.isDownloaded(kind)]
        if let mb = kind.approxMB { out["approxMB"] = mb }
        return out
    }
}

func process(_ args: Arguments) async {
    guard let path = args.positional.first else { Output.fail("usage: murmur process <media> […]", code: 64) }
    let media = URL(fileURLWithPath: path)
    let stems = args.options["stems"]?.split(separator: ",").map { URL(fileURLWithPath: String($0)) }
    let cache = args.url("cache") ?? FileManager.default.temporaryDirectory.appendingPathComponent("murmur-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let input = Pipeline.Input(media: media, micStem: stems?.first, systemStem: stems?.dropFirst().first,
                               enhance: args.flags.contains("enhance"), fillers: !args.flags.contains("no-fillers"),
                               summarize: args.flags.contains("title") && Summarizer.isAvailable,
                               language: args.options["language"], cache: cache)

    var kinds = ModelKind.allCases.filter(\.isRequired)
    if input.enhance { kinds.append(.clear) }
    if input.fillers { kinds.append(.uhm) }
    if args.flags.contains("redact") { kinds.append(.redact) }
    do { try await ensure(kinds) } catch { Output.fail("Download failed: \(error.localizedDescription)", code: 2) }

    let started = Date()
    do {
        let info = try await AudioDecoder.info(media)
        guard info.hasAudio else { throw AudioDecoder.DecodeError.noAudio }
        let reporter = await Reporter(Pipeline.steps(for: input))
        let out = try await Pipeline.run(input, delegate: reporter)
        var project = Project()
        project.status = .ready
        project.media = MediaRef(path: media.path, hasVideo: info.hasVideo)
        project.duration = out.duration
        project.words = out.words
        project.speakers = out.speakers
        project.language = out.language
        project.languageConfidence = out.confidence
        project.languageWarning = out.warning
        project.transcriber = out.transcriber
        project.title = out.title
        project.titleIsGenerated = out.title != nil
        project.summary = out.summary
        project.processedAt = Date()
        if args.flags.contains("redact") {
            project.redactions = try await RedactionFinder.find(in: project.words)
            project.settings.redact = true
        }
        if let url = args.url("out") { try project.encoded().write(to: url, options: .atomic) }
        if Output.events {
            var payload: [String: Any] = ["project": try Output.json(project), "seconds": Date().timeIntervalSince(started)]
            if let enhanced = out.enhancedMedia { payload["enhancedMedia"] = enhanced.path }
            Output.emit("done", payload)
        } else {
            Output.log(String(format: "Done in %.1f s · %@ · %d words · %d speakers", Date().timeIntervalSince(started),
                              out.language, out.words.count, out.speakers.count))
            if let warning = out.warning { Output.log("Warning: \(warning)") }
            Output.print(Renderer.render(project, format: .timestamps, options: RenderOptions(hideFillers: false)))
        }
        exit(0)
    } catch is Pipeline.Cancelled {
        Output.fail("Cancelled", code: 130)
    } catch {
        Output.fail("Failed: \(error.localizedDescription)")
    }
}

func load(_ args: Arguments, _ command: String) -> (URL, Project) {
    guard let path = args.positional.first else { Output.fail("usage: murmur \(command) <project.json> […]", code: 64) }
    let url = URL(fileURLWithPath: path)
    do { return (url, try Project.decode(Data(contentsOf: url))) } catch { Output.fail("Could not read \(path): \(error.localizedDescription)") }
}

let all = CommandLine.arguments
let command = all.count > 1 ? all[1] : "help"
let args = Arguments(all.dropFirst(2))
Output.events = args.flags.contains("events")

switch command {
case "process":
    await process(args)
case "models":
    if Output.events { Output.emit("models", ["models": models()]) } else {
        for m in models() {
            let state = (m["available"] as? Bool) == false ? "not on this computer" : (m["downloaded"] as? Bool) == true ? "ready" : "missing"
            Output.print("\(m["engine"]!)\t\(state)\t\(m["detail"]!)")
        }
    }
case "download":
    let names = args.positional.first ?? "required"
    let kinds = names == "required" ? ModelKind.allCases.filter(\.isRequired)
        : names.split(separator: ",").compactMap { ModelKind(rawValue: String($0)) }
    guard !kinds.isEmpty, kinds.allSatisfy(\.isAvailable) else { Output.fail("Unknown or unavailable model: \(names)", code: 64) }
    do { try await ensure(kinds) } catch { Output.fail("Download failed: \(error.localizedDescription)", code: 2) }
    if Output.events { Output.emit("models", ["models": models()]) }
case "render":
    let (_, project) = load(args, command)
    guard let format = TextFormat(rawValue: args.options["format"] ?? "plain") else { Output.fail("Unknown format", code: 64) }
    let options = RenderOptions(speakerNames: !args.flags.contains("no-names"), hideFillers: !args.flags.contains("keep-fillers"),
                                relativeTimes: args.flags.contains("relative"))
    Output.print(Renderer.render(project, format: format, options: options))
case "redact":
    var (url, project) = load(args, command)
    do {
        try await ensure([.redact])
        project.redactions = try await RedactionFinder.find(in: project.words)
        try project.encoded().write(to: url, options: .atomic)
        if Output.events { Output.emit("done", ["project": try Output.json(project)]) }
    } catch { Output.fail("Redaction failed: \(error.localizedDescription)") }
case "decode":
    guard let path = args.positional.first, let out = args.url("out") else { Output.fail("usage: murmur decode <media> --out audio.wav", code: 64) }
    do {
        let samples = try await AudioDecoder.decode(URL(fileURLWithPath: path))
        try WAVFile.write(samples, sampleRate: 16_000, to: out)
        Output.log(String(format: "%.2f s of audio", Double(samples.count) / 16_000))
    } catch { Output.fail("Decode failed: \(error.localizedDescription)") }
default:
    Output.log("usage: murmur process|models|download|render|redact|decode … (see Sources/murmur/main.swift)")
    exit(command == "help" ? 0 : 64)
}
