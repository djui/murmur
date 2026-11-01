import MurmurCore
import SwiftUI

/// The transcript, one paragraph per row. Follows playback until the person scrolls away; a button
/// brings it back to the current line.
struct TranscriptList: View {
    let session: ProjectSession
    /// Paragraphs picked for a mark; nil when not picking.
    @Binding var picking: Set<Int>?
    @AppStorage(AppSettings.speakerScheme) private var schemeName = SpeakerScheme.vivid.rawValue
    @AppStorage(AppSettings.redactionStyle) private var redactionStyle = RedactionStyle.labels.rawValue
    @State private var follow = true
    @State private var editing: Paragraph?
    @State private var giving: Paragraph?
    @State private var search = ""
    /// Set by the project's Search button.
    @Binding var searching: Bool
    @FocusState private var searchFocused: Bool
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
            // Search lives in the top bar, so the bottom of the screen stays for playback.
            .safeAreaInset(edge: .top, spacing: 0) {
                if searching {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find in transcript", text: $search)
                            .focused($searchFocused)
                            .submitLabel(.search)
                        if !search.isEmpty {
                            Text("\(visible.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .accessibilityLabel("\(visible.count) paragraphs match")
                        }
                        Button("Done") { search = ""; searching = false }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.fill.quaternary, in: .capsule)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(.systemBackground))
                    .onAppear { searchFocused = true }
                    .onDisappear { search = "" }
                }
            }
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
        .sheet(item: $giving) { paragraph in
            GiveWordsView(session: session, paragraph: paragraph)
        }
        #if DEBUG
        // `-give <paragraph>` opens Give Words, for screenshots.
        .onAppear {
            if let i = Int(UserDefaults.standard.string(forKey: "give") ?? ""), session.paragraphs.indices.contains(i) {
                giving = session.paragraphs[i]
            }
        }
        #endif
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
        let isPicked = picking?.contains(paragraph.id) == true
        return HStack(alignment: .top, spacing: 12) {
        if picking != nil {
            Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isPicked ? Color.mark : Color.secondary)
                .padding(.top, 2)
                .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 4) {
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
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if var picked = picking {
                if picked.contains(paragraph.id) { picked.remove(paragraph.id) } else { picked.insert(paragraph.id) }
                picking = picked
                return
            }
            session.player.seek(to: paragraph.start + 0.01)
            follow = true
            if !session.player.isPlaying { session.player.play() }
        }
        .contextMenu { if picking == nil { menu(paragraph) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityHint(picking == nil ? "Plays from here" : "Picks the paragraph for a mark")
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
        Button("Give Words to…", systemImage: "arrow.up.and.down.text.horizontal") { giving = paragraph }
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
        Button("Mark Several Paragraphs…", systemImage: "checklist") { picking = [paragraph.id] }
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
    @State private var giving = false
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
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Play Paragraph", systemImage: "play") { session.player.play(from: paragraph.start, to: paragraph.end) }
                        Spacer()
                        // Where people are when they notice words belong to someone else.
                        Button("Give Words to…", systemImage: "arrow.up.and.down.text.horizontal") {
                            session.replaceText(of: paragraph, with: text)
                            giving = true
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
        }
        .sheet(isPresented: $giving, onDismiss: {
            // Words were given away: this paragraph is no longer what the editor shows.
            let words = session.project.words
            if !words.indices.contains(paragraph.range.upperBound - 1)
                || words[paragraph.range].contains(where: { $0.speaker != paragraph.speaker }) { dismiss() }
        }) {
            if let current = session.paragraphs.first(where: { $0.range.contains(paragraph.range.lowerBound) }) {
                GiveWordsView(session: session, paragraph: current)
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
            Text("\(Int(OpenProjects.fraction(session.steps) * 100))%").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

/// Hands part of a paragraph to another speaker, as the Mac app's Give-to bar does: tap the first and
/// last word, then pick who said them. The speaker on the line before or after comes first, so words
/// at either end join that line.
struct GiveWordsView: View {
    let session: ProjectSession
    let paragraph: Paragraph
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.speakerScheme) private var schemeName = SpeakerScheme.vivid.rawValue
    /// Absolute word indices.
    @State private var selected: Range<Int>?

    private var scheme: SpeakerScheme { SpeakerScheme(rawValue: schemeName) ?? .vivid }

    private func neighbour(_ offset: Int) -> Int? {
        guard let i = session.paragraphs.firstIndex(where: { $0.id == paragraph.id }),
              session.paragraphs.indices.contains(i + offset) else { return nil }
        return session.paragraphs[i + offset].speaker
    }

    var body: some View {
        let words = session.project.words
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tap the first and last word someone else said.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    FlowLayout(spacing: 0, lineSpacing: 4) {
                        ForEach(Array(paragraph.range), id: \.self) { i in
                            let on = selected?.contains(i) == true
                            Text(words[i].text)
                                .font(.body)
                                .padding(.horizontal, 3).padding(.vertical, 2)
                                .background(on ? Color.accentColor.opacity(0.28) : Color.clear, in: .rect(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture { tap(i) }
                                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("From the Start") { if let s = selected { selected = paragraph.range.lowerBound..<s.upperBound } else { selected = paragraph.range.lowerBound..<paragraph.range.lowerBound + 1 } }
                        Button("To the End") { if let s = selected { selected = s.lowerBound..<paragraph.range.upperBound } else { selected = paragraph.range.upperBound - 1..<paragraph.range.upperBound } }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { if let selected { giveBar(selected) } }
            .navigationTitle("\(session.project.name(of: paragraph.speaker)) at \(Timecode.short(paragraph.start))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Play", systemImage: "play") {
                        let r = selected ?? paragraph.range
                        session.player.play(from: words[r.lowerBound].start, to: words[r.upperBound - 1].end)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        #if DEBUG
        // `-giveWords <first>,<count>`: preselect words, for screenshots.
        .onAppear {
            let p = (UserDefaults.standard.string(forKey: "giveWords") ?? "").split(separator: ",").compactMap { Int($0) }
            if p.count == 2 {
                let lo = min(paragraph.range.upperBound - 1, paragraph.range.lowerBound + p[0])
                selected = lo..<min(paragraph.range.upperBound, lo + p[1])
            }
        }
        #endif
    }

    private func tap(_ i: Int) {
        guard let s = selected else { selected = i..<i + 1; return }
        if s == i..<i + 1 { selected = nil; return }
        selected = min(s.lowerBound, i)..<max(s.upperBound, i + 1)
    }

    private func giveBar(_ range: Range<Int>) -> some View {
        let before = neighbour(-1), after = neighbour(1)
        let suggested = Editing.suggestedSpeakers(for: range, in: paragraph, before: before, after: after)
        let others = session.project.speakers.map(\.id).filter { $0 != paragraph.speaker && !suggested.contains($0) }
        let all = range == paragraph.range
        return VStack(alignment: .leading, spacing: 8) {
            Text(all ? "Give this paragraph to" : "Give \(range.count) \(range.count == 1 ? "word" : "words") to")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggested + others, id: \.self) { id in
                        let joins = suggested.contains(id)
                        Button {
                            session.reassign(words: range, to: id)
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                if joins {
                                    Image(systemName: id == before && range.lowerBound == paragraph.range.lowerBound ? "arrow.up" : "arrow.down")
                                }
                                Circle().fill(scheme.color(session.color(of: id))).frame(width: 8, height: 8)
                                Text(session.project.name(of: id))
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(joins ? .accentColor : .secondary)
                        .accessibilityHint(joins ? "Joins the line \(id == before && range.lowerBound == paragraph.range.lowerBound ? "before" : "after")" : "")
                    }
                    Button { session.newSpeaker(words: range); dismiss() } label: { Label("New Speaker", systemImage: "plus") }
                        .buttonStyle(.bordered).tint(.secondary)
                }
            }
        }
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
    }
}

/// Lays words out like text: left to right, wrapping at the edge.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + lineSpacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + lineSpacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
