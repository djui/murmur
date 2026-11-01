import MurmurCore
import SwiftUI

/// iPhone playback: a glass bar at the bottom with a speaker-coloured scrub strip and the transport.
/// Swipe it up, or tap the grabber, for the full score with a lane per speaker.
struct PlaybackDock: View {
    let session: ProjectSession
    @AppStorage("scoreExpanded") private var expanded = false

    var body: some View {
        VStack(spacing: 6) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide speaker lanes" : "Show speaker lanes")
            if expanded {
                // The score keeps an opaque ground inside the glass (DESIGN.md, Opaque Score).
                TimelineStrip(session: session)
                    .frame(height: 96 + CGFloat(min(session.project.speakers.count, 6)) * 13)
                    .padding(8)
                    .background(Color(.systemBackground), in: .rect(cornerRadius: 18))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                MiniScrub(session: session)
                    .frame(height: 30)
            }
            PlayerBar(session: session)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 2)
        .glassEffect(in: .rect(cornerRadius: 28))
        .padding(.horizontal, 10)
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height < -30, !expanded { withAnimation(.snappy) { expanded = true } }
            if value.translation.height > 30, expanded { withAnimation(.snappy) { expanded = false } }
        })
    }
}

/// The whole file as one thin strip: who speaks when, marks, the playhead. Drag to scrub.
struct MiniScrub: View {
    let session: ProjectSession
    @AppStorage(AppSettings.speakerScheme) private var schemeName = SpeakerScheme.vivid.rawValue

    var body: some View {
        let scheme = SpeakerScheme(rawValue: schemeName) ?? .vivid
        GeometryReader { geo in
            TimelineView(.animation(paused: !session.player.isPlaying)) { _ in
                // Read here, not in the Canvas closure, so the playhead moves while playing.
                let time = session.player.displayTime
                Canvas { ctx, size in draw(&ctx, size: size, time: time, scheme: scheme) }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let f = max(0, min(1, (v.location.x - 4) / max(1, geo.size.width - 8)))
                session.player.seek(to: Double(f) * session.project.duration)
            })
            .accessibilityElement()
            .accessibilityLabel("Timeline")
            .accessibilityValue("\(Timecode.short(session.player.time)) of \(Timecode.short(session.project.duration))")
            .accessibilityAdjustableAction { direction in
                session.player.skip(by: direction == .increment ? 5 : -5)
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, time: Double, scheme: SpeakerScheme) {
        ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(Color(.systemBackground)))
        let peaks = session.peaks, bins = session.speakerBins
        let duration = max(0.1, session.project.duration)
        let width = size.width - 8
        let x = { (t: Double) -> CGFloat in 4 + CGFloat(t / duration) * width }
        for mark in session.project.marks {
            let r = CGRect(x: x(mark.start), y: 0, width: max(2, x(mark.end) - x(mark.start)), height: size.height)
            ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(.mark.opacity(0.18)))
        }
        if !peaks.isEmpty {
            var column: CGFloat = 4
            while column < size.width - 4 {
                let lo = Int(Double((column - 4) / width) * Double(peaks.count))
                let hi = min(peaks.count, Int(Double((column - 1) / width) * Double(peaks.count)) + 1)
                if lo < hi {
                    let peak = peaks[lo..<hi].max() ?? 0
                    let mid = (lo + hi) / 2
                    let speaker = bins.indices.contains(mid) ? Int(bins[mid]) : -1
                    let h = max(2, CGFloat(peak) * (size.height - 8))
                    let played = Double(column - 4) / Double(width) * duration < time
                    let color = speaker < 0 ? Color.secondary.opacity(0.35)
                        : scheme.color(session.color(of: speaker)).opacity(played ? 1 : 0.4)
                    ctx.fill(Path(roundedRect: CGRect(x: column, y: (size.height - h) / 2, width: 2, height: h), cornerRadius: 1),
                             with: .color(color))
                }
                column += 3
            }
        }
        if let pending = session.pendingStart {
            let lo = min(pending, time), hi = max(pending, time)
            ctx.fill(Path(CGRect(x: x(lo), y: 0, width: max(2, x(hi) - x(lo)), height: size.height)), with: .color(.mark.opacity(0.25)))
        }
        ctx.fill(Path(roundedRect: CGRect(x: x(time) - 1, y: 1, width: 2, height: size.height - 2), cornerRadius: 1), with: .color(.primary))
    }
}

