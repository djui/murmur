#if os(macOS)
import AppKit
#endif
import Foundation
import MurmurCore

/// User preferences, read with `@AppStorage(AppSettings.x)` in views and `AppSettings.value` elsewhere.
enum AppSettings {
    static let copyFormat = "copyFormat"
    static let hideFillersInExport = "hideFillersInExport"
    static let enhanceNewProjects = "enhanceNewProjects"
    static let detectFillers = "detectFillers"
    static let autoTitle = "autoTitle"
    static let systemAudioSource = "systemAudioSource"
    static let markHotKey = "markHotKey"
    static let skippedOnboarding = "skippedOnboarding"
    static let knownProjects = "knownProjects"
    static let speakerScheme = "speakerScheme"
    static let hideRecorderFromSharing = "hideRecorderFromSharing"
    static let redactionStyle = "redactionStyle"
    /// Also settable at launch with `-appearance dark|light` (screenshots).
    static let appearance = "appearance"
    /// Single keys changed from their defaults, by action (see `ShortcutMap`).
    static let shortcuts = "shortcuts"
    static let settingsTab = "settingsTab"
    /// The combination for `markHotKey`, as JSON (see `HotKeyCombo`).
    static let markMomentKey = "markMomentKey"
    /// First uses that retire the window's how-to hints, across all projects.
    static let hasSelected = "hasSelected"
    static let hasMarked = "hasMarked"
    static let showProcessingInfo = "showProcessingInfo"
    /// Which inspector sections are unfolded, across all projects.
    static let showSummary = "showSummary"
    static let showSpeakers = "showSpeakers"
    static let showMarks = "showMarks"
    static let showPersonalDetails = "showPersonalDetails"
    static let showInspector = "showInspector"
    /// Where the timeline sits in the project window (see `TimelineLayout`).
    static let timelineLayout = "timelineLayout"
    /// iPhone and iPad: seconds the skip buttons jump (5, 10, 15 or 30), and whether the player shows time left.
    static let skipSeconds = "skipSeconds"
    static let showTimeLeft = "showTimeLeft"

    static func register() {
        UserDefaults.standard.register(defaults: [
            skipSeconds: 15,
            showTimeLeft: true,
            copyFormat: TextFormat.timestamps.rawValue,
            hideFillersInExport: true,
            enhanceNewProjects: false,
            detectFillers: true,
            autoTitle: true,
            systemAudioSource: "",
            markHotKey: true,
            hideRecorderFromSharing: true,
            redactionStyle: RedactionStyle.labels.rawValue,
            appearance: Appearance.system.rawValue,
        ])
    }

    static var copyFormatValue: TextFormat {
        TextFormat(rawValue: UserDefaults.standard.string(forKey: copyFormat) ?? "") ?? .timestamps
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    static var redactionStyleValue: RedactionStyle {
        RedactionStyle(rawValue: UserDefaults.standard.string(forKey: redactionStyle) ?? "") ?? .labels
    }

    /// Copy and export options that follow the user's settings.
    static var renderOptions: RenderOptions {
        RenderOptions(hideFillers: bool(hideFillersInExport), redactionStyle: redactionStyleValue)
    }
}

/// Light or dark windows, or whatever the system uses.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var current: Appearance {
        Appearance(rawValue: UserDefaults.standard.string(forKey: AppSettings.appearance) ?? "") ?? .system
    }

    #if os(macOS)
    /// Sets the appearance of every window, including panels and the menu bar extra.
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
    #endif
}
