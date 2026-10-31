import AppKit
import Foundation
import MurmurCore
import MurmurEngine
import Voz

/// `Murmur -process <media> [-language xx] [-enhance YES] [-fillers NO] [-title YES] [-stems mic,system]
/// [-out file.json]` runs the pipeline without UI and prints the transcript, for testing and scripting.
/// Flags are `-key value` pairs so AppKit reads them as defaults instead of files to open.
@MainActor
final class HeadlessRunner: PipelineDelegate {
    static func runIfRequested() -> Bool {
        if let source = UserDefaults.standard.string(forKey: "clip"), let out = UserDefaults.standard.string(forKey: "out") {
            // `-clip media -ranges 1-5,10-12 -out file|folder [-joined YES] [-video YES]`
            let ranges = (UserDefaults.standard.string(forKey: "ranges") ?? "0-5").split(separator: ",").enumerated().map { i, r in
                let p = r.split(separator: "-").compactMap { Double($0) }
                return ClipExporter.Clip(name: "Clip \(i + 1)", start: p.first ?? 0, end: p.last ?? 5)
            }
            Task {
                do {
                    let files = try await ClipExporter.export(source: URL(fileURLWithPath: source), clips: ranges,
                                                              video: UserDefaults.standard.bool(forKey: "video"),
                                                              joined: UserDefaults.standard.bool(forKey: "joined"),
                                                              destination: URL(fileURLWithPath: out),
                                                              bleeps: (UserDefaults.standard.string(forKey: "bleeps") ?? "").split(separator: ",").compactMap { r in
                                                                  let p = r.split(separator: "-").compactMap { Double($0) }
                                                                  return p.count == 2 ? p[0]...p[1] : nil
                                                              })
                    files.forEach { print($0.path) }
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("Clip export failed: \(error)\n".utf8))
                    exit(1)
                }
            }
            return true
        }
        if let stems = UserDefaults.standard.string(forKey: "mix"), let out = UserDefaults.standard.string(forKey: "out") {
            // `-mix mic.m4a,system.m4a -out recording.m4a`: what a recording does when it stops.
            Task {
                do {
                    try await StemMixer.mix(stems.split(separator: ",").map { URL(fileURLWithPath: String($0)) }, to: URL(fileURLWithPath: out))
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("Mix failed: \(error)\n".utf8))
                    exit(1)
                }
            }
            return true
        }
        if let stems = UserDefaults.standard.string(forKey: "live") {
            Task { exit(await HeadlessRunner().live(stems.split(separator: ",").map { URL(fileURLWithPath: String($0)) })) }
            return true
        }
        guard let path = UserDefaults.standard.string(forKey: "process") else { return false }
        let runner = HeadlessRunner()
        Task {
            let code = await runner.run(media: URL(fileURLWithPath: path))
            exit(code)
        }
        return true
    }

    func value(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    func flag(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.bool(forKey: key)
    }

    func run(media: URL) async -> Int32 {
        let models = ModelManager.shared
        let enhance = flag("enhance", default: false)
        let fillers = flag("fillers", default: true)
        var kinds = ModelKind.allCases.filter(\.isRequired)
        if enhance { kinds.append(.clear) }
        if fillers { kinds.append(.uhm) }
        for kind in kinds where !models.state(kind).isReady {
            log("Downloading \(kind.engine)…")
            do { try await models.ensure(kind) } catch { log("Download failed: \(error.localizedDescription)"); return 2 }
        }
        let stems = value("stems")?.split(separator: ",").map { URL(fileURLWithPath: String($0)) }
        let input = Pipeline.Input(media: media, micStem: stems?.first, systemStem: stems?.dropFirst().first,
                                   enhance: enhance, fillers: fillers,
                                   summarize: flag("title", default: false) && Summarizer.isAvailable,
                                   language: value("language"),
                                   cache: FileManager.default.temporaryDirectory.appendingPathComponent("murmur-headless"))
        try? FileManager.default.createDirectory(at: input.cache, withIntermediateDirectories: true)
        let started = Date()
        do {
            let out = try await Pipeline.run(input, delegate: self)
            var project = Project()
            project.duration = out.duration
            project.words = out.words
            project.speakers = out.speakers
            project.language = out.language
            project.title = out.title
            project.summary = out.summary
            project.languageWarning = out.warning
            log(String(format: "Done in %.1f s · %@ · %d words · %d speakers · %@", Date().timeIntervalSince(started),
                       out.language, out.words.count, out.speakers.count, out.transcriber))
            if let title = out.title { log("Title: \(title)\nSummary: \(out.summary ?? "")") }
            if let warning = out.warning { log("Warning: \(warning)") }
            if flag("redact", default: false) {
                try await ModelManager.shared.ensure(.redact)
                project.redactions = try await RedactionFinder.find(in: project.words)
                project.settings.redact = true
                log("Redacted: " + (project.redactions ?? []).map { "\($0.category)=\($0.original)" }.joined(separator: ", "))
            }
            print(Renderer.render(project, format: .timestamps, options: RenderOptions(hideFillers: false)))
            if let path = value("out") {
                try Renderer.render(project, format: .json, options: RenderOptions(hideFillers: false))
                    .write(toFile: path, atomically: true, encoding: .utf8)
            }
            return 0
        } catch {
            log("Failed: \(error.localizedDescription)")
            return 1
        }
    }

    /// `-live mic.m4a,system.m4a` streams two stems through live transcription at 4× speed and prints
    /// the lines as the compact window would show them.
    func live(_ stems: [URL]) async -> Int32 {
        guard stems.count == 2, let voz = try? await Engines.shared.voz() else { log("Need two stems and the Voz model"); return 2 }
        let mic = voz.liveTranscriber(), system = voz.liveTranscriber()
        var micWords: [(MurmurCore.Word, Bool)] = [], systemWords: [(MurmurCore.Word, Bool)] = []
        func collect(_ live: LiveTranscriber, isMe: Bool) -> Task<Void, Never> {
            Task { @MainActor in
                for await u in live.updates {
                    let words = u.committedWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), false) }
                        + u.tentativeWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), true) }
                    if isMe { micWords = words } else { systemWords = words }
                }
            }
        }
        let a = collect(mic, isMe: true), b = collect(system, isMe: false)
        guard let m = try? await AudioDecoder.decode(stems[0]), let s = try? await AudioDecoder.decode(stems[1]) else { return 1 }
        let chunk = 1600
        var updates = 0
        for start in stride(from: 0, to: max(m.count, s.count), by: chunk) {
            if start < m.count { await mic.append(Array(m[start..<min(m.count, start + chunk)]), sampleRate: 16_000) }
            if start < s.count { await system.append(Array(s[start..<min(s.count, start + chunk)]), sampleRate: 16_000) }
            try? await Task.sleep(for: .milliseconds(25))
            if start % (16_000 * 10) == 0 {
                updates += 1
                let lines = LiveLines.build(mic: micWords, system: systemWords)
                log(String(format: "t=%3.0fs  %d lines, last: %@", Double(start) / 16_000, lines.count,
                           lines.last.map { "\($0.isMe ? "Me" : "Others"): \($0.text)" } ?? "-"))
            }
        }
        await mic.finish()
        await system.finish()
        _ = await (a.value, b.value)
        for line in LiveLines.build(mic: micWords, system: systemWords) {
            print("[\(Timecode.short(line.start))] \(line.isMe ? "Me" : "Others"): \(line.text)")
        }
        return 0
    }

    func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

    func update(step id: String, _ change: (inout PipelineStep) -> Void) {
        var step = PipelineStep(id: id, title: id, detail: "")
        change(&step)
        if step.state == .done || step.state == .skipped {
            log("· \(id): \(step.state)\(step.detail.isEmpty ? "" : " — \(step.detail)")\(step.seconds.map { String(format: " (%.2f s)", $0) } ?? "")")
        }
    }

    func peaksReady(_ peaks: [Float], duration: Double) {}

    func chooseLanguage(_ prompt: LanguagePrompt) async -> LanguageChoice {
        log("Language \(prompt.language) is not supported by Voz; using Apple: \(prompt.appleSupports)")
        return prompt.appleSupports ? .apple(prompt.language) : .voz(prompt.language)
    }
}
