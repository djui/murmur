import MurmurCore
import SwiftUI

/// Transport controls, the overview strip, the speaker-colored waveform, speaker lanes and marks.
struct TimelinePanel: View {
    @Bindable var session: ProjectSession
    /// Off when the tracks sit on the left of the window instead.
    var showsTracks = true
    @AppStorage(AppSettings.hasSelected) private var hasSelected = false
    @AppStorage(AppSettings.hasMarked) private var hasMarked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransportBar(session: session)
            if session.mediaMissing { MissingMediaBar(session: session) }
            if showsTracks { TimelineTracks(session: session) }
            // How-to, until the person has selected and marked once; ? keeps the full list.
            if !(hasSelected && hasMarked) {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, showsTracks ? TimelineTracks.labelWidth + 12 : 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    var hint: String {
        let mark = ShortcutStore.shared.map.key(for: .markSection).map { " · \($0.symbol) at the start and again at the end marks a section" } ?? ""
        return "Click to jump · drag to select, then drag its edges\(mark) · swipe or scroll to scrub · pinch to zoom · ? for all shortcuts"
    }
}

/// Says where the media went missing, right under the controls that need it.
struct MissingMediaBar: View {
    let session: ProjectSession

    var path: String { session.project.media?.path ?? "" }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(URL(fileURLWithPath: path).lastPathComponent) isn’t where it was")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Playback, Enhance and clips need it. The transcript, marks and text exports still work.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .help(path)
            Spacer(minLength: 12)
            Button("Locate File…") { session.locateMedia() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

/// A keyboard key, drawn as a key cap so letters like I and l can't be mistaken for digits.
struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor)))
            .accessibilityHidden(true)
    }
}

struct TransportBar: View {
    @Bindable var session: ProjectSession
    private let keys = ShortcutStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Button { session.player.skip(by: -5) } label: { Image(systemName: "gobackward.5") }
                .buttonStyle(PillStyle())
                .help(keys.titled("Back 5 seconds", .back))
                .disabled(session.mediaMissing)
            Button { session.player.toggle() } label: {
                Image(systemName: session.player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(session.mediaMissing ? Color.secondary.opacity(0.35) : Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(session.mediaMissing)
            .help(keys.titled("Play or pause", .playPause))
            .accessibilityLabel(session.player.isPlaying ? "Pause" : "Play")
            Button { session.player.skip(by: 5) } label: { Image(systemName: "goforward.5") }
                .buttonStyle(PillStyle())
                .help(keys.titled("Forward 5 seconds", .forward))
                .disabled(session.mediaMissing)
            HStack(spacing: 0) {
                Text(Timecode.precise(session.player.time)).fontWeight(.medium)
                Text(" / " + Timecode.precise(session.project.duration)).foregroundStyle(.secondary)
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(.leading, 4)
            Menu {
                ForEach(PlayerModel.rates, id: \.self) { r in
                    Button { session.player.rate = r } label: {
                        if r == session.player.rate { Label(PlayerModel.label(r), systemImage: "checkmark") } else { Text(PlayerModel.label(r)) }
                    }
                }
            } label: {
                Text(PlayerModel.label(session.player.rate)).monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(PillStyle(isOn: session.player.rate != 1))
            .fixedSize()
            .help(["Playback speed", keys.map.key(for: .slower).map { "\($0.symbol) slower" }, keys.map.key(for: .faster).map { "\($0.symbol) faster" }]
                .compactMap { $0 }.joined(separator: " · "))
            PillToggle(title: "Enhance", systemImage: "waveform.badge.magnifyingglass",
                       isOn: Binding(get: { session.project.settings.enhance }, set: { session.setEnhance($0) }))
                .help("Clean up the audio for playback, transcription and export (Clear)")
                .disabled(session.mediaMissing)
            Spacer()
            MarkSectionButton(session: session)
            ZoomControl(session: session)
        }
    }
}

/// One button for marking: press at the start of a section, press again at its end.
struct MarkSectionButton: View {
    @Bindable var session: ProjectSession

    var pending: Bool { session.pendingStart != nil }
    var key: String? { ShortcutStore.shared.map.key(for: .markSection)?.symbol }
    var press: String { key.map { "Press \($0) or click" } ?? "Click" }

    var title: String {
        if let start = session.pendingStart { return "End section from \(Timecode.short(start))" }
        return session.selection != nil ? "Save selection as mark" : "Mark section"
    }

    var body: some View {
        Button { session.toggleMarkSection() } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.mark).frame(width: 9, height: 9)
                Text(title)
                if let key { KeyCap(key: key) }
            }
        }
        .buttonStyle(PillStyle(isOn: pending))
        .help(pending ? "\(press) at the end of the section; Esc cancels"
                      : "\(press) at the start of a section, then again at its end")
    }
}

