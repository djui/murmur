import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Voice Memos (or any app) › Share › Murmur: keeps the recording for Murmur, which transcribes it on this device
/// the next time it is open.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.take(providers) }
    }
}

@Observable
@MainActor
final class ShareModel {
    enum State { case working, done([String]), failed(String) }
    var state = State.working

    func take(_ providers: [NSItemProvider]) async {
        var names: [String] = []
        for provider in providers {
            guard let type = [UTType.audio, .movie, .audiovisualContent].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) })
            else { continue }
            do {
                let name = try await keep(provider, type: type)
                names.append(name)
            } catch {
                state = .failed(error.localizedDescription)
                return
            }
        }
        state = names.isEmpty ? .failed("There’s no audio or video here for Murmur.") : .done(names)
    }

    /// Copies the file while the provider's temporary copy still exists.
    private func keep(_ provider: NSItemProvider, type: UTType) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                guard let url else { return continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
                let ext = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "m4a") : url.pathExtension
                let base = provider.suggestedName ?? url.deletingPathExtension().lastPathComponent
                let name = base.hasSuffix(".\(ext)") ? base : "\(base).\(ext)"
                do {
                    try SharedInbox.add(url, name: name)
                    continuation.resume(returning: (name as NSString).deletingPathExtension)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct ShareView: View {
    let model: ShareModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                switch model.state {
                case .working:
                    ProgressView()
                    Text("Adding to Murmur…").foregroundStyle(.secondary)
                case .done(let names):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                    Text(names.count == 1 ? "“\(names[0])” is in Murmur" : "\(names.count) recordings are in Murmur")
                        .font(.headline).multilineTextAlignment(.center)
                    Text("Open Murmur to transcribe it. Speakers are told apart and everything stays on this iPhone.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                    Text("Couldn’t add this to Murmur").font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Murmur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
    }
}
