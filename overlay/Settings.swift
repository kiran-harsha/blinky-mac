import Foundation

/// The two reminder frequencies, in minutes. Persisted as `key=value` lines in `Paths.config`.
/// A frequency of 0 disables that reminder.
struct Settings {
    var blinkFreqMin: Double = 1
    var lookawayFreqMin: Double = 20

    /// Reads the config file; a missing file, missing key, or an unparsable/negative value
    /// falls back to the default for that key.
    static func load(from path: String = Paths.config) -> Settings {
        var settings = Settings()
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return settings }
        for line in text.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, let value = Double(pair[1]), value >= 0 else { continue }
            switch pair[0] {
            case "blink_freq_min": settings.blinkFreqMin = value
            case "lookaway_freq_min": settings.lookawayFreqMin = value
            default: break
            }
        }
        return settings
    }
}
