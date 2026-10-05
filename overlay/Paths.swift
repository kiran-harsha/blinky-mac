import Foundation

/// Filesystem locations shared by the overlay and the zsh plugin.
enum Paths {
    static let root = FileManager.default.homeDirectoryForCurrentUser.path + "/.blinky"
    static let runDir = root + "/run"
    static let events = runDir + "/events"
    static let pid = runDir + "/pid"
    /// Present while reminders are hidden; lets `blinky status` report real app state
    /// instead of a per-shell variable, since every terminal shares this file.
    static let hidden = runDir + "/hidden"
    /// `key=value` lines (blink_freq_min, lookaway_freq_min). Written by the plugin, read by the overlay.
    static let config = root + "/config"
}
