// Blinky overlay — a borderless, click-through window that nudges the user to blink and
// look away. The zsh plugin talks to it through an events file. Mirrors shihtzu-mac's main.swift.
import AppKit

CLI.runIfRequested()

try? FileManager.default.createDirectory(atPath: Paths.runDir, withIntermediateDirectories: true)
if let s = try? String(contentsOfFile: Paths.pid, encoding: .utf8),
   let p = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)),
   p != getpid(), kill(p, 0) == 0 {
    exit(0)
}

signal(SIGHUP, SIG_IGN)
_ = setsid()
try? String(getpid()).write(toFile: Paths.pid, atomically: true, encoding: .utf8)
if !FileManager.default.fileExists(atPath: Paths.events) {
    FileManager.default.createFile(atPath: Paths.events, contents: nil)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App(fireOnLaunch: CLI.demoRequest())
app.delegate = delegate
app.run()
