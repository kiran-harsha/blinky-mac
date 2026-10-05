# Blinky Eye-Care Reminder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Blinky, a macOS menu-bar companion that fires a "blink" nudge every N minutes and a "look away" (20-20-20) nudge every M minutes, both configurable from the terminal, structured exactly like the `shihtzu-mac` reference project (native Swift/AppKit overlay + zsh plugin + install script, zero external dependencies).

**Architecture:** A single detached, click-through, full-screen `NSWindow` (`.accessory` activation policy, no Dock icon) is driven by one ~30fps `Timer` that advances two independent pure state machines (`BlinkReminder`, `LookAwayReminder`) coordinated by a `ReminderScheduler`, and polls an events file the way `shihtzu-mac`'s dog does. The zsh plugin (`blinky.plugin.zsh`) starts the overlay on shell open, writes frequencies to a config file, and sends control lines (`reload`/`hide`/`show`/`quit`/`demo ...`) through the events file. `install.sh` compiles the overlay with `swiftc` and wires the plugin into `~/.zshrc`.

**Tech Stack:** Swift 6 + AppKit/CoreGraphics (no third-party dependencies), zsh, `swiftc` for the shipped binary, a SwiftPM `Package.swift` used only to run `swift test` against the pure-logic files (never used by `install.sh`, which keeps compiling `overlay/*.swift` directly with `swiftc`, exactly like `shihtzu-mac`).

**Spec:** `docs/superpowers/specs/2026-10-05-blinky-eye-care-reminder-design.md`

**Reference implementation (same architecture, read when a task says "mirrors X"):** `/Users/harshakiran/shihtzu-mac` — particularly `overlay/main.swift`, `overlay/App.swift`, `overlay/Paths.swift`, `overlay/Dog.swift`, `terminal-animals.plugin.zsh`, `install.sh`.

## Global Constraints

- macOS only, no iOS/cross-platform support (same as shihtzu-mac).
- No external dependencies — native Swift/AppKit/CoreGraphics only; `Package.swift` declares zero package dependencies.
- No notifications/sound — both reminders are purely visual.
- No analytics, update checker, or settings UI — terminal commands only.
- No idle/activity-based pausing — a frequency of `0` is the only escape hatch to disable a reminder.
- Both reminders must never block mouse clicks (`window.ignoresMouseEvents = true`) and never steal keyboard focus.
- The app must keep running and keep firing reminders after every terminal window closes, until the user explicitly quits it (`setsid()` detach, pid-file single-instance guard, `.accessory` activation policy).
- Default frequencies: blink every 1 minute, look-away every 20 minutes (the 20-20-20 rule).
- Only one reminder animates at a time; if both are due simultaneously, Blink Reminder shows first and Look-Away Reminder fires immediately after it finishes (sequential queue, no overlap).
- Config/control plane mirrors shihtzu-mac exactly, renamed: `~/.blinky/{run/events,run/pid,config}`, `blink_freq_min=`/`lookaway_freq_min=` keys, same events-file protocol shape (`reload`/`hide`/`show`/`quit`/`demo <name>`).

## Review Focus

- A config file with a malformed (non-numeric) frequency value — the affected reminder must fall back to its default rather than crashing or silently becoming `0`. Pinned by `SettingsTests.testFallsBackToDefaultOnMalformedValue` (Task 1).
- A frequency explicitly set to `0` — that reminder must never fire again; it is not "fires every 0 minutes." Pinned by `SettingsTests.testZeroIsAValidValue` (Task 1) and `ReminderSchedulerTests.testZeroFrequencyNeverFires` (Task 4).
- A negative frequency value in the config — must be treated as invalid and fall back to the default, not treated as "already elapsed" (which would fire immediately and repeatedly). Pinned by `SettingsTests.testFallsBackToDefaultOnNegativeValue` (Task 1).
- Both reminders becoming due in the same tick — Blink must fire first and Look-Away must fire immediately after Blink's animation completes, never simultaneously. Pinned by `ReminderSchedulerTests.testBlinkFiresFirstWhenBothDueTogether` and `testLookAwayFiresRightAfterBlinkFinishes` (Task 4).
- `blinky blink-freq` / `blinky lookaway-freq` called with no argument — must print the current value without modifying the config file. Pinned by `Tests/plugin_test.sh`'s "get does not mutate" assertions (Task 8).

---

## Task 1: Project scaffold, Paths, Settings

**Files:**
- Create: `Package.swift`
- Create: `overlay/Paths.swift`
- Create: `overlay/Settings.swift`
- Test: `Tests/BlinkyTests/SettingsTests.swift`

**Interfaces:**
- Produces: `enum Paths { static let root, runDir, events, pid, config: String }`
- Produces: `struct Settings { var blinkFreqMin: Double = 1; var lookawayFreqMin: Double = 20; static func load(from path: String = Paths.config) -> Settings }`

- [ ] **Step 1: Write the failing test**

Create `Tests/BlinkyTests/SettingsTests.swift`:

```swift
import XCTest
@testable import BlinkyCore

final class SettingsTests: XCTestCase {
    private func writeConfig(_ text: String) -> String {
        let path = NSTemporaryDirectory() + "blinky-config-\(UUID().uuidString)"
        try! text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testDefaultsWhenFileMissing() {
        let s = Settings.load(from: "/nonexistent/path/\(UUID().uuidString)")
        XCTAssertEqual(s.blinkFreqMin, 1)
        XCTAssertEqual(s.lookawayFreqMin, 20)
    }

    func testReadsValidFrequencies() {
        let path = writeConfig("blink_freq_min=5\nlookaway_freq_min=30\n")
        let s = Settings.load(from: path)
        XCTAssertEqual(s.blinkFreqMin, 5)
        XCTAssertEqual(s.lookawayFreqMin, 30)
    }

    func testFallsBackToDefaultOnMalformedValue() {
        let path = writeConfig("blink_freq_min=notanumber\n")
        let s = Settings.load(from: path)
        XCTAssertEqual(s.blinkFreqMin, 1)
    }

    func testFallsBackToDefaultOnNegativeValue() {
        let path = writeConfig("lookaway_freq_min=-5\n")
        let s = Settings.load(from: path)
        XCTAssertEqual(s.lookawayFreqMin, 20)
    }

    func testZeroIsAValidValue() {
        let path = writeConfig("blink_freq_min=0\n")
        let s = Settings.load(from: path)
        XCTAssertEqual(s.blinkFreqMin, 0)
    }
}
```

