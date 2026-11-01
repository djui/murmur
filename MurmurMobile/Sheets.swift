import MurmurCore
import SwiftUI
import UIKit
import Voz

// MARK: - Export

/// Text in any of the formats, or audio clips, handed to the share sheet.
struct ExportView: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss
    @State private var range: Range = .whole
    @State private var kind: Kind = .text(.timestamps)
    @State private var speakerNames = true
    @State private var hideFillers = AppSettings.bool(AppSettings.hideFillersInExport)
    @State private var relativeTimes = false
    @State private var joined = true
    @State private var working = false
    @State private var shared: SharedFiles?
    @State private var error: String?

    enum Range: Hashable { case whole, mark(UUID), allMarks }
    enum Kind: Hashable { case text(TextFormat), audio }
    struct SharedFiles: Identifiable { let id = UUID(); let urls: [URL] }

    private var project: Project { session.project }

    private var sections: [TranscriptSection]? {
        switch range {
        case .whole: nil
        case .mark(let id): project.marks.first { $0.id == id }.map { [TranscriptSection(name: $0.name, start: $0.start, end: $0.end)] }
        case .allMarks: project.marks.map { TranscriptSection(name: $0.name, start: $0.start, end: $0.end) }
        }
    }

    private var options: RenderOptions {
        var o = AppSettings.renderOptions
        o.speakerNames = speakerNames
        o.hideFillers = hideFillers
        o.relativeTimes = relativeTimes
        if !session.isRedacting { o.redactionStyle = .labels }
        return o
    }

    private var renderProject: Project {
        var p = project
        if !session.isRedacting { p.redactions = nil }
        return p
    }

    private var baseName: String {
        switch range {
        case .whole: project.displayTitle
        case .mark(let id): project.marks.first { $0.id == id }?.name ?? project.displayTitle
        case .allMarks: "\(project.displayTitle) (marks)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    Picker("Part", selection: $range) {
                        Text("Whole recording").tag(Range.whole)
                        if project.marks.count > 1 { Text("All marks").tag(Range.allMarks) }
                        ForEach(project.marks) { Text($0.name).tag(Range.mark($0.id)) }
                    }
                    Picker("As", selection: $kind) {
                        ForEach(TextFormat.allCases) { Text($0.title).tag(Kind.text($0)) }
                        Text("Audio (.m4a)").tag(Kind.audio)
                    }
                }
                if case .text(let format) = kind {
                    Section {
                        Toggle("Speaker names", isOn: $speakerNames)
                        Toggle("Leave out um and uh", isOn: $hideFillers)
                        if sections != nil { Toggle("Times from the start of each part", isOn: $relativeTimes) }
                    }
                    Section("Preview") {
                        Text(String(Renderer.render(renderProject, sections: sections, format: format, options: options).prefix(1500)))
                            .font(.system(.footnote, design: format == .json || format == .srt || format == .vtt ? .monospaced : .default))
                            .foregroundStyle(.secondary)
                            .lineLimit(14)
                            .textSelection(.enabled)
                    }
                } else {
                    Section {
                        if range == .allMarks { Toggle("One file", isOn: $joined) }
                    } footer: {
                        Text(session.isRedacting ? "Hidden personal details are bleeped." : "Clips are cut from \(project.settings.enhance ? "the enhanced" : "the original") audio.")
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else { Button("Share…") { prepare() } }
                }
            }
            .sheet(item: $shared) { ShareSheet(items: $0.urls) }
            .alert("Couldn’t export", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func prepare() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = baseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        switch kind {
        case .text(let format):
            let url = folder.appendingPathComponent(safe).appendingPathExtension(format.fileExtension)
            do {
                try Renderer.render(renderProject, sections: sections, format: format, options: options)
                    .write(to: url, atomically: true, encoding: .utf8)
                shared = SharedFiles(urls: [url])
            } catch { self.error = error.localizedDescription }
        case .audio:
            guard let source = session.playbackURL else { return }
            let clips = (sections ?? [TranscriptSection(start: 0, end: project.duration)])
                .map { ClipExporter.Clip(name: $0.name ?? project.displayTitle, start: $0.start, end: min($0.end, project.duration)) }
            let joined = clips.count == 1 || self.joined
            let destination = joined ? folder.appendingPathComponent(safe).appendingPathExtension("m4a") : folder
            let bleeps = session.hiddenSpans.map { $0.start...$0.end }
            working = true
            Task {
                do {
                    let files = try await ClipExporter.export(source: source, clips: clips, video: false, joined: joined,
                                                              destination: destination, bleeps: bleeps)
                    shared = SharedFiles(urls: files)
                } catch { self.error = error.localizedDescription }
                working = false
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Speakers

struct SpeakerRef: Identifiable { let id: Int }

struct SpeakersView: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.project.speakers) { speaker in
                        NavigationLink {
                            SpeakerPage(session: session, speaker: speaker.id)
                        } label: {
                            SpeakerLabel(session: session, speaker: speaker.id)
                        }
                    }
                } footer: {
                    Text("Tap a speaker to rename them, or to merge them with another if one voice was split in two.")
                }
            }
            .navigationTitle("Speakers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Colour, name and share of the talking.
struct SpeakerLabel: View {
    let session: ProjectSession
    let speaker: Int

    var body: some View {
        let talk = session.project.talkTime
        let total = max(1, talk.values.reduce(0, +))
        HStack(spacing: 12) {
            Circle().fill(SpeakerScheme.current.color(session.color(of: speaker))).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.project.name(of: speaker)).font(.body.weight(.medium))
                Text("\(Int(((talk[speaker] ?? 0) / total * 100).rounded()))% of the talking")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One speaker: their name, how much they talk, and "Same person as…" to merge them into another.
struct SpeakerPage: View {
    let session: ProjectSession
    let speaker: Int
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        let project = session.project
        let talk = project.talkTime
        let total = max(1, talk.values.reduce(0, +))
        let lines = session.paragraphsBySpeaker[speaker] ?? []
        List {
            Section {
                HStack(spacing: 12) {
                    Circle().fill(SpeakerScheme.current.color(session.color(of: speaker))).frame(width: 16, height: 16)
                    TextField(project.speaker(speaker)?.displayName ?? "Name", text: $name)
                        .font(.title3.weight(.semibold))
                        .submitLabel(.done)
                        .onSubmit { session.rename(speaker: speaker, to: name) }
                }
                LabeledContent("Talking", value: "\(Int(((talk[speaker] ?? 0) / total * 100).rounded()))%")
                LabeledContent("Lines", value: "\(lines.count)")
                if let first = lines.first {
                    Button("Play Their First Line", systemImage: "play") { session.player.play(from: first.start, to: first.end) }
                }
            }
            let others = project.speakers.filter { $0.id != speaker }
            if !others.isEmpty {
                Section {
                    ForEach(others) { other in
                        HStack(spacing: 12) {
                            Circle().fill(SpeakerScheme.current.color(session.color(of: other.id))).frame(width: 12, height: 12)
                            Text(project.name(of: other.id))
                            Spacer()
                            Button("Merge") {
                                session.merge(speaker, into: other.id)
                                session.flash("Merged into \(project.name(of: other.id))")
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Merge \(project.name(of: speaker)) into \(project.name(of: other.id))")
                        }
                    }
                } header: {
                    Text("Same person as…")
                } footer: {
                    Text("If Murmur split one voice in two, merge them: every line of \(project.name(of: speaker)) goes to the other speaker. Undo puts it back.")
                }
            }
        }
        .navigationTitle(project.name(of: speaker))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = project.speaker(speaker)?.name ?? "" }
        .onDisappear {
            if name != (session.project.speaker(speaker)?.name ?? ""), session.project.speaker(speaker) != nil {
                session.rename(speaker: speaker, to: name)
            }
        }
    }
}

// MARK: - Marks

struct MarksView: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Mark?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.project.marks) { mark in
                    Button {
                        session.player.play(from: mark.start, to: mark.end)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mark.name).foregroundStyle(.primary)
                            Text("\(Timecode.short(mark.start)) – \(Timecode.short(mark.end)) · \(Timecode.short(mark.duration))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { session.remove(mark: mark.id) }
                        Button("Rename", systemImage: "pencil") { newName = mark.name; renaming = mark }.tint(.orange)
                    }
                    .contextMenu {
                        Button("Rename…", systemImage: "pencil") { newName = mark.name; renaming = mark }
                        Button("Copy Text", systemImage: "doc.on.doc") { session.copy(mark: mark) }
                        Button("Delete", systemImage: "trash", role: .destructive) { session.remove(mark: mark.id) }
                    }
                }
            }
            .overlay {
                if session.project.marks.isEmpty {
                    ContentUnavailableView("No Marks", systemImage: "bookmark",
                                           description: Text("Tap the bookmark below the timeline at the start of a section and again at its end."))
                }
            }
            .navigationTitle("Marks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Rename Mark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { if let m = renaming { session.rename(mark: m.id, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Language

/// Transcribe again, detecting the language or in one chosen by hand.
struct LanguageView: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    private var languages: [(code: String, name: String)] {
        Voz.supportedLanguages.map { ($0, Locale.current.localizedString(forLanguageCode: $0) ?? $0) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Detect the Language") { run(nil) }
                } footer: {
                    if let l = session.project.language {
                        Text("Last time: \(Locale.current.localizedString(forLanguageCode: l) ?? l). Speaker names and marks are kept; edits to the words are replaced.")
                    }
                }
                Section("Transcribe as") {
                    ForEach(languages, id: \.code) { language in
                        Button { run(language.code) } label: {
                            HStack {
                                Text(language.name).foregroundStyle(.primary)
                                Spacer()
                                if language.code == session.project.language { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transcribe Again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func run(_ language: String?) {
        session.retranscribe(language: language)
        dismiss()
    }
}

// MARK: - Project info

/// The project's switches and facts, each in one place: Enhance and Hide Personal Details, what was heard,
/// and the hidden details one by one.
struct ProjectInfoView: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let project = session.project
        NavigationStack {
            List {
                if let summary = project.summary {
                    Section("Summary") { Text(summary) }
                }
                Section {
                    Toggle(isOn: Binding(get: { project.settings.enhance }, set: { session.setEnhance($0) })) {
                        Label("Enhance Audio", systemImage: "wand.and.stars")
                    }
                    .disabled(session.isProcessing)
                    Toggle(isOn: Binding(get: { session.isRedacting }, set: { session.setRedact($0) })) {
                        Label("Hide Personal Details", systemImage: "eye.slash")
                    }
                    .disabled(project.words.isEmpty || session.isFindingDetails)
                } footer: {
                    Text("Enhance removes noise and echo. Hidden details are bleeped in the audio and replaced in the text and exports.")
                }
                Section("Transcript") {
                    if let l = project.language {
                        LabeledContent("Language", value: (Locale.current.localizedString(forLanguageCode: l) ?? l)
                                       + (project.languageConfidence.map { " · \(Int($0 * 100))%" } ?? ""))
                    }
                    LabeledContent("Transcriber", value: project.transcriber == "apple" ? "Apple on-device" : "Voz")
                    LabeledContent("Length", value: Timecode.short(project.duration))
                    LabeledContent("Speakers", value: "\(project.speakers.count)")
                    LabeledContent("Words", value: "\(project.words.filter { !$0.isFiller }.count)")
                    if let at = project.processedAt {
                        LabeledContent("Made", value: at.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if session.isRedacting, let spans = project.redactions, !spans.isEmpty {
                    Section {
                        ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                            Button { session.toggleReveal(span) } label: {
                                HStack {
                                    Text(span.revealed ? span.original : "[\(span.category)]")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(Timecode.short(span.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    Image(systemName: span.revealed ? "eye" : "eye.slash").foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Hidden Details")
                    } footer: {
                        Text("Tap one to show it in the transcript and exports anyway.")
                    }
                }
            }
            .navigationTitle("Project Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
