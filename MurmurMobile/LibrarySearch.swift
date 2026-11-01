import MurmurCore
import SwiftUI

/// One line of a transcript that contains the search, with where it is.
struct SearchHit: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let speaker: String
    let colorIndex: Int
    let start: Double
    let text: AttributedString
}

/// Searches the words of every project in the library.
enum LibrarySearch {
    @MainActor
    static func hits(_ query: String, in items: [Library.Item]) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out: [SearchHit] = []
        for item in items {
            guard let project = try? ProjectFile.read(at: item.url) else { continue }
            let order = project.speakers.map(\.id)
            for paragraph in Merge.paragraphs(project.words) {
                let text = Merge.join(Array(project.words[paragraph.range]))
                guard let match = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                out.append(SearchHit(url: item.url, title: item.title, speaker: project.name(of: paragraph.speaker),
                                     colorIndex: order.firstIndex(of: paragraph.speaker) ?? 0, start: paragraph.start,
                                     text: snippet(text, around: match, query: q)))
            }
        }
        return out
    }

    /// A window of the line around the first match, every match in it set off.
    private static func snippet(_ text: String, around match: Range<String.Index>, query: String) -> AttributedString {
        let lo = text.index(match.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let hi = text.index(match.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        let window = (lo > text.startIndex ? "…" : "") + text[lo..<hi] + (hi < text.endIndex ? "…" : "")
        var attributed = AttributedString(window.replacingOccurrences(of: "\n", with: " "))
        var from = attributed.startIndex
        while let m = attributed[from...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[m].font = .body.weight(.semibold)
            attributed[m].backgroundColor = Color.accentColor.opacity(0.22)
            from = m.upperBound
        }
        return attributed
    }
}

/// Matching lines, grouped by project. Tapping one opens the project at that line.
struct SearchResultsView: View {
    let query: String
    let hits: [SearchHit]
    let open: (SearchHit) -> Void

    var body: some View {
        let scheme = SpeakerScheme.current
        let groups = Dictionary(grouping: hits, by: \.url)
        let order = hits.map(\.url).reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
        List {
            ForEach(order, id: \.self) { url in
                let rows = groups[url] ?? []
                Section {
                    ForEach(rows) { hit in
                        Button { open(hit) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle().fill(scheme.color(hit.colorIndex)).frame(width: 8, height: 8)
                                    Text(hit.speaker).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(scheme.color(hit.colorIndex))
                                    Text(Timecode.short(hit.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Text(hit.text).font(.body).foregroundStyle(.primary).lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    HStack {
                        Text(rows.first?.title ?? "").textCase(nil).font(.headline).foregroundStyle(.primary)
                        Spacer()
                        Text("\(rows.count) \(rows.count == 1 ? "match" : "matches")").textCase(nil).font(.caption)
                    }
                }
            }
        }
        .overlay {
            if hits.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }
}

/// Voice Memos' button: a red dot in a ring.
struct RecordButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 4)
                Circle().fill(Color.recordRed).padding(8)
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record")
    }
}
