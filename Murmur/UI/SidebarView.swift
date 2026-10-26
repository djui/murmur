import AVKit
import MurmurCore
import SwiftUI

struct SidebarView: View {
    @Bindable var session: ProjectSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if session.project.media?.hasVideo == true && session.project.settings.showVideo {
                    VideoPanel(player: session.player.player, time: session.player.time)
                }
                if session.mediaMissing { MissingMediaCard(session: session) }
                if let warning = session.project.languageWarning { WarningCard(text: warning, session: session) }
                if let summary = session.project.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Summary", trailing: AnyView(Text("Apple Intelligence").font(.system(size: 11)).foregroundStyle(.secondary)))
                        Text(summary).font(.system(size: 12.5)).foregroundStyle(.primary.opacity(0.85)).textSelection(.enabled)
                    }
                }
                SpeakersSection(session: session)
                MarksSection(session: session)
                SelectionSection(session: session)
                InfoSection(session: session)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
    }
}

struct VideoPanel: NSViewRepresentable {
    let player: AVPlayer
    let time: Double

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
        let w = proposal.width ?? 280
        return CGSize(width: w, height: w * 9 / 16)
    }
}

struct MissingMediaCard: View {
    let session: ProjectSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Media missing", systemImage: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            Text(session.project.media?.path ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            Button("Locate File…") { session.locateMedia() }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
    }
}

struct WarningCard: View {
    let text: String
    let session: ProjectSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Check the language", systemImage: "character.bubble").font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            LanguageMenu(session: session, title: "Transcribe Again As…")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.1)))
    }
}

struct SpeakersSection: View {
    @Bindable var session: ProjectSession

    var body: some View {
        let talk = session.project.talkTime
        let total = max(0.001, talk.values.reduce(0, +))
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Speakers", trailing: AnyView(mergeMenu))
            ForEach(session.project.speakers) { speaker in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle().fill(Palette.speaker(session.color(of: speaker.id))).frame(width: 10, height: 10)
                        SpeakerNameField(speaker: speaker, session: session)
                        Text("\(Timecode.short(talk[speaker.id] ?? 0)) \(Int(((talk[speaker.id] ?? 0) / total * 100).rounded()))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.well)
                            Capsule().fill(Palette.speaker(session.color(of: speaker.id)))
                                .frame(width: geo.size.width * CGFloat((talk[speaker.id] ?? 0) / total))
                        }
                    }
                    .frame(height: 4)
                    .padding(.leading, 18)
                }
            }
        }
    }

    var mergeMenu: some View {
        Menu("Merge…") {
            ForEach(session.project.speakers) { from in
                Menu("Merge \(from.displayName) into") {
                    ForEach(session.project.speakers.filter { $0.id != from.id }) { into in
                        Button(into.displayName) { session.merge(from.id, into: into.id) }
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 12))
        .disabled(session.project.speakers.count < 2)
    }
}

/// Commits the name when editing ends, so typing doesn't create an undo step per key.
struct SpeakerNameField: View {
    let speaker: Speaker
    let session: ProjectSession
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(speaker.isMe ? "Me" : "Speaker \(speaker.id + 1)", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, weight: .medium))
            .focused($focused)
            .onAppear { text = speaker.name }
            .onChange(of: speaker.name) { _, v in if !focused { text = v } }
            .onSubmit { session.rename(speaker: speaker.id, to: text) }
            .onChange(of: focused) { _, f in if !f { session.rename(speaker: speaker.id, to: text) } }
            .accessibilityLabel("Name for speaker \(speaker.id + 1)")
    }
}

struct MarksSection: View {
    @Bindable var session: ProjectSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Marks", trailing: AnyView(
                Button("Export all…") { session.showExport = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .disabled(session.project.marks.isEmpty)))
            if session.project.marks.isEmpty {
                Text("Select a section and press M to keep it as a named mark.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(session.project.marks) { mark in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.mark).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        MarkNameField(mark: mark, session: session)
                        Button("\(Timecode.short(mark.start)) – \(Timecode.short(mark.end)) · \(Timecode.short(mark.duration))") {
                            session.select(mark.start...mark.end)
                            session.player.seek(to: mark.start)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { session.player.play(from: mark.start, to: mark.end) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.borderless).help("Play mark")
                    Button { session.copy(mark: mark) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy mark text")
                    Button { session.remove(mark: mark.id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("Remove mark")
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct MarkNameField: View {
    let mark: Mark
    let session: ProjectSession
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Mark", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary)
            .focused($focused)
            .onAppear { text = mark.name }
            .onSubmit { session.rename(mark: mark.id, to: text) }
            .onChange(of: focused) { _, f in if !f { session.rename(mark: mark.id, to: text) } }
    }
}

struct SelectionSection: View {
    @Bindable var session: ProjectSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Selection")
            if let sel = session.selection {
                let range = Merge.indices(of: session.project.words, from: sel.lowerBound, to: sel.upperBound)
                let words = session.project.words[range].filter { !$0.isFiller }.count
                let paragraphs = session.paragraphs.filter { $0.end > sel.lowerBound && $0.start < sel.upperBound }.count
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(Timecode.precise(sel.lowerBound))  →  \(Timecode.precise(sel.upperBound))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Text("\(Timecode.precise(sel.upperBound - sel.lowerBound)) long · \(paragraphs) \(paragraphs == 1 ? "paragraph" : "paragraphs") · \(words) words")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button("Copy text") { session.copySelection() }.buttonStyle(.borderedProminent)
                        Button("Save as mark") { session.addMark() }
                        Button("Clear") { session.selection = nil }.buttonStyle(.borderless)
                    }
                    .controlSize(.small)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            } else {
                Text("Drag across the waveform, press I and O at the playhead, or shift-click lines to select. Cuts snap to whole words.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct InfoSection: View {
    let session: ProjectSession

    var body: some View {
        let p = session.project
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Processed on this Mac")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("Language", "\(languageName(p.language))" + (p.languageConfidence.map { " · \(Int($0 * 100))%" } ?? ""))
                row("Words", "\(p.words.filter { !$0.isFiller }.count) · \(p.transcriber == "apple" ? "Apple" : "Voz")")
                row("Speakers", "\(p.speakers.count) · Who")
                row("Fillers", "\(p.words.filter(\.isFiller).count) · Uhm")
            }
            .font(.system(size: 12))
        }
    }

    func row(_ a: String, _ b: String) -> some View {
        GridRow {
            Text(a).foregroundStyle(.secondary)
            Text(b)
        }
    }
}
