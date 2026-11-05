import MurmurCore
import SwiftUI

// MARK: - Mark actions

/// What can be done with one mark, as on the Mac's mark popover: play, rename, copy, share, trim to it,
/// delete. Shown when a mark is tapped on the timeline, and from the Marks lists.
struct MarkActions: ViewModifier {
    let session: ProjectSession
    @Binding var mark: Mark?
    @State private var renaming: Mark?
    @State private var newName = ""
    @State private var sharing: Mark?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(mark?.name ?? "", isPresented: Binding(get: { mark != nil }, set: { if !$0 { mark = nil } }),
                                titleVisibility: .visible, presenting: mark) { m in
                Button("Play") { session.player.play(from: m.start, to: m.end) }
                Button("Rename…") { newName = m.name; renaming = m }
                Button("Copy Text") { session.copy(mark: m) }
                Button("Share…") { sharing = m }
                Button("Trim to This Mark") { trim(to: m) }
                Button("Delete Mark", role: .destructive) { session.remove(mark: m.id) }
            } message: { m in
                Text("\(Timecode.short(m.start)) – \(Timecode.short(m.end)) · \(Timecode.short(m.duration))")
            }
            .alert("Rename Mark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { if let m = renaming { session.rename(mark: m.id, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $sharing) { m in
                ExportView(session: session, range: .mark(m.id), kind: .audio)
            }
    }

    private func trim(to mark: Mark) {
        session.selectMark(mark.id)
        session.trimToSelection()
    }
}

extension View {
    func markActions(session: ProjectSession, mark: Binding<Mark?>) -> some View {
        modifier(MarkActions(session: session, mark: mark))
    }
}

// MARK: - Trim

/// Trim Start/End to the playhead and Remove Trim, for the project's More menu.
struct TrimMenu: View {
    let session: ProjectSession

    var body: some View {
        let span = session.project.span
        // Only a playhead inside the trim, off its edges, can start or end it.
        let inside = session.player.time > span.lowerBound + 0.05 && session.player.time < span.upperBound - 0.05
        Menu {
            Button("Start at Playhead", systemImage: "arrow.right.to.line") { session.trimStart() }
                .disabled(!inside)
            Button("End at Playhead", systemImage: "arrow.left.to.line") { session.trimEnd() }
                .disabled(!inside)
            if session.project.trim != nil {
                Button("Remove Trim", systemImage: "arrow.left.and.right") { session.removeTrim() }
            }
        } label: {
            if session.project.trim != nil {
                Label("Trim · \(Timecode.short(span.lowerBound)) – \(Timecode.short(span.upperBound))", systemImage: "timeline.selection")
            } else {
                Label("Trim", systemImage: "timeline.selection")
            }
        }
    }
}

// MARK: - Notes

/// The project's notes in time order: tap to play from one, swipe to delete, Add Note at the playhead.
struct NotesView: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss
    @State private var editing: NoteDraft?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Add Note at \(Timecode.short(session.player.time))", systemImage: "plus") {
                        editing = NoteDraft(id: nil, time: session.player.time, text: "")
                    }
                } footer: {
                    if session.notes.isEmpty { Text("Notes written while recording show here too.") }
                }
                Section { NotesRows(session: session, editing: $editing) { dismiss() } }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .noteEditor(session: session, editing: $editing)
        }
        .presentationDetents([.medium, .large])
    }
}

/// The notes as list rows, shared by the Notes sheet and the iPad inspector.
struct NotesRows: View {
    let session: ProjectSession
    @Binding var editing: NoteDraft?
    var played: () -> Void = {}

    var body: some View {
        ForEach(session.notes) { note in
            Button {
                session.player.seek(to: note.time)
                session.jumpRequest += 1
                played()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Timecode.short(note.time)).font(.caption.monospacedDigit()).foregroundStyle(Color.mark)
                    Text(note.text).foregroundStyle(.primary).multilineTextAlignment(.leading)
                }
            }
            .tint(.primary)
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { session.remove(note: note.id) }
                Button("Edit", systemImage: "pencil") { editing = NoteDraft(note) }.tint(.orange)
            }
            .contextMenu {
                Button("Edit…", systemImage: "pencil") { editing = NoteDraft(note) }
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = note.text }
                Button("Delete", systemImage: "trash", role: .destructive) { session.remove(note: note.id) }
            }
        }
    }
}

/// A note being written or edited; `id` nil for a new one.
struct NoteDraft: Identifiable {
    var id: UUID?
    var time: Double
    var text: String

    init(id: UUID?, time: Double, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }

    init(_ note: Note) { self.init(id: note.id, time: note.time, text: note.text) }
}

extension View {
    /// The alert that writes a new note or edits one.
    func noteEditor(session: ProjectSession, editing: Binding<NoteDraft?>) -> some View {
        modifier(NoteEditor(session: session, editing: editing))
    }
}

private struct NoteEditor: ViewModifier {
    let session: ProjectSession
    @Binding var editing: NoteDraft?
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(editing?.id == nil ? "Note at \(Timecode.short(editing?.time ?? 0))" : "Edit Note",
                   isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), presenting: editing) { draft in
                TextField("Note", text: $text)
                Button(draft.id == nil ? "Add" : "Save") {
                    if let id = draft.id { session.edit(note: id, to: text) } else { session.addNote(text, at: draft.time) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: editing != nil) { text = editing?.text ?? "" }
    }
}