/// Zoom as one segmented pill: out, the visible span (click for the whole file), in.
struct ZoomControl: View {
    @Bindable var session: ProjectSession

    var spanLabel: String {
        guard session.zoom > 1.01 else { return "Fit" }
        let span = session.project.duration / session.zoom
        if span >= 90 { return "\(Int((span / 60).rounded())) min" }
        return "\(max(1, Int(span.rounded()))) s"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { session.zoom /= 2 } label: { Image(systemName: "minus").frame(width: 28, height: 26) }
                .disabled(session.zoom <= 1.01)
                .accessibilityLabel("Zoom out")
                .help("Zoom out (⌘−)")
            Divider().frame(height: 14)
            Button { session.zoom = 1 } label: {
                Text(spanLabel).font(.system(size: 12, weight: .medium)).monospacedDigit().frame(width: 52, height: 26)
            }
            .accessibilityLabel("Zoom to fit, now showing \(spanLabel)")
            .help("Show the whole file (⌘0)")
            Divider().frame(height: 14)
            Button { session.zoom *= 2 } label: { Image(systemName: "plus").frame(width: 28, height: 26) }
                .disabled(session.zoom >= 63.9)
                .accessibilityLabel("Zoom in")
                .help("Zoom in (⌘+), or pinch on the timeline")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

struct TimelineTracks: View {
    @Bindable var session: ProjectSession
    /// Time runs down a column instead of across; the tracks become columns side by side.
    var vertical = false
    @State private var dragView: ClosedRange<Double>?
    @State private var dragEdge: Edge?
    /// Set while the playhead itself is being dragged, so the drag scrubs instead of selecting.
    @State private var draggingPlayhead = false
    @State private var pinchBase: Double?
    /// The speaker turn the pointer has snapped to; clicks and selection ends land on its start.
    @State private var snap: Paragraph?
    @Namespace private var axSpace

    enum Edge { case start, end }

    /// How close, in points, the pointer must come to a speaker turn before it snaps.
    static let snapDistance: CGFloat = 8

    static let labelWidth: CGFloat = 104
    /// A little air above the marks row.
    static let topInset: CGFloat = 4
    static let markRowHeight: CGFloat = 18
    static let laneHeight: CGFloat = 22
    /// Narrower on the left, where the column takes width from the transcript.
    var waveHeight: CGFloat { vertical ? 88 : 110 }
    /// Wider on the left, where time labels sit beside the ticks instead of along them.
    var rulerHeight: CGFloat { vertical ? 48 : 20 }

    // Heights are across the tracks; on the left they are widths.
    var speakers: [Speaker] { session.project.speakers }
    /// Overlapping marks stack into rows; the marks area grows with them (up to four rows).
    var marksHeight: CGFloat { CGFloat(MarkLayout.rowCount(session.project.marks)) * Self.markRowHeight + 2 }
    /// Marks and waveform, above the speaker lanes.
    var topHeight: CGFloat { Self.topInset + marksHeight + waveHeight }
    /// Past this many speakers the lanes scroll, so the transcript stays on screen.
    static let maxVisibleLanes = 6
    var lanesHeight: CGFloat { CGFloat(min(speakers.count, Self.maxVisibleLanes)) * Self.laneHeight }
    var tracksHeight: CGFloat { topHeight + lanesHeight + rulerHeight }
    var zoomed: Bool { session.zoom > 1.01 }

    var body: some View {
        // While playing, redraw every display frame from the player's own clock so the view glides.
        SwiftUI.TimelineView(.animation(paused: !session.player.isPlaying)) { _ in
            let now = session.player.displayTime
            let view = dragView ?? viewRange(at: now)
            if vertical { columns(view: view, now: now) } else { tracks(view: view, now: now) }
        }
    }

    /// On the left: a header per column, then marks, waveform, speakers and ruler side by side.
    func columns(view: ClosedRange<Double>, now: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                if zoomed { Color.clear.frame(width: 28) }
                RoundedRectangle(cornerRadius: 2).fill(Palette.mark).frame(width: 9, height: 9)
                    .frame(width: Self.topInset + marksHeight)
                    .help("Marks")
                label("Waveform").frame(width: waveHeight)
                if speakers.count > Self.maxVisibleLanes {
                    label("\(speakers.count) speakers").frame(width: lanesHeight)
                } else {
                    ForEach(speakers) { s in
                        SpeakerDot(index: session.color(of: s.id)).frame(width: Self.laneHeight).help(s.displayName)
                    }
                }
            }
            .frame(height: 16)
            HStack(spacing: 10) {
                // Zoomed in, a map of where you are.
                if zoomed { OverviewStrip(session: session, vertical: true).frame(width: 18) }
                HStack(spacing: 0) {
                    track { ctx, size in drawTop(ctx, size: size, view: view, now: now) }.frame(width: topHeight)
                    ScrollView(.horizontal) {
                        track { ctx, size in drawLanes(ctx, size: size, view: view) }
                            .frame(width: CGFloat(speakers.count) * Self.laneHeight)
                            .frame(maxHeight: .infinity)
                    }
                    .scrollDisabled(speakers.count <= Self.maxVisibleLanes)
                    .frame(width: lanesHeight)
                    track { ctx, size in drawRuler(ctx, size: size, view: view) }.frame(width: rulerHeight)
                }
                .background {
                    GeometryReader { geo in
                        ScrollWheelCatcher { dx, dy, precise in scrub(dx: dx, dy: dy, precise: precise, width: geo.size.height) }
                    }
                }
                .overlay {
                    Canvas { ctx, size in drawCursor(ctx, size: size, view: view, now: now) }
                        .allowsHitTesting(false)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Timeline")
                .accessibilityValue("Playhead at \(Timecode.short(session.player.time))")
                .modifier(TimelineAccessibility(session: session, space: axSpace))
            }
        }
        .frame(width: tracksHeight + (zoomed ? 28 : 0))
        .frame(maxHeight: .infinity)
    }

    func tracks(view: ClosedRange<Double>, now: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // At Fit the waveform already shows the whole file; zoomed in, a map of where you are.
            if zoomed {
                HStack(spacing: 12) {
                    label("Overview").frame(width: Self.labelWidth, alignment: .leading)
                    OverviewStrip(session: session)
                }
                .frame(height: 18)
            }
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: Self.topInset)
                        label("Marks").frame(height: marksHeight)
                        label("Waveform").frame(height: waveHeight)
                    }
                    .frame(width: Self.labelWidth, alignment: .leading)
                    track { ctx, size in drawTop(ctx, size: size, view: view, now: now) }.frame(height: topHeight)
                }
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(speakers) { s in
                                HStack(spacing: 6) {
                                    SpeakerDot(index: session.color(of: s.id))
                                    Text(s.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                }
                                .frame(height: Self.laneHeight, alignment: .leading)
                            }
                        }
                        .frame(width: Self.labelWidth, alignment: .leading)
                        track { ctx, size in drawLanes(ctx, size: size, view: view) }
                            .frame(height: CGFloat(speakers.count) * Self.laneHeight)
                    }
                }
                .scrollDisabled(speakers.count <= Self.maxVisibleLanes)
                .frame(height: lanesHeight)
                HStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        Color.clear
                        if speakers.count > Self.maxVisibleLanes {
                            Text("\(speakers.count) speakers · scroll").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: Self.labelWidth, alignment: .leading)
                    track { ctx, size in drawRuler(ctx, size: size, view: view) }.frame(height: rulerHeight)
                }
            }
            .frame(height: tracksHeight)
            .background {
                GeometryReader { geo in
                    ScrollWheelCatcher { dx, dy, precise in scrub(dx: dx, dy: dy, precise: precise, width: geo.size.width - Self.labelWidth - 12) }
                }
            }
            // Selection and playhead run across all the tracks, over the scrolling lanes too.
            .overlay {
                Canvas { ctx, size in drawCursor(ctx, size: size, view: view, now: now) }
                    .padding(.leading, Self.labelWidth + 12)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Timeline")
            .accessibilityValue("Playhead at \(Timecode.short(session.player.time))")
            .modifier(TimelineAccessibility(session: session, space: axSpace))
        }
    }

    /// One part of the tracks; every part takes the same clicks, drags, pinches and cursors.
    func track(_ draw: @escaping (GraphicsContext, CGSize) -> Void) -> some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(ctx, size) }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: along(geo.size)))
                .simultaneousGesture(pinchGesture)
                .onContinuousHover { phase in hover(phase, width: along(geo.size)) }
        }
    }

    /// Where a point, or the length of a size, falls along the time axis.
    func along(_ p: CGPoint) -> CGFloat { vertical ? p.y : p.x }
    func along(_ s: CGSize) -> CGFloat { vertical ? s.height : s.width }

    /// Track space has time along x and the tracks stacked down y; on the left the two swap,
    /// so each track draws the same way in both layouts. Text is drawn unturned, at `screen(_:)`.
    func oriented(_ context: GraphicsContext, _ size: CGSize) -> (GraphicsContext, CGSize) {
        guard vertical else { return (context, size) }
        var ctx = context
        ctx.concatenate(.swapAxes)
        return (ctx, CGSize(width: size.height, height: size.width))
    }

    func screen(_ p: CGPoint) -> CGPoint { vertical ? CGPoint(x: p.y, y: p.x) : p }

    var resizeCursor: NSCursor { vertical ? .resizeUpDown : .resizeLeftRight }
    var textCursor: NSCursor { vertical ? .iBeamCursorForVerticalLayout : .iBeam }
    var snapCursor: NSCursor { vertical ? Self.snapCursorAcross : Self.snapCursorDown }

    func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxHeight: .infinity, alignment: .center)
    }

    var viewRange: ClosedRange<Double> { viewRange(at: session.player.time) }

    /// The visible span, centred on `now` where the file allows.
    func viewRange(at now: Double) -> ClosedRange<Double> {
        let duration = max(session.project.duration, 0.1)
        let span = duration / session.zoom
        let v0 = min(max(now - span / 2, 0), duration - span)
        return v0...(v0 + span)
    }

    var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchBase == nil { pinchBase = session.zoom }
                session.zoom = (pinchBase ?? 1) * value.magnification
            }
            .onEnded { _ in pinchBase = nil }
    }

    /// Which selection edge, if any, is under `x`.
    func edge(at x: CGFloat, width: CGFloat, view: ClosedRange<Double>) -> Edge? {
        guard let sel = session.selection else { return nil }
        let span = view.upperBound - view.lowerBound
        func px(_ t: Double) -> CGFloat { CGFloat((t - view.lowerBound) / span) * width }
        if abs(px(sel.lowerBound) - x) <= 6 { return .start }
        if abs(px(sel.upperBound) - x) <= 6 { return .end }
        return nil
    }

    /// Whether the playhead line (or its handle in the ruler) is under `x`.
    func onPlayhead(_ x: CGFloat, width: CGFloat, view: ClosedRange<Double>) -> Bool {
        let t = session.player.time
        return view.contains(t) && abs(self.x(t, width: width, view: view) - x) <= 6
    }

    /// The speaker turn starting within `snapDistance` of `x`, unless Option is held.
    func turn(near x: CGFloat, width: CGFloat, view: ClosedRange<Double>) -> Paragraph? {
        guard !NSEvent.modifierFlags.contains(.option) else { return nil }
        let reach = Double(Self.snapDistance / max(1, width)) * (view.upperBound - view.lowerBound)
        let t = time(at: x, width: width, view: view)
        return session.turns
            .filter { abs($0.start - t) <= reach }
            .min { abs($0.start - t) < abs($1.start - t) }
    }

    /// Moves the snap, with a light tick as it catches a new turn.
    func setSnap(_ turn: Paragraph?) {
        guard turn?.id != snap?.id else { return }
        if turn != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        snap = turn
    }

    /// The time under `x`, pulled onto a speaker turn when one is close.
    func snappedTime(at x: CGFloat, width: CGFloat, view: ClosedRange<Double>) -> Double {
        turn(near: x, width: width, view: view)?.start ?? time(at: x, width: width, view: view)
    }

    func hover(_ phase: HoverPhase, width: CGFloat) {
        switch phase {
        case .active(let point) where edge(at: along(point), width: width, view: viewRange) != nil:
            setSnap(nil)
            resizeCursor.set()
        case .active(let point) where onPlayhead(along(point), width: width, view: viewRange):
            setSnap(nil)
            resizeCursor.set()
        case .active(let point):
            let turn = turn(near: along(point), width: width, view: viewRange)
            setSnap(turn)
            (turn == nil ? textCursor : snapCursor).set()
        case .ended:
            setSnap(nil)
            NSCursor.arrow.set()
        }
    }

    /// Moves the playhead by a swipe or wheel turn, a point of scroll per point of waveform. Returns
    /// false for a trackpad's scroll across the time axis, which belongs to the speaker lanes.
    func scrub(dx: CGFloat, dy: CGFloat, precise: Bool, width: CGFloat) -> Bool {
        let (along, across) = vertical ? (dy, dx) : (dx, dy)
        let delta: CGFloat
        if abs(along) >= abs(across) {
            delta = vertical && !precise ? along * 12 : along
        } else if !precise {
            delta = across * 12  // a mouse wheel reports lines, not points
        } else {
            return false
        }
        guard delta != 0, !session.mediaMissing, dragView == nil else { return true }
        let span = session.project.duration / session.zoom
        let t = session.player.time + Double(delta / max(1, width)) * span
        session.player.seek(to: min(max(t, 0), session.project.duration))
        return true
    }

    func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragView == nil {
                    dragView = viewRange
                    dragEdge = edge(at: along(value.startLocation), width: width, view: viewRange)
                    draggingPlayhead = dragEdge == nil && onPlayhead(along(value.startLocation), width: width, view: viewRange)
                }
                guard let view = dragView, abs(along(value.translation)) > 3 else { return }
                setSnap(turn(near: along(value.location), width: width, view: view))
                let t = snappedTime(at: along(value.location), width: width, view: view)
                if draggingPlayhead {
                    session.player.seek(to: t)
                } else if let dragEdge, let sel = session.selection {
                    let other = dragEdge == .start ? sel.upperBound : sel.lowerBound
                    session.select(min(t, other)...max(t, other))
                } else {
                    let a = snappedTime(at: along(value.startLocation), width: width, view: view)
                    session.select(min(a, t)...max(a, t))
                }
            }
            .onEnded { value in
                let view = dragView ?? viewRange
                if abs(along(value.translation)) <= 3 {
                    session.player.seek(to: snappedTime(at: along(value.location), width: width, view: view))
                }
                dragView = nil
                dragEdge = nil
                draggingPlayhead = false
            }
    }

    func time(at x: CGFloat, width: CGFloat, view: ClosedRange<Double>) -> Double {
        let f = Double(max(0, min(width, x)) / max(1, width))
        return view.lowerBound + f * (view.upperBound - view.lowerBound)
    }

    func x(_ t: Double, width: CGFloat, view: ClosedRange<Double>) -> CGFloat {
        CGFloat((t - view.lowerBound) / max(0.001, view.upperBound - view.lowerBound)) * width
    }

    /// Marks and the speaker-coloured waveform.
    func drawTop(_ context: GraphicsContext, size canvas: CGSize, view: ClosedRange<Double>, now t: Double) {
        let (track, size) = oriented(context, canvas)
        var ctx = track
        let span = max(0.001, view.upperBound - view.lowerBound)
        func x(_ t: Double) -> CGFloat { self.x(t, width: size.width, view: view) }
        let peaks = session.peaks
        let bins = session.speakerBins
        let scheme = SpeakerScheme.current
        ctx.translateBy(x: 0, y: Self.topInset)

        // Marks lane: one row per overlap level; marks past the last row are counted.
        let rows = MarkLayout.rows(session.project.marks)
        let hidden = session.project.marks.count - rows.count
        if hidden > 0 {
            context.draw(Text(vertical ? "+\(hidden)" : "+\(hidden) more").font(.system(size: 10, weight: .semibold)).foregroundColor(Palette.markText),
                         at: screen(CGPoint(x: size.width - 4, y: Self.topInset + Self.markRowHeight / 2)), anchor: vertical ? .bottom : .trailing)
        }
        for mark in session.project.marks where mark.end > view.lowerBound && mark.start < view.upperBound {
            guard let row = rows[mark.id] else { continue }
            let rect = CGRect(x: x(max(mark.start, view.lowerBound)), y: 1 + CGFloat(row) * Self.markRowHeight,
                              width: max(2, x(min(mark.end, view.upperBound)) - x(max(mark.start, view.lowerBound))),
                              height: Self.markRowHeight - 3)
            let path = Path(roundedRect: rect, cornerRadius: 4)
            ctx.fill(path, with: .color(Palette.mark.opacity(0.18)))
            ctx.stroke(path, with: .color(Palette.mark), lineWidth: 1)
            // Names only fit along the marks; on the left the marks are listed in the sidebar.
            if !vertical && rect.width > 30 {
                var c = ctx
                c.clip(to: Path(rect.insetBy(dx: 5, dy: 0)))
                c.draw(Text(mark.name).font(.system(size: 10, weight: .semibold)).foregroundColor(Palette.markText),
                       at: CGPoint(x: rect.minX + 6, y: rect.midY), anchor: .leading)
            }
        }

        // Waveform: bars sit on a fixed time grid, so scrolling slides them instead of resampling them.
        let barCount = max(1, Int(size.width / 4))
        let barWidth = size.width / CGFloat(barCount)
        let barSpan = span / Double(barCount)
        let mid = marksHeight + waveHeight / 2
        var wave = ctx
        wave.clip(to: Path(CGRect(x: 0, y: marksHeight, width: size.width, height: waveHeight)))
        for i in Int((view.lowerBound / barSpan).rounded(.down))..<Int((view.upperBound / barSpan).rounded(.up)) {
            let a = Double(i) * barSpan
            let b = a + barSpan
            let amp = peaks.isEmpty ? 0.04 : CGFloat(Peaks.loudness(Peaks.peak(in: peaks, from: a, to: b)))
            let h = max(3, amp * (waveHeight - 6))
            let bin = Int((a + b) / 2 * Double(Peaks.binsPerSecond))
            let speaker = bins.indices.contains(bin) ? Int(bins[bin]) : -1
            let color = speaker < 0 ? Palette.silence : scheme.color(session.color(of: speaker))
            let rect = CGRect(x: x(a) + 0.5, y: mid - h / 2, width: max(1, barWidth - 2), height: h)
            wave.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(color.opacity((a + b) / 2 <= t ? 1 : 0.4)))
        }
    }

    /// One lane per speaker; each draws only its own paragraphs.
    func drawLanes(_ context: GraphicsContext, size canvas: CGSize, view: ClosedRange<Double>) {
        let (track, size) = oriented(context, canvas)
        var ctx = track
        func x(_ t: Double) -> CGFloat { self.x(t, width: size.width, view: view) }
        let scheme = SpeakerScheme.current
        var laneTop: CGFloat = 0
        for speaker in speakers {
            let track = CGRect(x: 0, y: laneTop + 4, width: size.width, height: Self.laneHeight - 8)
            ctx.fill(Path(roundedRect: track, cornerRadius: 4), with: .color(Palette.well))
            let index = session.color(of: speaker.id)
            let color = scheme.color(index)
            for p in session.paragraphsBySpeaker[speaker.id] ?? [] where p.end > view.lowerBound && p.start < view.upperBound {
                let r = CGRect(x: x(max(p.start, view.lowerBound)), y: track.minY + 2,
                               width: max(1.5, x(min(p.end, view.upperBound)) - x(max(p.start, view.lowerBound))),
                               height: track.height - 4)
                let block = Path(roundedRect: r, cornerRadius: 3)
                ctx.fill(block, with: .color(color))
                if scheme.isHatched(index) { hatch(&ctx, block, rect: r) }
            }
            laneTop += Self.laneHeight
        }
    }

    func drawRuler(_ context: GraphicsContext, size canvas: CGSize, view: ClosedRange<Double>) {
        let (ctx, size) = oriented(context, canvas)
        let span = max(0.001, view.upperBound - view.lowerBound)
        let step: Double = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800].first { span / $0 <= 14 } ?? 3600
        var tick = (view.lowerBound / step).rounded(.up) * step
        while tick <= view.upperBound {
            let px = x(tick, width: size.width, view: view)
            if px < size.width - (vertical ? 16 : 40) {
                ctx.fill(Path(CGRect(x: px, y: 2, width: 1, height: 12)), with: .color(Color(nsColor: .separatorColor)))
                // Across the top the time follows its tick; on the left it sits beside it.
                context.draw(Text(Timecode.short(tick)).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary),
                             at: screen(vertical ? CGPoint(x: px, y: 16) : CGPoint(x: px + 4, y: 8)), anchor: .leading)
            }
            tick += step
        }
    }

    /// The selection (or the section being marked) and the playhead, from the marks down to the ruler.
    func drawCursor(_ context: GraphicsContext, size canvas: CGSize, view: ClosedRange<Double>, now t: Double) {
        let (ctx, size) = oriented(context, canvas)
        func x(_ t: Double) -> CGFloat { self.x(t, width: size.width, view: view) }
        let top = Self.topInset
        let bottom = topHeight + lanesHeight
        let mid = top + marksHeight + waveHeight / 2

        let selection = session.pendingStart.map { min($0, t)...max($0, t) } ?? session.selection
        if let sel = selection, sel.upperBound > view.lowerBound, sel.lowerBound < view.upperBound {
            let lo = x(max(sel.lowerBound, view.lowerBound)), hi = x(min(sel.upperBound, view.upperBound))
            let rect = CGRect(x: lo, y: top, width: max(2, hi - lo), height: bottom - top)
            let tint = session.pendingStart != nil ? Palette.mark : Color.accentColor
            ctx.fill(Path(rect), with: .color(tint.opacity(0.12)))
            ctx.fill(Path(CGRect(x: lo, y: top, width: 2, height: bottom - top)), with: .color(tint))
            if session.pendingStart == nil {
                ctx.fill(Path(CGRect(x: hi - 2, y: top, width: 2, height: bottom - top)), with: .color(tint))
                for edgeX in [lo + 1, hi - 1] {
                    ctx.fill(Path(roundedRect: CGRect(x: edgeX - 3, y: mid - 9, width: 6, height: 18), cornerRadius: 3), with: .color(tint))
                }
            }
        }

        // The speaker turn the pointer snapped to, in that speaker's colour, with who and when
        if let snap, snap.start >= view.lowerBound, snap.start <= view.upperBound {
            let px = x(snap.start)
            let color = SpeakerScheme.current.color(session.color(of: snap.speaker))
            ctx.fill(Path(CGRect(x: px - 1, y: top, width: 2, height: bottom - top)), with: .color(color))
            let label = context.resolve(Text("\(session.project.name(of: snap.speaker)) · \(Timecode.short(snap.start))")
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.white))
            let w = label.measure(in: CGSize(width: 300, height: 20)).width + 10
            // The pill stays upright: beside the line across the top, just under it on the left.
            let pill: CGRect
            if vertical {
                let flip = px + 20 > size.width
                pill = CGRect(x: max(0, min(top + marksHeight + 3, canvas.width - w)), y: flip ? px - 20 : px + 4, width: w, height: 16)
            } else {
                let flip = px + 4 + w > size.width
                pill = CGRect(x: flip ? px - 4 - w : px + 4, y: top + marksHeight + 3, width: w, height: 16)
            }
            context.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(color))
            context.draw(label, at: CGPoint(x: pill.midX, y: pill.midY))
        }

        // Playhead: one line from the marks down to its handle in the ruler, which you can drag
        if t >= view.lowerBound && t <= view.upperBound {
            let px = x(t)
            ctx.fill(Path(CGRect(x: px - 1, y: top, width: 2, height: bottom - top)), with: .color(.primary))
            var handle = Path()
            handle.move(to: CGPoint(x: px, y: bottom))
            handle.addLine(to: CGPoint(x: px + 6, y: bottom + 6))
            handle.addLine(to: CGPoint(x: px + 6, y: bottom + 15))
            handle.addLine(to: CGPoint(x: px - 6, y: bottom + 15))
            handle.addLine(to: CGPoint(x: px - 6, y: bottom + 6))
            handle.closeSubpath()
            ctx.fill(handle, with: .color(.primary))
        }
    }

    /// An I-beam with notches either side: the pointer is locked onto the start of a speaker's turn.
    static let snapCursorDown = makeSnapCursor(across: false)
    /// The same, lying down, for time running down the left.
    static let snapCursorAcross = makeSnapCursor(across: true)

    static func makeSnapCursor(across: Bool) -> NSCursor {
        func pt(_ x: Double, _ y: Double) -> NSPoint { across ? NSPoint(x: y, y: x) : NSPoint(x: x, y: y) }
        let image = NSImage(size: across ? NSSize(width: 22, height: 17) : NSSize(width: 17, height: 22), flipped: true) { _ in
            let beam = NSBezierPath()
            for (a, b) in [((5.5, 2.0), (11.5, 2.0)), ((5.5, 20.0), (11.5, 20.0)), ((8.5, 2.0), (8.5, 20.0))] {
                beam.move(to: pt(a.0, a.1))
                beam.line(to: pt(b.0, b.1))
            }
            let notches = NSBezierPath()
            for side in [-1.0, 1.0] {
                notches.move(to: pt(8.5 + side * 2, 11))
                notches.line(to: pt(8.5 + side * 7, 7))
                notches.line(to: pt(8.5 + side * 7, 15))
                notches.close()
            }
            NSColor.white.set()
            beam.lineWidth = 3.5
            beam.stroke()
            notches.lineWidth = 2
            notches.stroke()
            NSColor.black.set()
            beam.lineWidth = 1.5
            beam.stroke()
            notches.fill()
            return true
        }
        return NSCursor(image: image, hotSpot: pt(8.5, 11))
    }

    /// Diagonal stripes, so neighbouring speakers differ by more than colour.
    func hatch(_ ctx: inout GraphicsContext, _ block: Path, rect: CGRect) {
        var c = ctx
        c.clip(to: block)
        var stripes = Path()
        var sx = rect.minX - rect.height
        while sx < rect.maxX {
            stripes.move(to: CGPoint(x: sx, y: rect.maxY))
            stripes.addLine(to: CGPoint(x: sx + rect.height, y: rect.minY))
            sx += 5
        }
        c.stroke(stripes, with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.8)), lineWidth: 1.5)
    }
}

