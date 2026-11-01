import MurmurCore
import SwiftUI

/// The transcript, one paragraph per row. Follows playback until the person scrolls away; a button
/// brings it back to the current line.
struct TranscriptList: View {
    let session: ProjectSession
    @AppStorage(AppSettings.speakerScheme) private var schemeName = SpeakerScheme.vivid.rawValue
    @AppStorage(AppSettings.redactionStyle) private var redactionStyle = RedactionStyle.labels.rawValue
    @State private var follow = true
    @State private var editing: Paragraph?
    @State private var search = ""
    @State private var renaming: Int?
    @State private var newName = ""

    private var scheme: SpeakerScheme { SpeakerScheme(rawValue: schemeName) ?? .vivid }

    private var visible: [Paragraph] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return session.paragraphs }
        return session.paragraphs.filter {
            Merge.join(session.project.words[$0.range]).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let active = session.activeParagraph?.id
        ScrollViewReader { proxy in
            List(visible) { paragraph in
                row(paragraph, isActive: paragraph.id == active)
                    .id(paragraph.id)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(paragraph.id == active ? Color.accentColor.opacity(0.08) : Color.clear)
            }
            .listStyle(.plain)
            .searchable(text: $search, placement: .toolbar, prompt: "Find in transcript")
            .searchToolbarBehavior(.minimize)
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in
                if session.player.isPlaying { follow = false }
            })
            .onChange(of: active) { _, id in
                guard follow, session.player.isPlaying, let id else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: session.jumpRequest) {
                follow = true
                if let id = session.activeParagraph?.id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
            .overlay(alignment: .bottomTrailing) {
                if !follow && session.player.isPlaying {
                    Button {
                        follow = true
                        if let id = session.activeParagraph?.id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    } label: {
                        Label("Current Line", systemImage: "arrow.down.to.line").font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.glass)
                    .padding(16)
                    .transition(.opacity)
                }
            }
        }
        .sheet(item: $editing) { paragraph in
            EditParagraphView(session: session, paragraph: paragraph)
        }
        .alert("Rename \(renaming.map { session.project.name(of: $0) } ?? "")", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let id = renaming { session.rename(speaker: id, to: newName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Used everywhere this voice speaks, and in exports.")
        }
    }

    private func row(_ paragraph: Paragraph, isActive: Bool) -> some View {
        let speaker = paragraph.speaker
        let color = scheme.color(session.color(of: speaker))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(session.project.name(of: speaker))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .onTapGesture { renaming = speaker; newName = session.project.speaker(speaker)?.name ?? "" }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Renames the speaker")
                Text(Timecode.short(paragraph.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(text(of: paragraph, isActive: isActive))
                .font(.body)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            session.player.seek(to: paragraph.start + 0.01)
            follow = true
            if !session.player.isPlaying { session.player.play() }
        }
        .contextMenu { menu(paragraph) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays from here")
        .accessibilityAction(named: "Edit text") { editing = paragraph }
    }

    /// The paragraph's words, hidden details replaced, fillers dimmed, the current word in the accent color.
    private func text(of paragraph: Paragraph, isActive: Bool) -> AttributedString {
        let words = session.project.words
        let hidden = session.hiddenSpans.filter { $0.end > paragraph.start && $0.start < paragraph.end }
        let style = RedactionStyle(rawValue: redactionStyle) ?? .labels
        let now = session.player.time
        var out = AttributedString()
        var lastSpan: RedactedSpan?
        var first = true
        for i in paragraph.range {
            let word = words[i]
            if word.isFiller && !session.project.settings.showFillers { continue }
            if let span = Redactor.span(for: word, in: hidden) {
                if span == lastSpan { continue }
                lastSpan = span
                if !first { out += AttributedString(" ") }
                var piece = AttributedString(Redactor.replacement(for: span, style: style))
                piece.foregroundColor = .secondary
                piece.backgroundColor = Color.secondary.opacity(0.15)
                out += piece
                first = false
                continue
            }
            if !first, !(word.text.first.map(Merge.isUnspaced) ?? false) { out += AttributedString(" ") }
            var piece = AttributedString(word.text)
            if word.isFiller {
                piece.foregroundColor = .secondary
                piece.inlinePresentationIntent = .emphasized
            }
            if isActive {
                // As in the Mac app: while playing, words still to come are secondary and the current one
                // is highlighted. Colour only, so the line never reflows.
                if word.start > now, session.player.isPlaying { piece.foregroundColor = .secondary }
                if word.start <= now, now < max(word.end, word.start + 0.15) {
                    piece.backgroundColor = Color.accentColor.opacity(0.28)
                }
            }
            out += piece
            first = false
        }
        return out
    }

    @ViewBuilder
    private func menu(_ paragraph: Paragraph) -> some View {
        Button("Play from Here", systemImage: "play") {
            session.player.seek(to: paragraph.start + 0.01)
            session.player.play()
        }
        Button("Edit Text", systemImage: "pencil") { editing = paragraph }
        Button("Rename \(session.project.name(of: paragraph.speaker))…", systemImage: "character.cursor.ibeam") {
            renaming = paragraph.speaker
            newName = session.project.speaker(paragraph.speaker)?.name ?? ""
        }
        Menu("Change Speaker", systemImage: "person.crop.circle") {
            ForEach(session.project.speakers.filter { $0.id != paragraph.speaker }) { speaker in
                Button(session.project.name(of: speaker.id)) { session.reassign(paragraph, to: speaker.id) }
            }
            Divider()
            Button("New Speaker", systemImage: "person.badge.plus") { session.newSpeaker(from: paragraph) }
        }
        Button("Mark Paragraph", systemImage: "bookmark") {
            session.select(paragraph.start...paragraph.end)
            session.addMark()
        }
        Button("Copy", systemImage: "doc.on.doc") {
            session.copy(sections: [TranscriptSection(start: paragraph.start, end: paragraph.end)], what: "paragraph")
        }
    }
}

extension Paragraph: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(range.lowerBound); hasher.combine(range.upperBound) }
}

