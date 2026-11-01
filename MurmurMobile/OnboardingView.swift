import SwiftUI
import UIKit

/// First launch: download the models, once.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var models = ModelManager.shared
    @AppStorage(AppSettings.skippedOnboarding) private var skippedOnboarding = false

    private var required: [ModelKind] { ModelKind.allCases.filter(\.isRequired) }
    private var totalMB: Int { required.compactMap(\.approxMB).reduce(0, +) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VoicesMark()
                .frame(width: 92, height: 64)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Who said what, when").font(.title2.bold()).multilineTextAlignment(.center)
                Text("Murmur transcribes on this \(UIDevice.current.model) and tells the speakers apart. Nothing you open or record is uploaded.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(required) { kind in
                    HStack {
                        Text(kind.engine).font(.body.weight(.semibold)).frame(width: 56, alignment: .leading)
                        Text(kind.detail).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        status(kind)
                    }
                }
            }
            .padding()
            .background(.fill.quaternary, in: .rect(cornerRadius: 14))
            Spacer()
            if models.requiredReady {
                Button { dismiss() } label: { Text("Start").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else if models.isDownloading {
                ProgressView(value: models.requiredFraction) {
                    Text("Downloading models · \(Int(models.requiredFraction * 100))%").font(.subheadline)
                }
            } else {
                Button {
                    Task { await models.downloadRequired() }
                } label: {
                    Text("Download Models (\(totalMB) MB)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Not Now") { skippedOnboarding = true; dismiss() }
            }
            Text("Models come from Hugging Face. Use Wi-Fi if you can.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .interactiveDismissDisabled(models.isDownloading)
    }

    @ViewBuilder
    private func status(_ kind: ModelKind) -> some View {
        switch models.state(kind) {
        case .ready, .preparing: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .downloading(let f): Text("\(Int(f * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .missing: Text(kind.approxMB.map { "\($0) MB" } ?? "").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Murmur's mark: five waveform bars in the first three speaker colours, as on the app icon.
struct VoicesMark: View {
    @AppStorage(AppSettings.speakerScheme) private var schemeName = SpeakerScheme.vivid.rawValue

    var body: some View {
        let scheme = SpeakerScheme(rawValue: schemeName) ?? .vivid
        let bars: [(CGFloat, Int)] = [(0.36, 0), (0.72, 0), (1, 1), (0.6, 2), (0.4, 2)]
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(bars.count * 2 - 1)
            HStack(spacing: w) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule().fill(scheme.color(bars[i].1)).frame(width: w, height: geo.size.height * bars[i].0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