/// While paragraphs are picked for a mark: how many, the time they span, and Mark.
struct PickBar: View {
    let session: ProjectSession
    let picked: Set<Int>
    let done: () -> Void

    /// Picked paragraphs that follow one another make one mark; a gap starts another.
    private var runs: [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        var current: ClosedRange<Double>?
        for p in session.paragraphs {
            if picked.contains(p.id) {
                current = current.map { $0.lowerBound...p.end } ?? p.start...p.end
            } else if let c = current {
                out.append(c)
                current = nil
            }
        }
        if let current { out.append(current) }
        return out
    }

    var body: some View {
        let runs = self.runs
        HStack(spacing: 12) {
            Button("Cancel", action: done)
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text(picked.isEmpty ? "Pick paragraphs" : "\(picked.count) \(picked.count == 1 ? "paragraph" : "paragraphs")")
                    .font(.subheadline.weight(.medium))
                if let first = runs.first, let last = runs.last {
                    Text(runs.count == 1 ? "\(Timecode.short(first.lowerBound)) – \(Timecode.short(last.upperBound))" : "\(runs.count) marks")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                for run in runs {
                    let name = session.markName(for: run)
                    session.update("Add Mark") { $0.marks.append(Mark(name: name, start: run.lowerBound, end: run.upperBound)) }
                }
                session.flash(runs.count == 1 ? "Marked “\(session.markName(for: runs[0]))”" : "Added \(runs.count) marks")
                done()
            } label: {
                Label("Mark", systemImage: "bookmark.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.mark)
            .disabled(picked.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

/// iPad: speakers with their share of the talking, marks, and the project's switches beside the transcript.
struct InspectorView: View {
    let session: ProjectSession
    @Binding var sheet: ProjectView.Sheet?
    @AppStorage(AppSettings.speakerScheme) private var schemeName = SpeakerScheme.vivid.rawValue
    @State private var renaming: Int?
    @State private var newName = ""

    var body: some View {
        let project = session.project
        let talk = project.talkTime
        let total = max(1, talk.values.reduce(0, +))
        let scheme = SpeakerScheme(rawValue: schemeName) ?? .vivid
        List {
            if let summary = project.summary {
                Section("Summary") { Text(summary).font(.subheadline) }
            }
            Section("Speakers") {
                ForEach(project.speakers) { s in
                    let color = scheme.color(session.color(of: s.id))
                    let share = (talk[s.id] ?? 0) / total
                    Button {
                        renaming = s.id
                        newName = s.name
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle().fill(color).frame(width: 10, height: 10)
                                Text(project.name(of: s.id)).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Spacer()
                                Text("\(Int((share * 100).rounded())) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            GeometryReader { g in
                                Capsule().fill(.quaternary)
                                    .overlay(alignment: .leading) { Capsule().fill(color).frame(width: g.size.width * share) }
                            }
                            .frame(height: 4)
                        }
                    }
                    .accessibilityHint("Renames the speaker")
                    .contextMenu {
                        Menu("Merge Into", systemImage: "arrow.triangle.merge") {
                            ForEach(project.speakers.filter { $0.id != s.id }) { other in
                                Button(project.name(of: other.id)) { session.merge(s.id, into: other.id) }
                            }
                        }
                    }
                }
            }
            Section("Marks") {
                ForEach(project.marks) { m in
                    Button { session.player.play(from: m.start, to: m.end) } label: {
                        HStack {
                            RoundedRectangle(cornerRadius: 2).fill(Color.mark).frame(width: 10, height: 10)
                            Text(m.name).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            Text(Timecode.short(m.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { session.remove(mark: m.id) } }
                }
                if project.marks.isEmpty {
                    Text("Tap the bookmark at the start and end of a section, or pick paragraphs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Hide Personal Details", isOn: Binding(get: { session.isRedacting }, set: { session.setRedact($0) }))
                    .disabled(session.isFindingDetails)
                Toggle("Enhance Audio", isOn: Binding(get: { project.settings.enhance }, set: { session.setEnhance($0) }))
                    .disabled(session.isProcessing)
                if project.summary != nil || project.language != nil {
                    Button("Details…") { sheet = .details }
                }
            }
        }
        .listStyle(.insetGrouped)
        .alert("Rename \(renaming.map { project.name(of: $0) } ?? "")", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let id = renaming { session.rename(speaker: id, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
