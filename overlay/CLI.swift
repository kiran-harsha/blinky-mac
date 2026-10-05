import Foundation

/// `--show` prints the current frequencies and exits. `--demo blink|lookaway` is read by
/// `main.swift` to fire that reminder immediately after the app launches (see spec's
/// Testing approach) — it does not exit by itself, since the animation needs a real window.
enum CLI {
    enum DemoReminder: String { case blink, lookaway }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// nil if `--demo` is absent, missing its value, or names an unrecognized reminder.
    static func demoRequest(_ args: [String] = CommandLine.arguments) -> DemoReminder? {
        guard let name = value(of: "--demo", in: args) else { return nil }
        return DemoReminder(rawValue: name)
    }

    /// Runs `--show` and exits; returns if no one-shot flag was given.
    static func runIfRequested(_ args: [String] = CommandLine.arguments) {
        if args.contains("--show") {
            let s = Settings.load()
            print("blink_freq_min=\(s.blinkFreqMin)\nlookaway_freq_min=\(s.lookawayFreqMin)")
            exit(0)
        }
    }
}
