import AppKit
import MurmurCore
import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    let session: ProjectSession
    @Environment(\.dismiss) private var dismiss

    enum Range: Hashable { case whole, selection, mark(UUID), allMarks }
    enum Kind: Hashable { case text(TextFormat), audio, video }

    @State private var range: Range = .whole
    @State private var kind: Kind = .text(.markdown)
    @State private var speakerNames = true
    @State private var hideFillers = AppSettings.bool(AppSettings.hideFillersInExport)
    @State private var relativeTimes = false
    @State private var joined = false
    @State private var working = false

    var project: Project { session.project }

    var sections: [TranscriptSection]? {
        switch range {
        case .whole: nil
        case .selection: session.selection.map { [TranscriptSection(name: "Selection", start: $0.lowerBound, end: $0.upperBound)] }
        case .mark(let id): project.marks.first { $0.id == id }.map { [TranscriptSection(name: $0.name, start: $0.start, end: $0.end)] }
        case .allMarks: project.marks.map { TranscriptSection(name: $0.name, start: $0.start, end: $0.end) }
        }
    }

    var clips: [ClipExporter.Clip] {
        (sections ?? [TranscriptSection(name: project.displayTitle, start: 0, end: project.duration)])
            .map { ClipExporter.Clip(name: $0.name ?? project.displayTitle, start: $0.start, end: min($0.end, project.duration)) }
    }

    var options: RenderOptions {
        RenderOptions(speakerNames: speakerNames, hideFillers: hideFillers, relativeTimes: relativeTimes,
                      redactionStyle: AppSettings.redactionStyleValue)
    }

    var preview: String {
        guard case .text(let format) = kind else {
            let names = clips.map { "\($0.name)  \(Timecode.short($0.start)) – \(Timecode.short($0.end))" }
            let joinedNote = clips.count > 1 ? (joined ? "\n\nAll joined into one file." : "\n\nOne file per mark.") : ""
            return names.joined(separator: "\n") + joinedNote
        }
        return String(Renderer.render(project, sections: sections, format: format, options: options).prefix(5000))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Export").font(.system(size: 17, weight: .bold))
                Text("\(project.displayTitle)" + (project.media.map { " · " + URL(fileURLWithPath: $0.path).lastPathComponent } ?? ""))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    label("Range")
                    Picker("Range", selection: $range) {
                        Text("Whole file").tag(Range.whole)
                        if session.selection != nil { Text("Selection").tag(Range.selection) }
                        ForEach(project.marks) { Text($0.name).tag(Range.mark($0.id)) }
                        if project.marks.count > 1 { Text("All marks (\(project.marks.count))").tag(Range.allMarks) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
                GridRow {
                    label("Format")
                    Picker("Format", selection: $kind) {
                        ForEach(TextFormat.allCases) { Text($0.title).tag(Kind.text($0)) }
                        Divider()
                        Text("Audio clip (.m4a)").tag(Kind.audio)
                        if project.media?.hasVideo == true { Text("Video clip (.mp4)").tag(Kind.video) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
                if isClip && clips.count > 1 {
                    GridRow {
                        label("Marks as")
                        Picker("Marks as", selection: $joined) {
                            Text("Separate files, named after each mark").tag(false)
                            Text("One joined file").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }
                if !isClip {
                    GridRow {
                        label("Include")
                        HStack(spacing: 16) {
                            Toggle("Speaker names", isOn: $speakerNames)
                            Toggle("Hide fillers", isOn: $hideFillers)
                            Toggle("Times relative to each part", isOn: $relativeTimes).disabled(range == .whole)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").font(.system(size: 11)).foregroundStyle(.secondary)
                ScrollView {
                    Text(preview)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(minHeight: 200)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.well.opacity(0.6)))

            HStack {
                Text(isClip && session.isRedacting ? (kind == .video ? "Video clips keep the original audio; audio clips bleep personal details" : "Personal details are bleeped") : isClip ? "Clips are cut from the \(project.settings.enhance && session.hasEnhancedAudio ? "enhanced" : "original") audio" : "Cuts snap to whole words")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if case .text(let format) = kind {
                    Button("Copy") {
                        let text = Renderer.render(project, sections: sections, format: format, options: options)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        session.flash("Copied as \(format.title)")
                        dismiss()
                    }
                }
                Button("Save…") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || (isClip && session.playbackURL == nil))
            }
        }
        .padding(24)
        .frame(width: 680, height: 600)
        .onAppear {
            if session.selection != nil { range = .selection }
            else if project.marks.count > 1 { range = .allMarks }
        }
    }

    var isClip: Bool { kind == .audio || kind == .video }

    func label(_ s: String) -> some View { Text(s).foregroundStyle(.secondary).gridColumnAlignment(.trailing) }

    var baseName: String {
        switch range {
        case .whole: project.displayTitle
        case .selection: "\(project.displayTitle) (selection)"
        case .mark(let id): project.marks.first { $0.id == id }?.name ?? project.displayTitle
        case .allMarks: "\(project.displayTitle) (marks)"
        }
    }

    func save() {
        switch kind {
        case .text(let format):
            let panel = NSSavePanel()
            panel.nameFieldStringValue = baseName + "." + format.fileExtension
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let text = Renderer.render(project, sections: sections, format: format, options: options)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                session.flash("Saved \(url.lastPathComponent)")
                dismiss()
            } catch {
                AppState.shared.presentError(error, title: "Couldn’t save the export")
            }
        case .audio, .video:
            guard let source = session.playbackURL else { return }
            let video = kind == .video
            let destination: URL
            if clips.count > 1 && !joined {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.prompt = "Export Here"
                panel.message = "Choose a folder for \(clips.count) clips"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                destination = url
            } else {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = baseName + (video ? ".mp4" : ".m4a")
                panel.allowedContentTypes = [video ? .mpeg4Movie : .mpeg4Audio]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                destination = url
            }
            working = true
            let clips = self.clips
            let joined = clips.count == 1 || self.joined
            Task {
                do {
                    let bleeps = session.hiddenSpans.map { $0.start...$0.end }
                    let files = try await ClipExporter.export(source: source, clips: clips, video: video, joined: joined,
                                                              destination: destination, bleeps: bleeps)
                    session.flash("Exported \(files.count) \(files.count == 1 ? "clip" : "clips")")
                    NSWorkspace.shared.activateFileViewerSelecting(files)
                    dismiss()
                } catch {
                    AppState.shared.presentError(error, title: "Couldn’t export the clip")
                }
                working = false
            }
        }
    }
}
