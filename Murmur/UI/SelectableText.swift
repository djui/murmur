import AppKit
import SwiftUI

/// Read-only transcript text that can be selected with the mouse, unlike SwiftUI's Text, which
/// doesn't say what's selected. A plain click still acts as a click on the line.
struct SelectableText: NSViewRepresentable {
    let text: NSAttributedString
    /// The selected characters (UTF-16 offsets), or nil when nothing is selected.
    @Binding var selection: Range<Int>?
    var onClick: () -> Void
    var onShiftClick: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TranscriptTextView {
        let view = TranscriptTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        view.textStorage?.setAttributedString(text)
        return view
    }

    func updateNSView(_ view: TranscriptTextView, context: Context) {
        context.coordinator.parent = self
        view.onClick = onClick
        view.onShiftClick = onShiftClick
        if view.textStorage?.isEqual(to: text) != true {
            let kept = view.selectedRange()
            view.textStorage?.setAttributedString(text)
            if NSMaxRange(kept) <= text.length { view.setSelectedRange(kept) }
        }
        if selection == nil, view.selectedRange().length > 0 {
            view.setSelectedRange(NSRange(location: view.selectedRange().location, length: 0))
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: TranscriptTextView, context: Context) -> CGSize? {
        // Measured on the text itself, so asking for a size never changes how the view wraps.
        let bounds = text.boundingRect(with: NSSize(width: proposal.width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: proposal.width ?? ceil(bounds.width), height: ceil(bounds.height))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableText
        init(_ parent: SelectableText) { self.parent = parent }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let range = view.selectedRange()
            let new = range.length > 0 ? range.location..<NSMaxRange(range) : nil
            if parent.selection != new { parent.selection = new }
        }
    }
}

final class TranscriptTextView: NSTextView {
    var onClick: () -> Void = {}
    var onShiftClick: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) && selectedRange().length == 0 {
            onShiftClick()
            return
        }
        super.mouseDown(with: event)
        // super tracks the drag; nothing selected afterwards means it was a click.
        if selectedRange().length == 0 && event.clickCount == 1 { onClick() }
    }

    /// Right-click shows the line's own menu (play, copy, assign…) rather than the text view's.
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func resignFirstResponder() -> Bool {
        setSelectedRange(NSRange(location: selectedRange().location, length: 0))
        return super.resignFirstResponder()
    }
}
