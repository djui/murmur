import MurmurCore
import SwiftUI

/// Transport controls, the overview strip, the speaker-colored waveform, speaker lanes and marks.
struct TimelinePanel: View {
    @Bindable var session: ProjectSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransportBar(session: session)
            TimelineTracks(session: session)
            Text("Click to jump · drag to select · M turns the selection into a mark · overlapping speech shows on both lanes")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, TimelineTracks.labelWidth + 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct TransportBar: View {
    @Bindable var session: ProjectSession

    var body: some View {
        HStack(spacing: 10) {
            Button { session.player.skip(by: -5) } label: { Image(systemName: "gobackward.5") }
                .buttonStyle(PillStyle())
                .help("Back 5 seconds (←)")
            Button { session.player.toggle() } label: {
                Image(systemName: session.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .help("Play or pause (Space)")
            .accessibilityLabel(session.player.isPlaying ? "Pause" : "Play")
            Button { session.player.skip(by: 5) } label: { Image(systemName: "goforward.5") }
                .buttonStyle(PillStyle())
                .help("Forward 5 seconds (→)")
            HStack(spacing: 0) {
                Text(Timecode.precise(session.player.time)).fontWeight(.medium)
                Text(" / " + Timecode.precise(session.project.duration)).foregroundStyle(.secondary)
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(.leading, 4)
            Spacer()
            Button { session.markIn() } label: { Text("In ") + Text("I").foregroundStyle(.secondary) }
                .buttonStyle(PillStyle())
                .help("Start the selection at the playhead (I)")
            Button { session.markOut() } label: { Text("Out ") + Text("O").foregroundStyle(.secondary) }
                .buttonStyle(PillStyle())
                .help("End the selection at the playhead (O)")
            Button { session.addMark() } label: {
                Label { Text("Add mark ") + Text("M").foregroundStyle(.secondary) } icon: {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.mark).frame(width: 9, height: 9)
                }
            }
            .buttonStyle(PillStyle())
            .help("Save the selection as a named mark (M)")
            Divider().frame(height: 18)
            Button { session.zoom = max(1, session.zoom / 2) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(PillStyle())
                .disabled(session.zoom <= 1)
                .accessibilityLabel("Zoom out")
            Text("\(Int(session.zoom))×").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 30)
            Button { session.zoom = min(64, session.zoom * 2) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(PillStyle())
                .accessibilityLabel("Zoom in")
        }
    }
}

struct TimelineTracks: View {
    @Bindable var session: ProjectSession
    @State private var dragStart: CGFloat?
    @State private var dragView: ClosedRange<Double>?

    static let labelWidth: CGFloat = 104
    static let marksHeight: CGFloat = 20
    static let waveHeight: CGFloat = 110
    static let laneHeight: CGFloat = 22
    static let rulerHeight: CGFloat = 20

    var speakers: [Speaker] { session.project.speakers }
    var tracksHeight: CGFloat {
        Self.marksHeight + Self.waveHeight + CGFloat(speakers.count) * Self.laneHeight + Self.rulerHeight
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                label("Overview").frame(height: 26)
                Spacer().frame(height: 10)
                label("Marks").frame(height: Self.marksHeight)
                label("Waveform").frame(height: Self.waveHeight)
                ForEach(speakers) { s in
                    HStack(spacing: 6) {
                        Circle().fill(Palette.speaker(session.color(of: s.id))).frame(width: 9, height: 9)
                        Text(s.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .frame(height: Self.laneHeight, alignment: .leading)
                }
            }
            .frame(width: Self.labelWidth, alignment: .leading)

            VStack(spacing: 10) {
                OverviewStrip(session: session).frame(height: 26)
                GeometryReader { geo in
                    let view = dragView ?? viewRange
                    Canvas { ctx, size in draw(ctx, size: size, view: view) }
                        .contentShape(Rectangle())
                        .gesture(dragGesture(width: geo.size.width))
                }
                .frame(height: tracksHeight)
                .accessibilityElement()
                .accessibilityLabel("Timeline")
                .accessibilityValue("Playhead at \(Timecode.short(session.player.time))")
            }
        }
    }

    func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxHeight: .infinity, alignment: .center)
    }

    var viewRange: ClosedRange<Double> {
        let duration = max(session.project.duration, 0.1)
        let span = duration / session.zoom
        let v0 = min(max(session.player.time - span / 2, 0), duration - span)
        return v0...(v0 + span)
    }

    func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation.x
                    dragView = viewRange
                }
                guard let view = dragView, abs(value.translation.width) > 4 else { return }
                let a = time(at: value.startLocation.x, width: width, view: view)
                let b = time(at: value.location.x, width: width, view: view)
                session.select(min(a, b)...max(a, b))
            }
            .onEnded { value in
                let view = dragView ?? viewRange
                if abs(value.translation.width) <= 4 {
                    session.player.seek(to: time(at: value.location.x, width: width, view: view))
                }
                dragStart = nil
                dragView = nil
            }
    }

    func time(at x: CGFloat, width: CGFloat, view: ClosedRange<Double>) -> Double {
        let f = Double(max(0, min(width, x)) / max(1, width))
        return view.lowerBound + f * (view.upperBound - view.lowerBound)
    }

    func draw(_ ctx: GraphicsContext, size: CGSize, view: ClosedRange<Double>) {
        let span = max(0.001, view.upperBound - view.lowerBound)
        func x(_ t: Double) -> CGFloat { CGFloat((t - view.lowerBound) / span) * size.width }
        let t = session.player.time
        let peaks = session.peaks
        let bins = session.speakerBins

        // Marks lane
        for mark in session.project.marks where mark.end > view.lowerBound && mark.start < view.upperBound {
            let rect = CGRect(x: x(max(mark.start, view.lowerBound)), y: 1,
                              width: max(2, x(min(mark.end, view.upperBound)) - x(max(mark.start, view.lowerBound))),
                              height: Self.marksHeight - 4)
            let path = Path(roundedRect: rect, cornerRadius: 4)
            ctx.fill(path, with: .color(Palette.mark.opacity(0.18)))
            ctx.stroke(path, with: .color(Palette.mark), lineWidth: 1)
            if rect.width > 30 {
                var c = ctx
                c.clip(to: Path(rect.insetBy(dx: 5, dy: 0)))
                c.draw(Text(mark.name).font(.system(size: 10, weight: .semibold)).foregroundColor(Palette.markText),
                       at: CGPoint(x: rect.minX + 6, y: rect.midY), anchor: .leading)
            }
        }

        // Waveform
        let waveTop = Self.marksHeight
        let barCount = max(1, Int(size.width / 4))
        let barWidth = size.width / CGFloat(barCount)
        let mid = waveTop + Self.waveHeight / 2
        for i in 0..<barCount {
            let a = view.lowerBound + Double(i) / Double(barCount) * span
            let b = view.lowerBound + Double(i + 1) / Double(barCount) * span
            let amp = peaks.isEmpty ? 0.04 : CGFloat(Peaks.peak(in: peaks, from: a, to: b))
            let h = max(3, amp * (Self.waveHeight - 6))
            let bin = Int((a + b) / 2 * Double(Peaks.binsPerSecond))
            let speaker = bins.indices.contains(bin) ? Int(bins[bin]) : -1
            let color = speaker < 0 ? Palette.silence : Palette.speaker(session.color(of: speaker))
            let rect = CGRect(x: CGFloat(i) * barWidth + 0.5, y: mid - h / 2, width: max(1, barWidth - 2), height: h)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(color.opacity((a + b) / 2 <= t ? 1 : 0.4)))
        }

        // Speaker lanes
        var laneTop = waveTop + Self.waveHeight
        for speaker in speakers {
            let track = CGRect(x: 0, y: laneTop + 4, width: size.width, height: Self.laneHeight - 8)
            ctx.fill(Path(roundedRect: track, cornerRadius: 4), with: .color(Palette.well))
            let color = Palette.speaker(session.color(of: speaker.id))
            for p in session.paragraphs where p.speaker == speaker.id && p.end > view.lowerBound && p.start < view.upperBound {
                let r = CGRect(x: x(max(p.start, view.lowerBound)), y: track.minY + 2,
                               width: max(1.5, x(min(p.end, view.upperBound)) - x(max(p.start, view.lowerBound))),
                               height: track.height - 4)
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(color))
            }
            laneTop += Self.laneHeight
        }

        // Ruler
        let step: Double = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800].first { span / $0 <= 14 } ?? 3600
        var tick = (view.lowerBound / step).rounded(.up) * step
        while tick <= view.upperBound {
            let px = x(tick)
            if px < size.width - 40 {
                ctx.fill(Path(CGRect(x: px, y: laneTop + 2, width: 1, height: 12)), with: .color(Color(nsColor: .separatorColor)))
                ctx.draw(Text(Timecode.short(tick)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary),
                         at: CGPoint(x: px + 4, y: laneTop + 8), anchor: .leading)
            }
            tick += step
        }

        // Selection
        let contentBottom = laneTop
        if let sel = session.selection, sel.upperBound > view.lowerBound, sel.lowerBound < view.upperBound {
            let lo = x(max(sel.lowerBound, view.lowerBound)), hi = x(min(sel.upperBound, view.upperBound))
            let rect = CGRect(x: lo, y: 0, width: max(2, hi - lo), height: contentBottom)
            ctx.fill(Path(rect), with: .color(Color.accentColor.opacity(0.12)))
            ctx.fill(Path(CGRect(x: lo, y: 0, width: 2, height: contentBottom)), with: .color(.accentColor))
            ctx.fill(Path(CGRect(x: hi - 2, y: 0, width: 2, height: contentBottom)), with: .color(.accentColor))
        }

        // Playhead
        if t >= view.lowerBound && t <= view.upperBound {
            let px = x(t)
            ctx.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: contentBottom)), with: .color(.primary))
            ctx.fill(Path(ellipseIn: CGRect(x: px - 5, y: -1, width: 10, height: 10)), with: .color(.primary))
        }
    }
}

