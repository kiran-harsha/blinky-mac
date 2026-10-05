import AppKit

/// Full-screen transparent, click-through overlay: a blurred backdrop (shown during the
/// look-away reminder) behind a `ReminderView`, driven by a ~30fps timer that also polls
/// the events file for commands from the zsh plugin. Mirrors shihtzu-mac's `App.swift`.
final class App: NSObject, NSApplicationDelegate {
    private let fireOnLaunch: CLI.DemoReminder?

    var window: NSWindow!
    var blurView: NSVisualEffectView!
    var view: ReminderView!
    var timer: Timer?
    var statusItem: NSStatusItem!
    var hideItem: NSMenuItem!
    var lastTick = CACurrentMediaTime()
    var frame = 0
    var offset: UInt64 = 0
    var hidden = false

    init(fireOnLaunch: CLI.DemoReminder? = nil) {
        self.fireOnLaunch = fireOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSView(frame: .zero)
        blurView = NSVisualEffectView(frame: .zero)
        blurView.material = .fullScreenUI
        blurView.state = .active
        blurView.alphaValue = 0
        blurView.autoresizingMask = [.width, .height]
        container.addSubview(blurView)

        view = ReminderView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)

        window.contentView = container
        layoutWindow()
        window.orderFrontRegardless()

        NotificationCenter.default.addObserver(self, selector: #selector(layoutWindow),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "👁️"
        let menu = NSMenu()
        hideItem = NSMenuItem(title: "Hide reminders", action: #selector(toggleHidden), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)
        let quit = NSMenuItem(title: "Quit Blinky", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        let settings = Settings.load()
        view.scheduler.blinkFreqMin = settings.blinkFreqMin
        view.scheduler.lookawayFreqMin = settings.lookawayFreqMin

        offset = (try? FileManager.default.attributesOfItem(atPath: Paths.events)[.size] as? UInt64 ?? 0) ?? 0
        // A fresh launch always starts shown; clear any marker a previous run left behind.
        try? FileManager.default.removeItem(atPath: Paths.hidden)

        if let demo = fireOnLaunch {
            switch demo {
            case .blink: view.scheduler.blink.fire()
            case .lookaway: view.scheduler.lookAway.fire()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    @objc func layoutWindow() {
        guard let s = NSScreen.screens.first else { return }
        window.setFrame(s.frame, display: true)
        window.contentView?.frame = NSRect(origin: .zero, size: s.frame.size)
    }

    @objc func toggleHidden() { setHidden(!hidden) }

    func setHidden(_ h: Bool) {
        hidden = h
        hideItem.title = h ? "Show reminders" : "Hide reminders"
        if h {
            window.orderOut(nil)
            try? "1".write(toFile: Paths.hidden, atomically: true, encoding: .utf8)
        } else {
            window.orderFrontRegardless()
            try? FileManager.default.removeItem(atPath: Paths.hidden)
        }
    }

    @objc func quitApp() {
        try? FileManager.default.removeItem(atPath: Paths.pid)
        NSApp.terminate(nil)
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(0.1, now - lastTick))
        lastTick = now
        frame += 1
        if frame % 8 == 0 { pollEvents() }
        guard !hidden else { return }
        let wasActive = view.scheduler.isAnyActive
        view.scheduler.update(dt)
        blurView.alphaValue = view.scheduler.lookAway.alpha
        // Idle costs nothing beyond the poll tick above; redraw while a reminder animates,
        // plus one extra frame on the way back to idle so the last frame actually clears.
        if wasActive || view.scheduler.isAnyActive { view.needsDisplay = true }
    }

    func pollEvents() {
        guard let fh = FileHandle(forReadingAtPath: Paths.events) else { return }
        defer { try? fh.close() }
        let size = (try? FileManager.default.attributesOfItem(atPath: Paths.events)[.size] as? UInt64 ?? 0) ?? 0
        if size < offset { offset = 0 }
        guard size > offset else { return }
        try? fh.seek(toOffset: offset)
        let data = fh.readDataToEndOfFile()
        offset = size
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") { handle(String(line)) }
        if size > 65_536 { try? Data().write(to: URL(fileURLWithPath: Paths.events)); offset = 0 }
    }

    func handle(_ line: String) {
        let parts = line.split(separator: " ")
        switch parts.first {
        case "reload":
            let settings = Settings.load()
            view.scheduler.blinkFreqMin = settings.blinkFreqMin
            view.scheduler.lookawayFreqMin = settings.lookawayFreqMin
        case "hide": setHidden(true)
        case "show": setHidden(false)
        case "demo":
            if parts.count > 1 && parts[1] == "lookaway" { view.scheduler.lookAway.fire() }
            else { view.scheduler.blink.fire() }
        case "quit": quitApp()
        default: break
        }
    }
}
