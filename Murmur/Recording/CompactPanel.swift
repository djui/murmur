import AppKit
import SwiftUI

/// The small floating window for meetings: on top of everything, on every Space, hidden from
/// screen sharing. Shrinks to a one-line strip.
@MainActor
final class CompactPanelController {
    static let shared = CompactPanelController()
    private var panel: NSPanel?

    static let panelSize = NSSize(width: 340, height: 560)
    static let stripSize = NSSize(width: 640, height: 52)

    func show() {
        if panel == nil { panel = makePanel() }
        AppState.shared.recorder.strip = false
        resize(strip: false, animate: false)
        panel?.orderFrontRegardless()
    }

    #if DEBUG
    /// Layout checks only: lets screenshots see the panel.
    func allowCapture() { panel?.sharingType = .readOnly }
    #endif

    func close() {
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
        let size = strip ? Self.stripSize : Self.panelSize
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var frame = panel.frame
        if panel.frame.width < 10 {
            frame.origin = NSPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24)
        } else {
            frame.origin.y += frame.height - size.height
        }
        frame.size = size
        if strip { frame.origin.x = visible.midX - size.width / 2; frame.origin.y = visible.maxY - size.height - 12 }
        panel.setFrame(frame, display: true, animate: animate)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView: CompactRoot().environment(AppState.shared))
        panel.setFrame(NSRect(origin: .zero, size: .zero), display: false)
        return panel
    }
}

private struct CompactRoot: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.recorder.strip { StripView(recorder: app.recorder) } else { CompactRecorderView(recorder: app.recorder) }
        }
        .ignoresSafeArea()
    }
}
