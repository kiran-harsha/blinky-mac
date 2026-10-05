import Foundation

/// Filesystem locations shared by the overlay and the zsh plugin.
enum Paths {
    static let root = FileManager.default.homeDirectoryForCurrentUser.path + "/.blinky"
    static let runDir = root + "/run"
    static let events = runDir + "/events"
    static let pid = runDir + "/pid"
    /// `key=value` lines (blink_freq_min, lookaway_freq_min). Written by the plugin, read by the overlay.
    static let config = root + "/config"
}
