import AppKit
import Foundation
import MurmurCore
import Observation

/// Everything one project window needs: the project, playback, selection and processing.
@Observable
@MainActor
final class ProjectSession: PipelineDelegate {
    let document: ProjectDocument
    let fileURL: URL?
    private(set) var project: Project
    private(set) var peaks: [Float]
    private(set) var paragraphs: [Paragraph] = []
    /// The same paragraphs grouped by speaker, so each timeline lane draws only its own.
    private(set) var paragraphsBySpeaker: [Int: [Paragraph]] = [:]
    /// Each speaker's position in the list, which picks their colour; looked up on every timeline frame.
    private var colorIndex: [Int: Int] = [:]
    /// The speaker heard in each 10 ms waveform bin, or -1 for silence.
    private(set) var speakerBins: [Int16] = []
    let player = PlayerModel()

    var selection: ClosedRange<Double>?
    /// Where a section being marked with M started, until M is pressed again.
    var pendingStart: Double?
    /// Bumped to ask the transcript to scroll back to the current line.
    var jumpRequest = 0
    var zoom: Double = 1 {
        didSet { if zoom < 1 || zoom > 64 { zoom = min(64, max(1, zoom)) } }
    }
    var editing = false
    var search = ""
    var showExport = false

    var steps: [PipelineStep] = []
    var isFindingDetails = false
    var isProcessing = false
    var languagePrompt: LanguagePrompt?
    var toast: String?

    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var languageContinuation: CheckedContinuation<LanguageChoice, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(document: ProjectDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        project = document.project
        peaks = document.peaks
        refreshDerived()
        loadMedia()
    }

    // MARK: - Media

    var mediaURL: URL? { project.media?.resolvedURL() }
    var mediaMissing: Bool { project.media != nil && mediaURL == nil }
    var enhancedURL: URL { ProjectFile.cacheFolder(for: project).appendingPathComponent("enhanced.m4a") }
    var hasEnhancedAudio: Bool { FileManager.default.fileExists(atPath: enhancedURL.path) }

    /// The file playback and clip export use: the enhanced copy when Enhance is on.
    var playbackURL: URL? {
        if project.settings.enhance, hasEnhancedAudio { return enhancedURL }
        return mediaURL
    }

    func loadMedia() {
        player.load(playbackURL, duration: project.duration)
    }