Also create `Package.swift` (needed before any test can run):

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Blinky",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "BlinkyCore", path: "overlay", exclude: ["main.swift"]),
        .testTarget(name: "BlinkyTests", dependencies: ["BlinkyCore"]),
    ]
)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsTests`
Expected: FAIL to build — `cannot find 'Settings' in scope` (and `overlay/main.swift` has not been created yet either, which is fine: `Package.swift` excludes it so its absence doesn't matter yet).

- [ ] **Step 3: Write minimal implementation**

Create `overlay/Paths.swift`:

```swift
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
```

Create `overlay/Settings.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsTests`
Expected: PASS, 5/5 tests.

- [ ] **Step 5: Commit**

```bash
git add Package.swift overlay/Paths.swift overlay/Settings.swift Tests/BlinkyTests/SettingsTests.swift
git commit -m "feat: add Settings/Paths with SwiftPM test scaffold"
```

---

## Task 2: BlinkReminder state machine

**Files:**
- Create: `overlay/BlinkReminder.swift`
- Test: `Tests/BlinkyTests/BlinkReminderTests.swift`

**Interfaces:**
- Produces: `final class BlinkReminder { var isActive: Bool { get }; var eyeClosedAmount: CGFloat { get }; var alpha: CGFloat { get }; func fire(); func update(_ dt: CGFloat) }`

- [ ] **Step 1: Write the failing test**

Create `Tests/BlinkyTests/BlinkReminderTests.swift`. Every `update()` call below carries a `dt` that lands exactly on one phase boundary — never two boundaries in a single call, since `update()` only evaluates one phase transition per call (matching how `App`'s ~30fps timer will drive it in Task 7, always with small per-frame `dt`):

```swift
import XCTest
@testable import BlinkyCore

final class BlinkReminderTests: XCTestCase {
    func testIdleByDefault() {
        let r = BlinkReminder()
        XCTAssertFalse(r.isActive)
        XCTAssertEqual(r.alpha, 0)
    }

    func testFireActivatesAndRunsFullCycle() {
        let r = BlinkReminder()
        r.fire()
        XCTAssertTrue(r.isActive)
        r.update(1.4)  // two blinks done (4 half-cycles of 0.35s) -> now fading out
        XCTAssertTrue(r.isActive)
        r.update(0.3)  // fade-out done
        XCTAssertFalse(r.isActive)
    }

    func testEyesCloseAndReopenTwice() {
        let r = BlinkReminder()
        r.fire()
        XCTAssertEqual(r.eyeClosedAmount, 0, accuracy: 0.001)
        r.update(0.35)  // first half-cycle: fully closed
        XCTAssertEqual(r.eyeClosedAmount, 1, accuracy: 0.01)
        r.update(0.35)  // second half-cycle: open again (first blink done)
        XCTAssertEqual(r.eyeClosedAmount, 0, accuracy: 0.01)
    }

    func testFadesOutAfterAnimating() {
        let r = BlinkReminder()
        r.fire()
        r.update(1.4)
        XCTAssertEqual(r.alpha, 1, accuracy: 0.01)
        r.update(0.15)  // halfway through the 0.3s fade-out
        XCTAssertEqual(r.alpha, 0.5, accuracy: 0.05)
    }