/// Hands scroll-wheel and trackpad scrolls over its area to `onScroll` (deltas in points, `precise` for
/// a trackpad), which returns whether it took them. Watches the window's events rather than sitting on
/// top, so clicks and drags still reach the views above it.
struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, Bool) -> Bool

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat, Bool) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      self.onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas) == true
                else { return event }
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension CGAffineTransform {
    /// Swaps x and y: what runs across runs down instead.
    static let swapAxes = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
}

/// The whole file at a glance; click or drag to jump.
struct OverviewStrip: View {
    @Bindable var session: ProjectSession
    /// Time runs down, beside the timeline on the left.
    var vertical = false

    var body: some View {
        GeometryReader { geo in
            Canvas { context, canvas in
                var ctx = context
                var size = canvas
                if vertical {
                    ctx.concatenate(.swapAxes)
                    size = CGSize(width: canvas.height, height: canvas.width)
                }
                let duration = max(session.project.duration, 0.1)
                let count = max(1, Int(size.width / 3))
                let w = size.width / CGFloat(count)
                let bins = session.speakerBins
                let scheme = SpeakerScheme.current
                for i in 0..<count {
                    let a = Double(i) / Double(count) * duration, b = Double(i + 1) / Double(count) * duration
                    let amp = session.peaks.isEmpty ? 0.1 : CGFloat(Peaks.loudness(Peaks.peak(in: session.peaks, from: a, to: b)))
                    let h = max(2, amp * (size.height - 6))
                    let bin = Int((a + b) / 2 * Double(Peaks.binsPerSecond))
                    let s = bins.indices.contains(bin) ? Int(bins[bin]) : -1
                    let color = s < 0 ? Palette.silence : scheme.color(session.color(of: s))
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
                let length = vertical ? geo.size.height : geo.size.width
                let f = Double(max(0, min(length, vertical ? v.location.y : v.location.x)) / max(1, length))
                session.player.seek(to: f * session.project.duration)
            })
        }
        .accessibilityLabel("Overview of the whole file")
    }
}