/// Fixing a paragraph's words. Edited words are re-timed against the audio.
struct EditParagraphView: View {
    let session: ProjectSession
    let paragraph: Paragraph
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .focused($focused)
                .padding(.horizontal, 12)
                .navigationTitle("\(session.project.name(of: paragraph.speaker)) at \(Timecode.short(paragraph.start))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            session.replaceText(of: paragraph, with: text)
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Play Paragraph", systemImage: "play") { session.player.play(from: paragraph.start, to: paragraph.end) }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            text = Merge.join(session.project.words[paragraph.range])
            focused = true
        }
    }
}

/// While the first transcription runs: each step with its progress.
struct ProcessingView: View {
    let session: ProjectSession

    var body: some View {
        List {
            Section {
                ForEach(session.steps) { step in
                    HStack(spacing: 12) {
                        icon(step).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).foregroundStyle(step.state == .pending ? .secondary : .primary)
                            Text(step.detail).font(.caption).foregroundStyle(.secondary)
                            if step.state == .running, let f = step.fraction {
                                ProgressView(value: f).padding(.top, 2)
                            }
                        }
                        Spacer()
                        if let s = step.seconds {
                            Text(s < 10 ? String(format: "%.1f s", s) : Timecode.short(s))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text("Everything runs on this device. You can leave Murmur; iOS shows the progress and lets it finish.")
            }
        }
    }

    @ViewBuilder
    private func icon(_ step: PipelineStep) -> some View {
        switch step.state {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

/// While a project that already has words is transcribed again.
struct ProcessingBanner: View {
    let session: ProjectSession

    var body: some View {
        let running = session.steps.first { $0.state == .running }
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(running?.title ?? "Transcribing").font(.footnote.weight(.medium))
            Spacer()
            Text("\(Int(ProjectView.fraction(session.steps) * 100))%").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}
