import Align
import Clear
import Ear
import Foundation
import Observation
import Tongue
import Uhm
import Voz
import Who

enum ModelKind: String, CaseIterable, Identifiable, Sendable {
    case voz, who, ear, align, uhm, clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voz: "Transcription"
        case .who: "Speakers"
        case .ear: "Language"
        case .align: "Word timing"
        case .uhm: "Hide fillers"
        case .clear: "Enhance audio"
        }
    }

    var engine: String {
        switch self {
        case .voz: "Voz"
        case .who: "Who"
        case .ear: "Ear"
        case .align: "Align"
        case .uhm: "Uhm"
        case .clear: "Clear"
        }
    }

    var detail: String {
        switch self {
        case .voz: "25 languages, word timestamps"
        case .who: "Who spoke when, overlaps kept"
        case .ear: "Detects the spoken language"
        case .align: "Tighter word timing"
        case .uhm: "Finds um, uh and hmm"
        case .clear: "Denoise and level speech"
        }
    }

    /// Download size where it is published.
    var approxMB: Int? {
        switch self {
        case .voz: 467
        case .who: 42
        case .ear: 5
        case .align: 1
        case .uhm, .clear: nil
        }
    }

    var isRequired: Bool { self == .voz || self == .who || self == .ear || self == .align }

    var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("com.djui.Murmur/Models/\(rawValue)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum ModelState: Equatable {
    case missing
    case downloading(Double)
    case preparing
    case ready
    case failed(String)

    /// Downloaded and usable (possibly still being prepared for first use).
    var isReady: Bool { self == .ready || self == .preparing }
}

/// The model instances. Construction does no work; weights load on first use.
final class Engines: @unchecked Sendable {
    static let shared = Engines()

    let who = Who(directory: ModelKind.who.directory.path, variant: .int8)
    let ear = Ear(directory: ModelKind.ear.directory.path)
    let align = Align(directory: ModelKind.align.directory.path)
    let uhm = Uhm(directory: ModelKind.uhm.directory.path)
    let clear = Clear(directory: ModelKind.clear.directory.path)
    let tongue: Tongue? = try? Tongue()

    private let lock = NSLock()
    private var vozTask: Task<Voz, Error>?

    /// The transcriber, loaded once. The first load after a download takes ~20 s.
    func voz() async throws -> Voz {
        let task = lock.withLock { () -> Task<Voz, Error> in
            if let vozTask { return vozTask }
            let task = Task { try await Voz(directory: ModelKind.voz.directory.path) }
            vozTask = task
            return task
        }
        do { return try await task.value } catch {
            lock.withLock { vozTask = nil }
            throw error
        }
    }

    private var warmTasks: [ModelKind: Task<Void, Never>] = [:]
    private var warmed: Set<ModelKind> = []

    func isWarm(_ kind: ModelKind) -> Bool { lock.withLock { warmed.contains(kind) } }

    /// Loads a model and runs it once on silence. The first time a build of the app does this, Core ML
    /// prepares the model for the Neural Engine, which takes seconds (Voz: about 20 s); after that it is
    /// quick. Concurrent callers share one warm-up.
    func warmUp(_ kind: ModelKind) async {
        let task = lock.withLock { () -> Task<Void, Never> in
            if let task = warmTasks[kind] { return task }
            let task = Task { await self.load(kind) }
            warmTasks[kind] = task
            return task
        }
        await task.value
        lock.withLock { _ = warmed.insert(kind) }
    }

    private func load(_ kind: ModelKind) async {
        let silence = [Float](repeating: 0, count: 32_000)
        switch kind {
        case .voz: _ = try? await voz()
        case .ear: _ = try? await ear.identify(samples: silence, sampleRate: 16_000, windows: 1)
        case .who: _ = try? await who.diarize(samples: silence, sampleRate: 16_000)
        case .align:
            _ = try? await align.refine([WordTiming(text: "a", start: 0.5, end: 0.8)], audio: silence,
                                        sampleRate: 16_000, languageCode: "en")
        case .uhm: _ = try? await uhm.analyze(samples: silence, sampleRate: 16_000)
        case .clear: _ = try? await clear.enhance(samples: silence, sampleRate: 16_000)
        }
    }