/// The tracks are drawn, so VoiceOver gets the marks and each speaker's turns as elements of their
/// own, plus rotors to step through them.
struct TimelineAccessibility: ViewModifier {
    let session: ProjectSession
    let space: Namespace.ID

    func body(content: Content) -> some View {
        content
            .accessibilityChildren { tracks }
            .accessibilityRotor("Marks") {
                ForEach(session.project.marks) { m in AccessibilityRotorEntry(Text(m.name), id: m.id, in: space) }
            }
            .accessibilityRotor("Speaker turns") {
                ForEach(session.paragraphs) { p in AccessibilityRotorEntry(Text(turnLabel(p)), id: p.id, in: space) }
            }
    }

    @ViewBuilder var tracks: some View {
        ForEach(session.project.marks) { m in
            Text("Mark: \(m.name), \(Timecode.short(m.start)) to \(Timecode.short(m.end))")
                .accessibilityRotorEntry(id: m.id, in: space)
                .accessibilityAction { session.select(m.start...m.end); session.player.seek(to: m.start) }
        }
        ForEach(session.paragraphs) { p in
            Text(turnLabel(p) + " to \(Timecode.short(p.end))")
                .accessibilityRotorEntry(id: p.id, in: space)
                .accessibilityAction { session.player.seek(to: p.start) }
        }
    }

    func turnLabel(_ p: Paragraph) -> String {
        "\(session.project.name(of: p.speaker)), \(Timecode.short(p.start))"
    }
}
