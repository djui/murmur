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

struct SpeakersView: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.speakerScheme) private var schemeName = SpeakerScheme.vivid.rawValue

    var body: some View {
        let project = session.project
        let talk = project.talkTime
        let total = max(1, talk.values.reduce(0, +))
        NavigationStack {
            List {
                Section {
                    ForEach(project.speakers) { speaker in
                        SpeakerRow(session: session, speaker: speaker,
                                   color: (SpeakerScheme(rawValue: schemeName) ?? .vivid).color(session.color(of: speaker.id)),
                                   share: (talk[speaker.id] ?? 0) / total)
                    }
                } footer: {
                    Text("Names are used in the transcript, exports and mark names. Merge two speakers if Who split one voice.")
                }
            }
            .navigationTitle("Speakers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SpeakerRow: View {
    let session: ProjectSession
    let speaker: Speaker
    let color: Color
    let share: Double
    @State private var name = ""

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                TextField(speaker.displayName, text: $name)
                    .font(.body.weight(.medium))
                    .submitLabel(.done)
                    .onSubmit { session.rename(speaker: speaker.id, to: name) }
                Text("\(Int((share * 100).rounded()))% of the talking")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Play First Line", systemImage: "play") {
                    if let p = session.paragraphsBySpeaker[speaker.id]?.first { session.player.play(from: p.start, to: p.end) }
                }
                Menu("Merge Into", systemImage: "arrow.triangle.merge") {
                    ForEach(session.project.speakers.filter { $0.id != speaker.id }) { other in
                        Button(session.project.name(of: other.id)) { session.merge(speaker.id, into: other.id) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .accessibilityLabel("Actions for \(session.project.name(of: speaker.id))")
        }
        .onAppear { name = speaker.name }
        .onDisappear { if name != speaker.name { session.rename(speaker: speaker.id, to: name) } }
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

// MARK: - Details

/// Summary, language and how the transcript was made; hidden personal details to show one by one.
struct DetailsView: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let project = session.project
        NavigationStack {
            List {
                if let summary = project.summary {
                    Section("Summary") { Text(summary) }
                }
                Section("Transcript") {
                    if let l = project.language {
                        LabeledContent("Language", value: (Locale.current.localizedString(forLanguageCode: l) ?? l)
                                       + (project.languageConfidence.map { " · \(Int($0 * 100))%" } ?? ""))
                    }
                    LabeledContent("Transcriber", value: project.transcriber == "apple" ? "Apple on-device" : "Voz")
                    LabeledContent("Length", value: Timecode.short(project.duration))
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
                        Text("Personal Details")
                    } footer: {
                        Text("Tap one to show it in the transcript and exports anyway.")
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