    func testFireWhileActiveIsIgnored() {
        let r = BlinkReminder()
        r.fire()
        r.update(0.1)
        let before = r.eyeClosedAmount
        r.fire()  // no-op: still mid-animation
        XCTAssertEqual(r.eyeClosedAmount, before, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BlinkReminderTests`
Expected: FAIL to build — `cannot find 'BlinkReminder' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `overlay/BlinkReminder.swift`:

```swift
import CoreGraphics

/// Blink reminder: two blinks then a fade-out, driven by `update(_:)`. Pure state, no AppKit,
/// so it can be unit tested and reused by `Smiley`'s drawing code without a window.
final class BlinkReminder {
    private enum Phase { case idle, animating, fadingOut }

    private static let halfCycle: CGFloat = 0.35       // ~350ms per half-cycle
    private static let blinkDuration: CGFloat = halfCycle * 4  // two full blinks ≈ 1.4s
    private static let fadeDuration: CGFloat = 0.3

    private var phase: Phase = .idle
    private var t: CGFloat = 0

    var isActive: Bool { phase != .idle }

    /// Starts the animation; a no-op while already animating.
    func fire() {
        guard phase == .idle else { return }
        phase = .animating
        t = 0
    }

    func update(_ dt: CGFloat) {
        guard phase != .idle else { return }
        t += dt
        switch phase {
        case .animating:
            if t >= Self.blinkDuration { phase = .fadingOut; t = 0 }
        case .fadingOut:
            if t >= Self.fadeDuration { phase = .idle; t = 0 }
        case .idle:
            break
        }
    }

    /// 0 = eyes open, 1 = eyes fully closed; cycles closed/open twice during the animation.
    var eyeClosedAmount: CGFloat {
        guard phase == .animating else { return 0 }
        let half = Self.halfCycle
        let cycle = t.truncatingRemainder(dividingBy: half * 2)
        return cycle < half ? cycle / half : 1 - (cycle - half) / half
    }

    /// 1 = fully visible, 0 = fully faded.
    var alpha: CGFloat {
        switch phase {
        case .idle: return 0
        case .animating: return 1
        case .fadingOut: return 1 - min(1, t / Self.fadeDuration)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BlinkReminderTests`
Expected: PASS, 5/5 tests.

- [ ] **Step 5: Commit**

```bash
git add overlay/BlinkReminder.swift Tests/BlinkyTests/BlinkReminderTests.swift
git commit -m "feat: add BlinkReminder state machine"
```

---

## Task 3: LookAwayReminder state machine

**Files:**
- Create: `overlay/LookAwayReminder.swift`
- Test: `Tests/BlinkyTests/LookAwayReminderTests.swift`

**Interfaces:**
- Produces: `final class LookAwayReminder { enum Direction { case left, right, up, down }; var isActive: Bool { get }; var currentDirection: Direction? { get }; var lookAmount: CGFloat { get }; var alpha: CGFloat { get }; func fire(); func update(_ dt: CGFloat) }`

- [ ] **Step 1: Write the failing test**

Create `Tests/BlinkyTests/LookAwayReminderTests.swift`. As in Task 2, every `update()` call lands exactly on one phase boundary — never combine two boundaries (e.g. fade-in + a leg) into a single call:

```swift
import XCTest
@testable import BlinkyCore

final class LookAwayReminderTests: XCTestCase {
    func testIdleByDefault() {
        let r = LookAwayReminder()
        XCTAssertFalse(r.isActive)
        XCTAssertNil(r.currentDirection)
    }

    func testFiresThroughFourDirectionsInOrder() {
        let r = LookAwayReminder()
        r.fire()
        r.update(0.4)  // fade-in done -> looking, leg 0
        XCTAssertEqual(r.currentDirection, .left)
        r.update(1.0)  // leg 0 done -> leg 1
        XCTAssertEqual(r.currentDirection, .right)
        r.update(1.0)
        XCTAssertEqual(r.currentDirection, .up)
        r.update(1.0)
        XCTAssertEqual(r.currentDirection, .down)
    }

    func testCompletesFullCycleAndReturnsToIdle() {
        let r = LookAwayReminder()
        r.fire()
        r.update(0.4)  // fade-in -> leg 0 (left)
        r.update(1.0)  // -> leg 1 (right)
        r.update(1.0)  // -> leg 2 (up)
        r.update(1.0)  // -> leg 3 (down)
        r.update(1.0)  // leg 3 done -> fading out
        XCTAssertTrue(r.isActive)
        XCTAssertNil(r.currentDirection)
        r.update(0.4)  // fade-out done -> idle
        XCTAssertFalse(r.isActive)
    }

    func testAlphaFadesInThenHoldsAtFullVisibility() {
        let r = LookAwayReminder()
        r.fire()
        XCTAssertEqual(r.alpha, 0, accuracy: 0.001)
        r.update(0.2)  // halfway through the 0.4s fade-in
        XCTAssertEqual(r.alpha, 0.5, accuracy: 0.05)
        r.update(0.2)  // fade-in done -> looking, fully visible
        XCTAssertEqual(r.alpha, 1, accuracy: 0.01)
    }

    func testFireWhileActiveIsIgnored() {
        let r = LookAwayReminder()
        r.fire()
        r.update(0.4)
        r.fire()  // no-op: still mid-animation
        XCTAssertEqual(r.currentDirection, .left)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LookAwayReminderTests`
Expected: FAIL to build — `cannot find 'LookAwayReminder' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `overlay/LookAwayReminder.swift`:

```swift
import CoreGraphics

/// Look-away (20-20-20) reminder: blur+smiley fade in, four 1s look-direction legs,
/// then fade out. Pure state, no AppKit — same reasoning as `BlinkReminder`.
final class LookAwayReminder {
    enum Direction { case left, right, up, down }
    private enum Phase { case idle, fadingIn, looking, fadingOut }

    private static let fadeInDuration: CGFloat = 0.4
    private static let legDuration: CGFloat = 1.0
    private static let legs: [Direction] = [.left, .right, .up, .down]
    private static let fadeOutDuration: CGFloat = 0.4

    private var phase: Phase = .idle
    private var t: CGFloat = 0
    private var legIndex = 0

    var isActive: Bool { phase != .idle }

    /// Starts the animation; a no-op while already animating.
    func fire() {
        guard phase == .idle else { return }
        phase = .fadingIn
        t = 0
        legIndex = 0
    }

    func update(_ dt: CGFloat) {
        guard phase != .idle else { return }
        t += dt
        switch phase {
        case .fadingIn:
            if t >= Self.fadeInDuration { phase = .looking; t = 0 }
        case .looking:
            if t >= Self.legDuration {
                t = 0
                legIndex += 1
                if legIndex >= Self.legs.count { phase = .fadingOut }
            }
        case .fadingOut:
            if t >= Self.fadeOutDuration { phase = .idle; t = 0 }
        case .idle:
            break
        }
    }

    var currentDirection: Direction? {
        phase == .looking ? Self.legs[legIndex] : nil
    }

    /// Unit amount the pupil should shift toward `currentDirection`; 0 outside the looking phase.
    var lookAmount: CGFloat { phase == .looking ? 1 : 0 }

    /// 1 = fully visible, 0 = fully hidden; shared by the blur backdrop and the smiley.
    var alpha: CGFloat {
        switch phase {
        case .idle: return 0
        case .fadingIn: return min(1, t / Self.fadeInDuration)
        case .looking: return 1
        case .fadingOut: return 1 - min(1, t / Self.fadeOutDuration)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LookAwayReminderTests`
Expected: PASS, 5/5 tests.

- [ ] **Step 5: Commit**

```bash
git add overlay/LookAwayReminder.swift Tests/BlinkyTests/LookAwayReminderTests.swift
git commit -m "feat: add LookAwayReminder state machine"
```

---

## Task 4: ReminderScheduler

**Files:**
- Create: `overlay/ReminderScheduler.swift`
- Test: `Tests/BlinkyTests/ReminderSchedulerTests.swift`

**Interfaces:**
- Consumes: `BlinkReminder` (`fire()`, `update(_:)`, `isActive`) and `LookAwayReminder` (`fire()`, `update(_:)`, `isActive`) from Tasks 2–3.
- Produces: `final class ReminderScheduler { let blink: BlinkReminder; let lookAway: LookAwayReminder; var blinkFreqMin: Double = 1; var lookawayFreqMin: Double = 20; var isAnyActive: Bool { get }; func update(_ dt: CGFloat) }`

- [ ] **Step 1: Write the failing test**

Create `Tests/BlinkyTests/ReminderSchedulerTests.swift`:

```swift
import XCTest
@testable import BlinkyCore

final class ReminderSchedulerTests: XCTestCase {
    func testFiresBlinkWhenItsIntervalElapses() {
        let s = ReminderScheduler()
        s.blinkFreqMin = 1  // 60s
        s.lookawayFreqMin = 0
        for _ in 0..<59 { s.update(1) }
        XCTAssertFalse(s.blink.isActive)
        s.update(1)  // 60s total
        XCTAssertTrue(s.blink.isActive)
    }

    func testZeroFrequencyNeverFires() {
        let s = ReminderScheduler()
        s.blinkFreqMin = 0
        s.lookawayFreqMin = 0
        for _ in 0..<10_000 { s.update(1) }
        XCTAssertFalse(s.blink.isActive)
        XCTAssertFalse(s.lookAway.isActive)
    }

    func testBlinkFiresFirstWhenBothDueTogether() {
        let s = ReminderScheduler()
        s.blinkFreqMin = 1       // 60s
        s.lookawayFreqMin = 1    // 60s, due at the same tick
        for _ in 0..<60 { s.update(1) }
        XCTAssertTrue(s.blink.isActive)
        XCTAssertFalse(s.lookAway.isActive)
    }

    func testLookAwayFiresRightAfterBlinkFinishes() {
        let s = ReminderScheduler()
        s.blinkFreqMin = 1
        s.lookawayFreqMin = 1
        for _ in 0..<60 { s.update(1) }  // both due; blink fires first
        XCTAssertTrue(s.blink.isActive)
        var guardCount = 0
        while s.blink.isActive && guardCount < 1000 {
            s.update(1.0 / 30)  // drain blink's ~1.7s animation in small, boundary-safe steps
            guardCount += 1
        }
        XCTAssertFalse(s.blink.isActive)
        XCTAssertTrue(s.lookAway.isActive)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReminderSchedulerTests`
Expected: FAIL to build — `cannot find 'ReminderScheduler' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `overlay/ReminderScheduler.swift`:

```swift
import CoreGraphics

/// Owns both reminder timers and state machines, and enforces the "only one animates
/// at a time" rule: if both become due in the same tick, Blink fires first and Look-Away
/// stays pending, firing the instant Blink returns to idle.
final class ReminderScheduler {
    let blink = BlinkReminder()
    let lookAway = LookAwayReminder()

    /// Minutes; 0 disables that reminder.
    var blinkFreqMin: Double = 1
    var lookawayFreqMin: Double = 20

    private var blinkElapsed: CGFloat = 0
    private var lookAwayElapsed: CGFloat = 0
    private var lookAwayPending = false

    var isAnyActive: Bool { blink.isActive || lookAway.isActive }

    func update(_ dt: CGFloat) {
        blink.update(dt)
        lookAway.update(dt)

        if blinkFreqMin > 0 {
            blinkElapsed += dt
            if blinkElapsed >= CGFloat(blinkFreqMin * 60) && !isAnyActive {
                blinkElapsed = 0
                blink.fire()
            }
        }

        if lookawayFreqMin > 0 {
            lookAwayElapsed += dt
            if lookAwayElapsed >= CGFloat(lookawayFreqMin * 60) {
                lookAwayElapsed = 0
                lookAwayPending = true
            }
        }

        if lookAwayPending && !isAnyActive {
            lookAwayPending = false
            lookAway.fire()
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ReminderSchedulerTests`
Expected: PASS, 4/4 tests.

- [ ] **Step 5: Commit**

```bash
git add overlay/ReminderScheduler.swift Tests/BlinkyTests/ReminderSchedulerTests.swift
git commit -m "feat: add ReminderScheduler sequencing blink and look-away"
```

---

## Task 5: CLI argument parsing

**Files:**
- Create: `overlay/CLI.swift`
- Test: `Tests/BlinkyTests/CLITests.swift`

**Interfaces:**
- Consumes: `Settings.load() -> Settings` from Task 1.
- Produces: `enum CLI { enum DemoReminder: String { case blink, lookaway }; static func demoRequest(_ args: [String] = CommandLine.arguments) -> DemoReminder?; static func runIfRequested(_ args: [String] = CommandLine.arguments) }`

- [ ] **Step 1: Write the failing test**

Create `Tests/BlinkyTests/CLITests.swift`. Only `demoRequest` is tested here — `runIfRequested` calls `exit(0)` on `--show` and must never be called from a test process:

```swift
import XCTest
@testable import BlinkyCore

final class CLITests: XCTestCase {
    func testParsesBlinkDemoRequest() {
        XCTAssertEqual(CLI.demoRequest(["overlay", "--demo", "blink"]), .blink)
    }

    func testParsesLookawayDemoRequest() {
        XCTAssertEqual(CLI.demoRequest(["overlay", "--demo", "lookaway"]), .lookaway)
    }

    func testNoDemoFlagReturnsNil() {
        XCTAssertNil(CLI.demoRequest(["overlay"]))
    }

    func testUnrecognizedDemoNameReturnsNil() {
        XCTAssertNil(CLI.demoRequest(["overlay", "--demo", "nonsense"]))
    }

    func testDemoFlagMissingValueReturnsNil() {
        XCTAssertNil(CLI.demoRequest(["overlay", "--demo"]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CLITests`
Expected: FAIL to build — `cannot find 'CLI' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `overlay/CLI.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CLITests`
Expected: PASS, 5/5 tests.

- [ ] **Step 5: Commit**

```bash
git add overlay/CLI.swift Tests/BlinkyTests/CLITests.swift
git commit -m "feat: add CLI --show/--demo parsing"
```

---

## Task 6: Smiley drawing

**Files:**
- Create: `overlay/Smiley.swift`
- Test: `Tests/BlinkyTests/SmileyTests.swift`

**Interfaces:**
- Consumes: `LookAwayReminder.Direction` from Task 3.
- Produces: `enum Smiley { static let radius: CGFloat; static func draw(_ c: CGContext, at center: CGPoint, eyeClosedAmount: CGFloat = 0, lookDirection: LookAwayReminder.Direction? = nil, lookAmount: CGFloat = 0, alpha: CGFloat) }`

This is the one drawing-only file (no behavioral state, same role as shihtzu-mac's `DogDrawing.swift`, which has no unit tests in the reference project — only the visual `Snapshot.swift` contact sheets). It gets exactly one kind of automated test, modeled on that same `Snapshot.swift` technique: render into an offscreen `NSBitmapImageRep` (no window needed) and assert on specific pixels, so a totally blank or crashing `draw` is caught without needing a human to look at it. Actual visual quality is checked by eye later, via the `--demo` flags built in Task 7.

- [ ] **Step 1: Write the failing test**

Create `Tests/BlinkyTests/SmileyTests.swift`:

```swift
import XCTest
import AppKit
@testable import BlinkyCore

final class SmileyTests: XCTestCase {
    private func renderPixel(at point: NSPoint, eyeClosedAmount: CGFloat = 0,
                              lookDirection: LookAwayReminder.Direction? = nil,
                              lookAmount: CGFloat = 0, alpha: CGFloat = 1) -> NSColor? {
        let size = 200
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        Smiley.draw(ctx.cgContext, at: NSPoint(x: size / 2, y: size / 2), eyeClosedAmount: eyeClosedAmount,
                    lookDirection: lookDirection, lookAmount: lookAmount, alpha: alpha)
        NSGraphicsContext.restoreGraphicsState()
        return rep.colorAt(x: Int(point.x), y: Int(point.y))
    }

    func testFaceIsOpaqueAtCenter() {
        let color = renderPixel(at: NSPoint(x: 100, y: 100))
        XCTAssertNotNil(color)
        XCTAssertGreaterThan(color!.alphaComponent, 0.9)
    }

    func testFullyTransparentAtZeroAlpha() {
        let color = renderPixel(at: NSPoint(x: 100, y: 100), alpha: 0)
        XCTAssertNotNil(color)
        XCTAssertLessThan(color!.alphaComponent, 0.05)
    }

    func testClosedEyeHidesTheWhiteSclera() {
        // Sample inside the eye's white sclera but outside the pupil, where a closed eye
        // (drawn as a thin line, no fill) shows the face colour instead of white.
        let eyeCenterX = 100 - Int(Smiley.radius * 0.4)
        let eyeCenterY = 100 + Int(Smiley.radius * 0.25)
        let sampleX = eyeCenterX + Int(Smiley.radius * 0.3 / 2) - 2
        let open = renderPixel(at: NSPoint(x: sampleX, y: eyeCenterY), eyeClosedAmount: 0)
        let closed = renderPixel(at: NSPoint(x: sampleX, y: eyeCenterY), eyeClosedAmount: 1)
        XCTAssertGreaterThan(open?.blueComponent ?? 0, 0.8, "open eye's white sclera should be visible")
        XCTAssertLessThan(closed?.blueComponent ?? 1, 0.8, "closed eye should not show the white sclera")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SmileyTests`
Expected: FAIL to build — `cannot find 'Smiley' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `overlay/Smiley.swift`:

```swift
import AppKit

/// Draws the smiley: a circular face, two eyes (open/closed/looking), and a fixed smile.
/// Pure drawing function — all animation state lives in `BlinkReminder`/`LookAwayReminder`.
enum Smiley {
    static let radius: CGFloat = 70

    private static let faceFill = NSColor(red: 1, green: 0.84, blue: 0.2, alpha: 1)
    private static let ink = NSColor(red: 0.6, green: 0.45, blue: 0.05, alpha: 1)
    private static let pupilColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)

    /// - eyeClosedAmount: 0 = open, 1 = fully closed (driven by the blink reminder)
    /// - lookDirection/lookAmount: pupil offset toward a direction (driven by the look-away reminder)
    static func draw(_ c: CGContext, at center: CGPoint, eyeClosedAmount: CGFloat = 0,
                      lookDirection: LookAwayReminder.Direction? = nil, lookAmount: CGFloat = 0,
                      alpha: CGFloat) {
        c.saveGState()
        c.setAlpha(alpha)
        c.translateBy(x: center.x, y: center.y)

        c.setFillColor(faceFill.cgColor)
        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(3)
        let face = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        c.fillEllipse(in: face)
        c.strokeEllipse(in: face)

        let eyeDX: CGFloat = radius * 0.4, eyeY: CGFloat = radius * 0.25
        for ex in [-eyeDX, eyeDX] {
            drawEye(c, at: CGPoint(x: ex, y: eyeY), closedAmount: eyeClosedAmount,
                    direction: lookDirection, lookAmount: lookAmount)
        }

        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(4)
        c.setLineCap(.round)
        c.beginPath()
        c.move(to: CGPoint(x: -radius * 0.4, y: -radius * 0.25))
        c.addQuadCurve(to: CGPoint(x: radius * 0.4, y: -radius * 0.25), control: CGPoint(x: 0, y: -radius * 0.6))
        c.strokePath()

        c.restoreGState()
    }

    private static func drawEye(_ c: CGContext, at p: CGPoint, closedAmount: CGFloat,
                                 direction: LookAwayReminder.Direction?, lookAmount: CGFloat) {
        let eyeW: CGFloat = radius * 0.3
        let eyeH = eyeW * (1 - closedAmount)
        if eyeH < 1 {
            c.setStrokeColor(NSColor(red: 0.3, green: 0.2, blue: 0.05, alpha: 1).cgColor)
            c.setLineWidth(3)
            c.setLineCap(.round)
            c.beginPath()
            c.move(to: CGPoint(x: p.x - eyeW / 2, y: p.y))
            c.addLine(to: CGPoint(x: p.x + eyeW / 2, y: p.y))
            c.strokePath()
            return
        }
        c.setFillColor(NSColor.white.cgColor)
        c.fillEllipse(in: CGRect(x: p.x - eyeW / 2, y: p.y - eyeH / 2, width: eyeW, height: eyeH))

        var pupil = p
        let shift = radius * 0.1 * lookAmount
        switch direction {
        case .left: pupil.x -= shift
        case .right: pupil.x += shift
        case .up: pupil.y += shift
        case .down: pupil.y -= shift
        case nil: break
        }
        c.setFillColor(pupilColor.cgColor)
        let pupilSize = eyeW * 0.5
        c.fillEllipse(in: CGRect(x: pupil.x - pupilSize / 2, y: pupil.y - pupilSize / 2,
                                  width: pupilSize, height: pupilSize))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SmileyTests`
Expected: PASS, 3/3 tests.

- [ ] **Step 5: Commit**

```bash
git add overlay/Smiley.swift Tests/BlinkyTests/SmileyTests.swift
git commit -m "feat: add Smiley drawing"
```

---

## Task 7: ReminderView, App, main.swift (overlay assembly)

**Files:**
- Create: `overlay/ReminderView.swift`
- Create: `overlay/App.swift`
- Create: `overlay/main.swift`

**Interfaces:**
- Consumes: `ReminderScheduler` (Task 4), `Smiley.draw` (Task 6), `CLI.demoRequest`/`CLI.runIfRequested` (Task 5), `Settings.load`/`Paths` (Task 1).
- Produces: the compiled overlay process's runtime behavior (pid file, events-file protocol, menu-bar item) — nothing here is imported by a later Swift task.

This task is AppKit windowing/process glue: an `NSWindow`, a real `Timer`, a real menu-bar item, a detaching process. None of that is unit-testable without a live window server, and shihtzu-mac's equivalent files (`App.swift`, `main.swift`) have no automated tests either — only its manual verification checklist. This task follows that precedent: it is verified by actually building and running the binary (an automated smoke test proving it launches, writes its pid file, and responds to `quit` without crashing) plus a checklist of things that need a human's eyes, carried over verbatim from the spec's own Testing approach section.

**`BlinkyCore` is excluded from this task's `swift test` run** — these three files are AppKit-only glue with no new pure logic, so there is nothing here for XCTest to assert on; `main.swift` is excluded from the `BlinkyCore` library target entirely (SwiftPM only allows top-level executable statements in a target's designated main file, and `BlinkyCore` is a library).

- [ ] **Step 1: Write `overlay/ReminderView.swift`**

```swift
import AppKit

/// Draws the smiley for whichever reminder is currently active. The look-away blur backdrop
/// is a separate `NSVisualEffectView` owned by `App`, layered behind this view.
final class ReminderView: NSView {
    let scheduler = ReminderScheduler()
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.clear(bounds)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if scheduler.blink.isActive {
            Smiley.draw(c, at: center, eyeClosedAmount: scheduler.blink.eyeClosedAmount, alpha: scheduler.blink.alpha)
        } else if scheduler.lookAway.isActive {
            Smiley.draw(c, at: center, lookDirection: scheduler.lookAway.currentDirection,
                        lookAmount: scheduler.lookAway.lookAmount, alpha: scheduler.lookAway.alpha)
        }
    }
}
```

- [ ] **Step 2: Write `overlay/App.swift`**

```swift
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
        if h { window.orderOut(nil) } else { window.orderFrontRegardless() }
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
```

- [ ] **Step 3: Write `overlay/main.swift`**

```swift
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
```

- [ ] **Step 4: Build and smoke-test the real binary**

Run:

```bash
swiftc -O -o /tmp/blinky-overlay-smoketest overlay/*.swift -framework AppKit
```

Expected: exits 0, `/tmp/blinky-overlay-smoketest` exists.

Then, against the real `~/.blinky` (there is no installed Blinky yet, so this is safe — the last line cleans up fully):

```bash
rm -rf ~/.blinky
/tmp/blinky-overlay-smoketest --show
```

Expected: prints `blink_freq_min=1.0\nlookaway_freq_min=20.0` (defaults, since `~/.blinky/config` doesn't exist) and exits — this path never creates `~/.blinky` or a window, matching `CLI.runIfRequested()` running before the pid-file/window setup.

```bash
/tmp/blinky-overlay-smoketest --demo blink &
sleep 1
test -f ~/.blinky/run/pid && echo "pid file present"
kill -0 "$(cat ~/.blinky/run/pid)" && echo "process alive"
echo quit >> ~/.blinky/run/events
sleep 1
kill -0 "$(cat ~/.blinky/run/pid)" 2>/dev/null && echo "still running (unexpected)" || echo "process exited on quit"
rm -rf ~/.blinky
```

Expected: `pid file present`, `process alive`, `process exited on quit` — proving the binary launches, detaches, writes its pid file, and cleanly exits on `quit` without crashing. This does **not** verify what's drawn on screen.

- [ ] **Step 5: Hand off the manual checklist**

The following need a human looking at the screen and cannot be verified by an agent; call them out explicitly when this task is reported as done (carried over verbatim from the spec's Testing approach section):

- Window is click-through: clicking through to the app underneath still works while a reminder is showing.
- App survives closing all terminal windows.
- Dock icon is absent; the 👁️ menu-bar item is present and its hide/show toggle works.
- Frequency changes (via `blinky blink-freq`/`lookaway-freq`, built in Task 8) take effect without restarting the app.
- The look-away blur visibly blurs arbitrary desktop content behind the smiley; if `NSVisualEffectView`'s `.fullScreenUI` material looks wrong in practice, switch to a `CIGaussianBlur` over a screen-captured `CGImage` instead (the spec's documented fallback).

- [ ] **Step 6: Commit**

```bash
git add overlay/ReminderView.swift overlay/App.swift overlay/main.swift
git commit -m "feat: assemble overlay window, timer, and events-file control plane"
```

---

## Task 8: blinky.plugin.zsh

**Files:**
- Create: `blinky.plugin.zsh`
- Test: `Tests/plugin_test.sh`

**Interfaces:**
- Consumes: the `blink_freq_min=`/`lookaway_freq_min=` config key names from Task 1's `Settings.load()`.
- Produces: the `blinky` zsh function, consumed by Task 9's `install.sh`.

This file is tested by actually sourcing it under an isolated `$HOME` and asserting on its real output and the real config file it writes — no binary needs to be built or running, since frequency get/set is pure config-file logic (`_blinky_start` simply no-ops when `$_BLINKY_BIN` doesn't exist, which is fine for this task).

- [ ] **Step 1: Write the failing test**

Create `Tests/plugin_test.sh`:

```bash
#!/bin/zsh
set -e
ROOT="${0:A:h:h}"
export HOME="$(mktemp -d)"
unset SSH_CONNECTION

source "$ROOT/blinky.plugin.zsh"

fail() { echo "FAIL: $1"; exit 1; }

out="$(blinky blink-freq 5)"
[[ "$out" == *"5"* ]] || fail "blink-freq 5 did not report 5 (got: $out)"
grep -qx "blink_freq_min=5" "$HOME/.blinky/config" || fail "config missing blink_freq_min=5"

out="$(blinky blink-freq)"
[[ "$out" == "5" ]] || fail "blink-freq with no arg should print 5 (got: $out)"
[[ "$(grep -c '^blink_freq_min=' "$HOME/.blinky/config")" == "1" ]] || fail "blink-freq with no arg must not duplicate the key"

out="$(blinky lookaway-freq 45)"
[[ "$out" == *"45"* ]] || fail "lookaway-freq 45 did not report 45 (got: $out)"
grep -qx "lookaway_freq_min=45" "$HOME/.blinky/config" || fail "config missing lookaway_freq_min=45"

out="$(blinky blink-freq 10)"
[[ "$(cat "$HOME/.blinky/config")" == $'blink_freq_min=10\nlookaway_freq_min=45' ]] || fail "setting blink-freq again should replace, not duplicate: $(cat "$HOME/.blinky/config")"

out="$(blinky status)"
[[ "$out" == *"blink-freq: 10"* ]] || fail "status missing blink-freq (got: $out)"
[[ "$out" == *"lookaway-freq: 45"* ]] || fail "status missing lookaway-freq (got: $out)"
[[ "$out" == *"state: on"* ]] || fail "status should default to on (got: $out)"

out="$(blinky off)"
out="$(blinky status)"
[[ "$out" == *"state: off"* ]] || fail "status should report off after 'blinky off' (got: $out)"

out="$(blinky demo nonsense 2>&1)"
[[ "$out" == *"usage"* ]] || fail "unrecognized demo name should print usage (got: $out)"

out="$(blinky start 2>&1)"
[[ "$out" == *"not installed"* ]] || fail "start without a built binary should say so (got: $out)"

echo "all plugin assertions passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x Tests/plugin_test.sh && zsh Tests/plugin_test.sh`
Expected: FAIL — `blinky.plugin.zsh: No such file or directory` (nothing has been written yet).

- [ ] **Step 3: Write minimal implementation**

Create `blinky.plugin.zsh`:

```zsh
# Blinky — eye-care reminders. A native overlay nudges you to blink and look away on
# configurable intervals; the shell only sends small events to control it.

[[ -n "${BLINKY_LOADED:-}" ]] && return
typeset -g BLINKY_LOADED=1
typeset -g _BLINKY_HOME="${BLINKY_HOME:-$HOME/.blinky}"
typeset -g _BLINKY_BIN="$_BLINKY_HOME/bin/blinky-overlay"
typeset -g _BLINKY_EVENTS="$_BLINKY_HOME/run/events"
typeset -g _BLINKY_PID="$_BLINKY_HOME/run/pid"
typeset -g _BLINKY_CONFIG="$_BLINKY_HOME/config"
typeset -g _BLINKY_HIDDEN=0

_blinky_running() {
  [[ -r "$_BLINKY_PID" ]] || return 1
  kill -0 "$(<"$_BLINKY_PID")" 2>/dev/null
}

_blinky_start() {
  [[ "$OSTYPE" == darwin* && -x "$_BLINKY_BIN" ]] || return 1
  _blinky_running && return 0
  mkdir -p "$_BLINKY_HOME/run"
  ( nohup "$_BLINKY_BIN" >/dev/null 2>&1 & )
}

_blinky_send() {
  [[ -d "$_BLINKY_HOME/run" ]] || return
  print -r -- "$1" >> "$_BLINKY_EVENTS"
}

# Wake blinky when a local interactive shell opens (skip over SSH).
[[ -z "${SSH_CONNECTION:-}" ]] && _blinky_start

_blinky_config_set() {
  local key="$1" value="$2" line
  local -a kept=()
  if [[ -r "$_BLINKY_CONFIG" ]]; then
    while IFS= read -r line; do [[ "$line" == "$key="* ]] || kept+=("$line"); done < "$_BLINKY_CONFIG"
  fi
  mkdir -p "${_BLINKY_CONFIG:h}"
  print -rl -- "${kept[@]}" "$key=$value" > "$_BLINKY_CONFIG"
}

_blinky_config_get() {
  local key="$1"
  [[ -r "$_BLINKY_CONFIG" ]] || return
  sed -n "s/^$key=//p" "$_BLINKY_CONFIG" | tail -1
}

# Get/set one frequency: `_blinky_freq <config-key> <label> <minutes-or-empty> <default>`.
_blinky_freq() {
  local key="$1" label="$2" minutes="${3:-}" default="$4"
  if [[ -z "$minutes" ]]; then
    local current="$(_blinky_config_get "$key")"
    echo "${current:-$default}"
    return
  fi
  if ! [[ "$minutes" =~ '^[0-9]+$' ]]; then
    echo "usage: blinky $label [minutes]  (0 disables)"
    return 1
  fi
  _blinky_config_set "$key" "$minutes"
  _blinky_start; _blinky_send reload
  echo "👁️ $label: $minutes min"
}

blinky() {
  case "${1:-}" in
    on)    _BLINKY_HIDDEN=0; _blinky_start; _blinky_send show; echo "👁️ blinky: on" ;;
    off)   _BLINKY_HIDDEN=1; _blinky_send hide; echo "blinky: off" ;;
    start) _blinky_start && echo "👁️ blinky started" || echo "overlay not installed — run install.sh" ;;
    quit)  _blinky_send quit; echo "👁️ blinky stopped" ;;
    blink-freq)    _blinky_freq blink_freq_min "blink-freq" "${2:-}" 1 ;;
    lookaway-freq) _blinky_freq lookaway_freq_min "lookaway-freq" "${2:-}" 20 ;;
    status)
      echo "blink-freq: $(_blinky_freq blink_freq_min "blink-freq" "" 1) min"
      echo "lookaway-freq: $(_blinky_freq lookaway_freq_min "lookaway-freq" "" 20) min"
      echo "state: $([[ "$_BLINKY_HIDDEN" == 1 ]] && echo off || echo on)"
      ;;
    demo)
      case "${2:-}" in
        blink|lookaway) _blinky_start; _blinky_send "demo $2" ;;
        *) echo "usage: blinky demo blink|lookaway" ;;
      esac
      ;;
    *) echo "usage: blinky {on|off|start|quit|status|blink-freq [min]|lookaway-freq [min]|demo blink|lookaway}" ;;
  esac
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zsh Tests/plugin_test.sh`
Expected: PASS — prints `all plugin assertions passed`.

- [ ] **Step 5: Commit**

```bash
git add blinky.plugin.zsh Tests/plugin_test.sh
git commit -m "feat: add blinky.plugin.zsh terminal commands"
```

---

## Task 9: install.sh

**Files:**
- Create: `install.sh`
- Test: `Tests/install_test.sh`

**Interfaces:**
- Consumes: `overlay/*.swift` (Tasks 1–7) and `blinky.plugin.zsh` (Task 8).
- Produces: nothing consumed by a later task — this is the last task.

- [ ] **Step 1: Write the failing test**

Create `Tests/install_test.sh`:

```bash
#!/bin/zsh
set -e
ROOT="${0:A:h:h}"
export HOME="$(mktemp -d)"

fail() { echo "FAIL: $1"; exit 1; }

"$ROOT/install.sh" >/tmp/blinky-install-test.log 2>&1

[[ -x "$HOME/.blinky/bin/blinky-overlay" ]] || fail "overlay binary was not built"
[[ -f "$HOME/.blinky/blinky.plugin.zsh" ]] || fail "plugin was not copied"
grep -qF 'source "$HOME/.blinky/blinky.plugin.zsh"' "$HOME/.zshrc" || fail "zshrc source line missing"

lines_before="$(grep -cF 'source "$HOME/.blinky/blinky.plugin.zsh"' "$HOME/.zshrc")"
"$ROOT/install.sh" >>/tmp/blinky-install-test.log 2>&1
lines_after="$(grep -cF 'source "$HOME/.blinky/blinky.plugin.zsh"' "$HOME/.zshrc")"
[[ "$lines_before" == "$lines_after" ]] || fail "running install.sh twice duplicated the zshrc source line"

echo "all install assertions passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x Tests/install_test.sh && zsh Tests/install_test.sh`
Expected: FAIL — `install.sh: No such file or directory` (nothing has been written yet).

- [ ] **Step 3: Write minimal implementation**

Create `install.sh`:

```bash
#!/bin/zsh
set -e

ROOT="${0:A:h}"
DEST="${HOME}/.blinky"
mkdir -p "$DEST/bin" "$DEST/run"

if ! command -v swiftc >/dev/null; then
  echo "swiftc not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

# Stop a running instance so the new build takes over.
if [[ -r "$DEST/run/pid" ]] && kill -0 "$(<"$DEST/run/pid")" 2>/dev/null; then
  echo quit >> "$DEST/run/events"
  sleep 0.5
fi

echo "Building overlay..."
swiftc -O -o "$DEST/bin/blinky-overlay" \
  "$ROOT"/overlay/*.swift -framework AppKit

cp "$ROOT/blinky.plugin.zsh" "$DEST/"

ZSHRC="${HOME}/.zshrc"
LINE='source "$HOME/.blinky/blinky.plugin.zsh"'
if ! grep -Fqx "$LINE" "$ZSHRC" 2>/dev/null; then
  printf '\n# Blinky\n%s\n' "$LINE" >> "$ZSHRC"
fi

echo "👁️ Blinky installed."
echo "Open a new terminal (or: source ~/.zshrc) and the reminders will start."
echo "Commands: blinky on | off | start | quit | status"
echo "Frequencies: blinky blink-freq [minutes] | blinky lookaway-freq [minutes]  (0 disables)"
echo "Try it: blinky demo blink | blinky demo lookaway"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zsh Tests/install_test.sh`
Expected: PASS — prints `all install assertions passed`.

- [ ] **Step 5: Commit**

```bash
git add install.sh Tests/install_test.sh
git commit -m "feat: add install.sh"
```

---

## Final verification (whole project)

After Task 9, run the full automated suite before handing off to final review:

```bash
swift test
zsh Tests/plugin_test.sh
zsh Tests/install_test.sh
```

Expected: all green. Then perform the manual checklist from Task 7, Step 5 on the real machine — this plan's execution cannot complete that part itself.
