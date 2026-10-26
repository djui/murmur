import Foundation

public enum Timecode {
    /// `mm:ss`, or `h:mm:ss` past an hour.
    public static func short(_ t: Double) -> String {
        let s = Int(max(0, t).rounded(.down))
        let h = s / 3600, m = (s / 60) % 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// `mm:ss.t`, or `h:mm:ss.t` past an hour.
    public static func precise(_ t: Double) -> String {
        let tenths = Int((max(0, t) * 10).rounded(.down))
        let s = tenths / 10
        let h = s / 3600, m = (s / 60) % 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d.%d", h, m, sec, tenths % 10)
            : String(format: "%02d:%02d.%d", m, sec, tenths % 10)
    }

    public static func srt(_ t: Double) -> String { clock(t, separator: ",") }
    public static func vtt(_ t: Double) -> String { clock(t, separator: ".") }

    static func clock(_ t: Double, separator: String) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        let h = ms / 3_600_000, m = (ms / 60_000) % 60, s = (ms / 1000) % 60
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, separator, ms % 1000)
    }
}
