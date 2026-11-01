import MurmurCore
import SwiftUI

/// The speaker-colored waveform with one lane per speaker. Tap to jump, drag to scrub, pinch to zoom;
/// zoomed in, the playhead stays in the middle and the audio moves under it.
struct TimelineStrip: View {
    let session: ProjectSession
    @AppStorage(AppSettings.speakerScheme) private var schemeName = SpeakerScheme.vivid.rawValue
    @State private var dragStart: (time: Double, x: CGFloat)?
    @State private var pinchStart: Double?

    private var scheme: SpeakerScheme { SpeakerScheme(rawValue: schemeName) ?? .vivid }
    private var duration: Double { max(session.project.duration, 0.1) }
    private static let laneHeight: CGFloat = 10
    private static let laneGap: CGFloat = 3
    private static let rulerHeight: CGFloat = 14
    /// Names the lanes, so a voice is never told apart by colour alone; every track starts after it.
    static let labelWidth: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: !session.player.isPlaying)) { _ in
                // Read here, not inside the Canvas closure: reads there are not observed, and the
                // playhead would stand still while playing.
                let time = session.player.displayTime
                Canvas { context, size in draw(&context, size: size, time: time) }
            }
            .contentShape(Rectangle())
            .gesture(drag(width: geo.size.width - Self.labelWidth))
            .simultaneousGesture(pinch)
            .accessibilityElement()
            .accessibilityLabel("Timeline")
            .accessibilityValue("\(Timecode.short(session.player.time)) of \(Timecode.short(duration))")
            .accessibilityAdjustableAction { direction in
                session.player.skip(by: direction == .increment ? 5 : -5)
            }
        }
    }

    /// The seconds shown, given the playhead.
    private func window(at time: Double) -> (start: Double, span: Double) {
        let span = duration / session.zoom
        guard session.zoom > 1 else { return (0, duration) }
        return (min(max(0, time - span / 2), duration - span), span)
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let player = session.player
                let x = value.location.x - Self.labelWidth
                if dragStart == nil { dragStart = (player.time, value.startLocation.x) }
                if session.zoom > 1, let start = dragStart {
                    // Zoomed: the audio follows the finger.
                    let spp = duration / session.zoom / Double(width)
                    player.seek(to: start.time - Double(value.location.x - start.x) * spp)
                } else {
                    player.seek(to: Double(max(0, x) / width) * duration)
                }
            }
            .onEnded { value in
                // A tap while zoomed jumps to the spot that was tapped.
                if session.zoom > 1, let start = dragStart, abs(value.translation.width) < 4 {
                    let w = window(at: start.time)
                    session.player.seek(to: w.start + Double(max(0, value.location.x - Self.labelWidth) / width) * w.span)
                }
                dragStart = nil
            }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStart == nil { pinchStart = session.zoom }
                session.zoom = (pinchStart ?? 1) * value.magnification
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func draw(_ context: inout GraphicsContext, size full: CGSize, time: Double) {
        let (start, span) = window(at: time)
        let names = session.project.speakers.prefix(6).map { session.project.name(of: $0.id) }
        // The tracks start after the label column.
        context.translateBy(x: Self.labelWidth, y: 0)
        let size = CGSize(width: full.width - Self.labelWidth, height: full.height)
        let speakers = session.project.speakers
        let lanes = CGFloat(min(speakers.count, 6))
        let lanesHeight = lanes * (Self.laneHeight + Self.laneGap)
        let waveHeight = size.height - lanesHeight - Self.rulerHeight
        let x = { (t: Double) -> CGFloat in CGFloat((t - start) / span) * size.width }

        // Background well
        context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: waveHeight), cornerRadius: 8),
                     with: .style(.fill.quinary))

        // Marks and the selection behind the waveform
        for mark in session.project.marks where mark.end > start && mark.start < start + span {
            let r = CGRect(x: x(mark.start), y: 0, width: max(2, x(mark.end) - x(mark.start)), height: waveHeight)
            context.fill(Path(r), with: .color(.mark.opacity(0.16)))
            context.fill(Path(CGRect(x: r.minX, y: 0, width: r.width, height: 3)), with: .color(.mark))
        }
        if let sel = session.selection {
            context.fill(Path(CGRect(x: x(sel.lowerBound), y: 0, width: x(sel.upperBound) - x(sel.lowerBound), height: waveHeight)),
                         with: .color(.accentColor.opacity(0.18)))
        }
        if let pending = session.pendingStart {
            let lo = min(pending, time), hi = max(pending, time)
            context.fill(Path(CGRect(x: x(lo), y: 0, width: max(2, x(hi) - x(lo)), height: waveHeight)), with: .color(.mark.opacity(0.22)))
        }

        // Waveform: one bar every 3 points, colored by who speaks there
        let peaks = session.peaks, bins = session.speakerBins
        let per = Double(Peaks.binsPerSecond)
        let colors = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, scheme.color(session.color(of: $0.id))) })
        let mid = waveHeight / 2
        if !peaks.isEmpty {
            var column: CGFloat = 1.5
            while column < size.width {
                let t0 = start + Double(column - 1.5) / Double(size.width) * span
                let t1 = start + Double(column + 1.5) / Double(size.width) * span
                let lo = max(0, Int(t0 * per)), hi = min(peaks.count, max(lo + 1, Int(t1 * per)))
                if lo < peaks.count {
                    var peak: Float = 0
                    for i in lo..<hi where peaks[i] > peak { peak = peaks[i] }
                    let speaker = bins.indices.contains((lo + hi) / 2) ? Int(bins[(lo + hi) / 2]) : -1
                    let h = max(1.5, CGFloat(peak) * (waveHeight - 10))
                    let bar = Path(roundedRect: CGRect(x: column - 1, y: mid - h / 2, width: 2, height: h), cornerRadius: 1)
                    let played = t0 < time
                    let color = colors[speaker] ?? Color.secondary
                    context.fill(bar, with: .color(color.opacity(speaker < 0 ? 0.35 : (played ? 1 : 0.4))))
                }
                column += 3
            }
        }

        // Speaker lanes
        for (row, speaker) in speakers.prefix(6).enumerated() {
            let y = waveHeight + 4 + CGFloat(row) * (Self.laneHeight + Self.laneGap)
            context.draw(Text(names[row]).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary),
                         in: CGRect(x: -Self.labelWidth, y: y - 2, width: Self.labelWidth - 6, height: Self.laneHeight + 4))
            context.fill(Path(roundedRect: CGRect(x: 0, y: y, width: size.width, height: Self.laneHeight), cornerRadius: 3),
                         with: .style(.fill.quinary))
            let color = colors[speaker.id] ?? .secondary
            for p in session.paragraphsBySpeaker[speaker.id] ?? [] where p.end > start && p.start < start + span {
                let r = CGRect(x: x(p.start), y: y, width: max(2, x(p.end) - x(p.start)), height: Self.laneHeight)
                context.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(color))
            }
        }

        // Ruler: start, end and the visible span's middle
        let rulerY = size.height - Self.rulerHeight + 2
        context.draw(Text("Waveform").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary),
                     at: CGPoint(x: -Self.labelWidth, y: waveHeight / 2), anchor: .leading)
        let font = Font.system(size: 10, design: .monospaced)
        context.draw(Text(Timecode.short(start)).font(font).foregroundStyle(.secondary), at: CGPoint(x: 0, y: rulerY), anchor: .topLeading)
        context.draw(Text(Timecode.short(start + span)).font(font).foregroundStyle(.secondary),
                     at: CGPoint(x: size.width, y: rulerY), anchor: .topTrailing)
        if session.zoom > 1 {
            context.draw(Text("\(Int(session.zoom.rounded()))×").font(font).foregroundStyle(.secondary),
                         at: CGPoint(x: size.width / 2, y: rulerY), anchor: .top)
        }

        // Playhead
        let px = x(time)
        context.fill(Path(roundedRect: CGRect(x: px - 1, y: -2, width: 2, height: size.height - Self.rulerHeight + 2), cornerRadius: 1),
                     with: .color(.primary))
    }
}