/// The whole file at a glance; click or drag to jump.
struct OverviewStrip: View {
    @Bindable var session: ProjectSession

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let duration = max(session.project.duration, 0.1)
                let count = max(1, Int(size.width / 3))
                let w = size.width / CGFloat(count)
                let bins = session.speakerBins
                for i in 0..<count {
                    let a = Double(i) / Double(count) * duration, b = Double(i + 1) / Double(count) * duration
                    let amp = session.peaks.isEmpty ? 0.1 : CGFloat(Peaks.peak(in: session.peaks, from: a, to: b))
                    let h = max(2, amp * (size.height - 6))
                    let bin = Int((a + b) / 2 * Double(Peaks.binsPerSecond))
                    let s = bins.indices.contains(bin) ? Int(bins[bin]) : -1
                    let color = s < 0 ? Palette.silence : Palette.speaker(session.color(of: s))
                    ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: (size.height - h) / 2, width: max(1, w - 1), height: h)),
                             with: .color(color.opacity(0.55)))
                }
                if session.zoom > 1 {
                    let span = duration / session.zoom
                    let v0 = min(max(session.player.time - span / 2, 0), duration - span)
                    let rect = CGRect(x: CGFloat(v0 / duration) * size.width, y: 0,
                                      width: CGFloat(span / duration) * size.width, height: size.height)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color.accentColor.opacity(0.1)))
                    ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 5), with: .color(.accentColor), lineWidth: 1.5)
                }
                let px = CGFloat(session.player.time / duration) * size.width
                ctx.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: size.height)), with: .color(.primary))
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.well))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let f = Double(max(0, min(geo.size.width, v.location.x)) / max(1, geo.size.width))
                session.player.seek(to: f * session.project.duration)
            })
        }
        .accessibilityLabel("Overview of the whole file")
    }
}