    func isDownloaded(_ kind: ModelKind) -> Bool {
        switch kind {
        case .voz: Voz.isDownloaded(directory: kind.directory.path)
        case .who: who.isDownloaded()
        case .ear: ear.isDownloaded()
        case .align: align.isDownloaded()
        case .uhm: uhm.isDownloaded()
        case .clear: clear.isDownloaded()
        }
    }

    func download(_ kind: ModelKind, progress: @escaping @Sendable (Double) -> Void) async throws {
        switch kind {
        case .voz: try await Voz.download(directory: kind.directory.path) { progress($0.fraction) }
        case .who: try await who.download(progress: progress)
        case .ear: try await ear.download(progress: progress)
        case .align: try await align.download(progress: progress)
        case .uhm: try await uhm.download(progress: progress)
        case .clear: try await clear.download(progress: progress)
        }
    }
}

/// Download state of every model, for onboarding and Settings.
@Observable
@MainActor
final class ModelManager {
    static let shared = ModelManager()

    var states: [ModelKind: ModelState] = [:]
    var isDownloading = false

    init() { refresh() }

    func refresh() {
        for kind in ModelKind.allCases where !isBusy(kind) {
            states[kind] = Engines.shared.isDownloaded(kind) ? .ready : .missing
        }
    }

    func state(_ kind: ModelKind) -> ModelState { states[kind] ?? .missing }

    func isBusy(_ kind: ModelKind) -> Bool {
        switch states[kind] {
        case .downloading, .preparing: true
        default: false
        }
    }

    var requiredReady: Bool { ModelKind.allCases.filter(\.isRequired).allSatisfy { state($0).isReady } }

    /// 0...1 across the required models, weighted by size.
    var requiredFraction: Double {
        let kinds = ModelKind.allCases.filter(\.isRequired)
        let total = kinds.reduce(0) { $0 + Double($1.approxMB ?? 1) }
        let done = kinds.reduce(0.0) { sum, kind in
            let weight = Double(kind.approxMB ?? 1)
            switch state(kind) {
            case .ready, .preparing: return sum + weight
            case .downloading(let f): return sum + weight * f
            default: return sum
            }
        }
        return total > 0 ? done / total : 0
    }

    func downloadRequired() async {
        await download(ModelKind.allCases.filter(\.isRequired))
    }

    func download(_ kinds: [ModelKind]) async {
        isDownloading = true
        defer { isDownloading = false }
        for kind in kinds where !state(kind).isReady {
            do { try await ensure(kind) } catch { states[kind] = .failed(error.localizedDescription) }
        }
        isDownloading = false
        await prepareDownloaded()
    }

    /// Downloads one model if needed. Voz is also loaded once so its one-time Neural Engine
    /// preparation happens here instead of during the first transcription.
    func ensure(_ kind: ModelKind) async throws {
        if state(kind).isReady { return }
        states[kind] = .downloading(0)
        try await Engines.shared.download(kind) { fraction in
            Task { @MainActor in
                if case .downloading = ModelManager.shared.states[kind] {
                    ModelManager.shared.states[kind] = .downloading(fraction)
                }
            }
        }
        states[kind] = .ready
    }

    var isPreparing = false
    var preparedCount = 0
    var preparingTotal = 0

    /// True until this build of the app has prepared its models once.
    var isFirstPreparation: Bool {
        UserDefaults.standard.string(forKey: "preparedBuild") != Self.build
    }

    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }

    /// Gets every downloaded model ready in the background, so the first file isn't slow.
    func prepareDownloaded() async {
        let kinds = ModelKind.allCases.filter { state($0).isReady && !Engines.shared.isWarm($0) }
        guard !kinds.isEmpty, !isPreparing else { return }
        isPreparing = true
        preparedCount = 0
        preparingTotal = kinds.count
        for kind in kinds {
            states[kind] = .preparing
            await Engines.shared.warmUp(kind)
            states[kind] = .ready
            preparedCount += 1
        }
        isPreparing = false
        UserDefaults.standard.set(Self.build, forKey: "preparedBuild")
    }

    func remove(_ kind: ModelKind) {
        try? FileManager.default.removeItem(at: kind.directory)
        states[kind] = .missing
    }

    func diskSize(_ kind: ModelKind) -> Int64 {
        guard let e = FileManager.default.enumerator(at: kind.directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