    func locateMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audiovisualContent]
        panel.message = "Locate \(URL(fileURLWithPath: project.media?.path ?? "").lastPathComponent)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        update("Locate Media") { $0.media?.path = url.path; $0.media?.bookmark = try? url.bookmarkData() }
        loadMedia()
    }

    // MARK: - Changes and undo

    /// Applies a user change with undo support.
    func update(_ action: String, _ change: (inout Project) -> Void) {
        let old = project
        change(&project)
        guard project != old else { return }
        document.project = project
        undoManager?.registerUndo(withTarget: self) { $0.restore(old, action: action) }
        undoManager?.setActionName(action)
        refreshDerived()
    }

    private func restore(_ snapshot: Project, action: String) {
        let current = project
        project = snapshot
        document.project = snapshot
        undoManager?.registerUndo(withTarget: self) { $0.restore(current, action: action) }
        undoManager?.setActionName(action)
        refreshDerived()
        loadMedia()
    }

    /// Applies a change that should not be undoable (processing results) but still saves.
    private func replace(_ change: (inout Project) -> Void) {
        change(&project)
        document.project = project
        document.peaks = peaks
        undoManager?.registerUndo(withTarget: self) { _ in }
        undoManager?.removeAllActions(withTarget: self)
        refreshDerived()
    }

    private func refreshDerived() {
        paragraphs = Merge.paragraphs(project.words)
        paragraphsBySpeaker = Dictionary(grouping: paragraphs, by: \.speaker)
        colorIndex = Dictionary(project.speakers.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let bins = peaks.isEmpty ? Int(project.duration * Double(Peaks.binsPerSecond)) + 1 : peaks.count
        var out = [Int16](repeating: -1, count: max(0, bins))
        let per = Double(Peaks.binsPerSecond)
        for w in project.words where !w.isFiller {
            let lo = max(0, Int((w.start - 0.08) * per)), hi = min(out.count, Int((w.end + 0.08) * per) + 1)
            if lo < hi { for i in lo..<hi { out[i] = Int16(w.speaker) } }
        }
        speakerBins = out
    }

    // MARK: - Processing

    func processIfNeeded() {
        guard !isProcessing else { return }
        if project.status == .new || project.status == .processing { process() }
    }

    func retranscribe(language: String? = nil) {
        guard !isProcessing else { return }
        process(language: language)
    }

    func process(language: String? = nil) {
        guard let media = mediaURL else {
            replace { $0.status = .failed; $0.failure = "The media file is missing." }
            return
        }
        let enhance = project.settings.enhance
        let fillers = AppSettings.bool(AppSettings.detectFillers)
        let summarize = AppSettings.bool(AppSettings.autoTitle) && Summarizer.isAvailable
            && (project.title == nil || project.titleIsGenerated)
        let input = Pipeline.Input(
            media: media,
            micStem: project.media?.micStem.map { URL(fileURLWithPath: $0) },
            systemStem: project.media?.systemStem.map { URL(fileURLWithPath: $0) },
            enhance: enhance, fillers: fillers, summarize: summarize,
            language: language, cache: ProjectFile.cacheFolder(for: project))
        steps = Pipeline.steps(for: input)
        isProcessing = true
        replace { $0.status = .processing; $0.failure = nil }

        Task {
            do {
                if enhance { try await ModelManager.shared.ensure(.clear) }
                if fillers { try await ModelManager.shared.ensure(.uhm) }
                let out = try await Pipeline.run(input, delegate: self)
                replace { p in
                    p.duration = out.duration
                    p.words = out.words
                    p.speakers = Self.keepNames(old: p.speakers, new: out.speakers)
                    p.language = out.language
                    p.languageConfidence = out.confidence
                    p.languageWarning = out.warning
                    p.transcriber = out.transcriber
                    if let title = out.title { p.title = title; p.titleIsGenerated = true }
                    if let summary = out.summary { p.summary = summary }
                    p.status = .ready
                    p.processedAt = Date()
                    p.redactions = nil
                }
                loadMedia()
                if project.settings.redact == true { await findPersonalDetails() }
            } catch is Pipeline.Cancelled {
                replace { $0.status = project.words.isEmpty ? .failed : .ready; $0.failure = "Transcription was cancelled." }
            } catch {
                replace { $0.status = .failed; $0.failure = error.localizedDescription }
            }
            isProcessing = false
        }
    }

    /// Keeps names the user typed when the same speaker ids come back from a new run.
    static func keepNames(old: [Speaker], new: [Speaker]) -> [Speaker] {
        new.map { s in
            var s = s
            if let o = old.first(where: { $0.id == s.id }), !o.name.isEmpty { s.name = o.name }
            return s
        }
    }

    // PipelineDelegate

    func update(step id: String, _ change: (inout PipelineStep) -> Void) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        change(&steps[i])
    }

    func peaksReady(_ peaks: [Float], duration: Double) {
        self.peaks = peaks
        document.peaks = peaks
        project.duration = duration
        document.project.duration = duration
        refreshDerived()
        loadMedia()
    }

    func chooseLanguage(_ prompt: LanguagePrompt) async -> LanguageChoice {
        await withCheckedContinuation { continuation in
            languageContinuation = continuation
            languagePrompt = prompt
        }
    }

    func answerLanguage(_ choice: LanguageChoice) {
        languagePrompt = nil
        languageContinuation?.resume(returning: choice)
        languageContinuation = nil
    }

    // MARK: - Selection, marks, copy

    func select(_ range: ClosedRange<Double>?) {
        guard let range, range.upperBound - range.lowerBound > 0.15 else { selection = nil; return }
        selection = range
    }

    /// M: press at the start of a section and again at its end to save it as a mark. With a selection
    /// already made (by dragging), M saves that selection instead.
    func toggleMarkSection() {
        let t = player.time
        if let start = pendingStart {
            pendingStart = nil
            let lo = min(start, t), hi = max(start, t)
            guard hi - lo >= 0.3 else { flash("Section cancelled: it was shorter than a moment"); return }
            selection = lo...hi
            addMark()
        } else if selection != nil {
            addMark()
        } else {
            pendingStart = t
            flash("Section starts at \(Timecode.short(t)) · press M again at the end")
        }
    }

    func cancelPendingSection() { pendingStart = nil }

    /// Extends the selection to cover a paragraph (shift-click).
    func extendSelection(to paragraph: Paragraph) {
        let lo = min(selection?.lowerBound ?? paragraph.start, paragraph.start)
        let hi = max(selection?.upperBound ?? paragraph.end, paragraph.end)
        select(lo...hi)
    }

    func addMark() {
        guard let selection else { flash("Select a section first, then press M"); return }
        let name = "Mark \(project.marks.count + 1)"
        update("Add Mark") { $0.marks.append(Mark(name: name, start: selection.lowerBound, end: selection.upperBound)) }
        self.selection = nil
        flash("Saved as “\(name)” · rename it in the sidebar")
    }

    func copyAll() { copy(sections: nil, what: "transcript") }

    func copySelection() {
        guard let selection else { return }
        copy(sections: [TranscriptSection(start: selection.lowerBound, end: selection.upperBound)], what: "selection")
    }

    func copy(mark: Mark) {
        copy(sections: [TranscriptSection(name: mark.name, start: mark.start, end: mark.end)], what: "“\(mark.name)”")
    }

    func copy(sections: [TranscriptSection]?, what: String) {
        let format = AppSettings.copyFormatValue
        let text = Renderer.render(project, sections: sections, format: format, options: AppSettings.renderOptions)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("Copied \(what) as \(format.title)")
    }

    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: - Editing

    func replaceText(of paragraph: Paragraph, with text: String) {
        let current = Merge.join(project.words[paragraph.range])
        guard text.trimmingCharacters(in: .whitespacesAndNewlines) != current else { return }
        let (words, range) = Editing.replace(in: project.words, range: paragraph.range, with: text)
        update("Edit Text") { $0.words = words }
        retime(range)
    }

    /// Re-times edited words against the audio with Align, without a separate undo step.
    private func retime(_ range: Range<Int>) {
        guard !range.isEmpty, let url = mediaURL, let language = project.language else { return }
        let words = Array(project.words[range])
        let start = max(0, (words.first?.start ?? 0) - 1), end = (words.last?.end ?? 0) + 1
        Task {
            guard (try? await Engines.shared.align.isSupported(languageCode: language)) == true,
                  let audio = try? await AudioDecoder.decode(url, from: start, to: end) else { return }
            let shifted = words.map { var w = $0; w.start -= start; w.end -= start; return w }
            guard let refined = try? await Pipeline.refine(shifted, audio: audio, language: language) else { return }
            // Only apply if nothing changed meanwhile.
            guard project.words.indices.contains(range.upperBound - 1),
                  Array(project.words[range]).map(\.text) == words.map(\.text) else { return }
            project.words.replaceSubrange(range, with: refined.map { var w = $0; w.start += start; w.end += start; return w })
            document.project = project
            refreshDerived()
        }
    }

    func reassign(_ paragraph: Paragraph, to speaker: Int) {
        update("Change Speaker") { $0.words = Editing.reassign($0.words, range: paragraph.range, to: speaker) }
    }

    func newSpeaker(from paragraph: Paragraph) {
        update("New Speaker") { $0 = Editing.splitToNewSpeaker($0, paragraph: paragraph, from: paragraph.range.lowerBound) }
    }

    func merge(_ from: Int, into: Int) {
        update("Merge Speakers") { $0 = Editing.mergeSpeaker($0, from: from, into: into) }
    }

    func rename(speaker id: Int, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update("Rename Speaker") { p in
            if let i = p.speakers.firstIndex(where: { $0.id == id }) { p.speakers[i].name = name }
        }
    }

    func rename(mark id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update("Rename Mark") { p in
            if let i = p.marks.firstIndex(where: { $0.id == id }) { p.marks[i].name = name }
        }
    }

    func remove(mark id: UUID) {
        update("Remove Mark") { $0.marks.removeAll { $0.id == id } }
    }

    func setEnhance(_ on: Bool) {
        update(on ? "Enhance Audio" : "Original Audio") { $0.settings.enhance = on }
        if on && !hasEnhancedAudio {
            retranscribe(language: project.language)
        } else {
            loadMedia()
            flash(on ? "Enhance on · playback, transcription and export" : "Enhance off · original audio")
        }
    }

    // MARK: - Redaction

    var isRedacting: Bool { project.settings.redact == true }

    /// Hidden spans, for the transcript, exports and clip bleeps; empty while redaction is off.
    var hiddenSpans: [RedactedSpan] { isRedacting ? (project.redactions ?? []).filter { !$0.revealed } : [] }

    func setRedact(_ on: Bool) {
        if on && project.redactions == nil {
            Task { await findPersonalDetails() }
        } else {
            update(on ? "Hide Personal Details" : "Show Personal Details") { $0.settings.redact = on }
        }
    }

    func findPersonalDetails() async {
        guard !isFindingDetails else { return }
        isFindingDetails = true
        defer { isFindingDetails = false }
        flash("Looking for names, numbers and addresses…")
        do {
            try await ModelManager.shared.ensure(.redact)
            await Engines.shared.warmUp(.redact)
            let spans = try await RedactionFinder.find(in: project.words)
            update("Hide Personal Details") { $0.redactions = spans; $0.settings.redact = true }
            flash(spans.isEmpty ? "No personal details found" : "Hid \(spans.count) personal \(spans.count == 1 ? "detail" : "details")")
        } catch {
            flash("Couldn’t look for personal details: \(error.localizedDescription)")
        }
    }

    func toggleReveal(_ span: RedactedSpan) {
        update(span.revealed ? "Hide Detail" : "Show Detail") { p in
            if let i = p.redactions?.firstIndex(of: span) { p.redactions?[i].revealed.toggle() }
        }
    }

    func toggleVideo() {
        let show = !project.settings.showVideo
        update(show ? "Show Video" : "Hide Video") { $0.settings.showVideo = show }
    }

    func setTitle(_ title: String) {
        update("Rename Project") { $0.title = title; $0.titleIsGenerated = false }
    }

    // MARK: - Derived

    var activeParagraph: Paragraph? {
        let t = player.time
        return paragraphs.last { $0.start <= t + 0.05 && t < $0.end + 0.3 }
    }

    func color(of speaker: Int) -> Int {
        colorIndex[speaker] ?? speaker
    }
}
