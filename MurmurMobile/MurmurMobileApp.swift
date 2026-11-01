import AVFoundation
import MurmurCore
import SwiftUI

@main
struct MurmurMobileApp: App {
    @AppStorage(AppSettings.appearance) private var appearance = Appearance.system.rawValue

    init() {
        AppSettings.register()
        // Plays with the ringer switched off, like any media app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        ContinuedProcessing.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        }
    }
}

extension Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The library beside (iPad) or before (iPhone) the open project.
struct RootView: View {
    @State private var library = Library.shared
    @State private var models = ModelManager.shared
    @State private var selection: URL?
    @State private var showModels = false
    @AppStorage(AppSettings.skippedOnboarding) private var skippedOnboarding = false

    var body: some View {
        NavigationSplitView {
            LibraryView(selection: $selection)
        } detail: {
            if let selection {
                ProjectScreen(url: selection).id(selection)
            } else {
                ContentUnavailableView("No Project Open", systemImage: "waveform",
                                       description: Text("Open an audio or video file, or record one."))
            }
        }
        .onOpenURL { url in
            Task {
                do { selection = try await library.importMedia(url) } catch { library.error = error.localizedDescription }
            }
        }
        .fullScreenCover(isPresented: $showModels) { OnboardingView() }
        .onAppear {
            #if DEBUG
            // `-import <path>` opens a file at launch, for scripted runs and screenshots.
            if let path = UserDefaults.standard.string(forKey: "import") {
                Task {
                    do { selection = try await library.importMedia(URL(fileURLWithPath: path)) } catch { library.error = error.localizedDescription }
                }
            }
            #endif
            if !models.requiredReady && !skippedOnboarding { showModels = true }
            Task {
                await models.updateOutdated()
                await models.prepareDownloaded()
            }
        }
        .alert("Murmur couldn’t open the file", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.error ?? "")
        }
    }
}
