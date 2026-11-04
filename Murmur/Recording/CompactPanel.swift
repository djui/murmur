import AppKit
import SwiftUI

/// The small floating window for meetings: on top of everything, on every Space, hidden from
/// screen sharing. Shrinks to a one-line strip. Both can be moved and resized, and each remembers
/// where it was.
@MainActor
final class CompactPanelController {
    static let shared = CompactPanelController()
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    /// True while the panel is being placed by code, so the frame isn't saved as the user's.
    private var placing = false

    static let panelSize = NSSize(width: 340, height: 560)
    static let stripSize = NSSize(width: 640, height: 52)
    static let panelMin = NSSize(width: 280, height: 320), panelMax = NSSize(width: 720, height: 1600)
    static let stripMin = NSSize(width: 360, height: 52), stripMax = NSSize(width: 1600, height: 52)
    private static let panelFrameKey = "recorderPanelFrame", stripFrameKey = "recorderStripFrame"

    func show() {
        if panel == nil { panel = makePanel() }
        AppState.shared.recorder.strip = false
        resize(strip: false, animate: false)
        applySharing()
        panel?.orderFrontRegardless()
    }

    /// Follows the "hide from screen sharing" setting.
    func applySharing() {
        panel?.sharingType = AppSettings.bool(AppSettings.hideRecorderFromSharing) ? .none : .readOnly
    }

    #if DEBUG
    /// Layout checks only: lets screenshots see the panel.
    func allowCapture() { panel?.sharingType = .readOnly }
    #endif

    func close() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        panel?.orderOut(nil)
        panel = nil
    }

    func setStrip(_ strip: Bool) {
        AppState.shared.recorder.strip = strip
        resize(strip: strip, animate: true)
    }

    /// Swaps the panel for the full recording window.
    func expand() {
        panel?.orderOut(nil)
        AppState.shared.openWindow?("recording")
        NSApp.activate()
    }

    private func resize(strip: Bool, animate: Bool) {
        guard let panel else { return }
        panel.contentMinSize = strip ? Self.stripMin : Self.panelMin
        panel.contentMaxSize = strip ? Self.stripMax : Self.panelMax
        let frame = Self.saved(strip: strip) ?? defaultFrame(strip: strip, for: panel)
        placing = true
        panel.setFrame(frame, display: true, animate: animate)
        placing = false
    }

    /// Top right for the panel, top centre for the strip, on the screen the panel is on.
    private func defaultFrame(strip: Bool, for panel: NSPanel) -> NSRect {
        let size = strip ? Self.stripSize : Self.panelSize
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        if strip {
            return NSRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12, width: size.width, height: size.height)
        }
        return NSRect(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24, width: size.width, height: size.height)
    }

    /// Where the user last left the panel or strip, if that is still on a screen.
    private static func saved(strip: Bool) -> NSRect? {
        guard let text = UserDefaults.standard.string(forKey: strip ? stripFrameKey : panelFrameKey) else { return nil }
        var frame = NSRectFromString(text)
        guard frame.width > 10, frame.height > 10,
              NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return nil }
        let lo = strip ? stripMin : panelMin, hi = strip ? stripMax : panelMax
        let height = min(hi.height, max(lo.height, frame.height))
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: min(hi.width, max(lo.width, frame.width)), height: height)
        return frame
    }

    private func remember(_ panel: NSPanel) {
        guard !placing else { return }
        let key = AppState.shared.recorder.strip ? Self.stripFrameKey : Self.panelFrameKey
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: key)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                            styleMask: [.nonactivatingPanel, .borderless, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        // Borderless: the views draw their own rounded shapes, so no window frame shows around
        // the strip's capsule. Resizable from its edges all the same.
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.sharingType = AppSettings.bool(AppSettings.hideRecorderFromSharing) ? .none : .readOnly
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView: CompactRoot().environment(AppState.shared))
        panel.setFrame(NSRect(origin: .zero, size: .zero), display: false)
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self, weak panel] _ in
                MainActor.assumeIsolated { if let panel { self?.remember(panel) } }
            })
        }
        return panel
    }
}

/// Lets a drag on the area behind it move the window, where SwiftUI controls would otherwise take the mouse.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct CompactRoot: View {
    @Environment(AppState.self) private var app
    @AppStorage(AppSettings.speakerScheme) private var scheme = SpeakerScheme.vivid.rawValue

    var body: some View {
        Group {
            if app.recorder.strip { StripView(recorder: app.recorder) } else { CompactRecorderView(recorder: app.recorder) }
        }
        .id(scheme)
        .ignoresSafeArea()
    }
}
