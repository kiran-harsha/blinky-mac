# Blinky — Eye-Care Reminder — Design

## Purpose

A macOS desktop companion, structured the same way as `shihtzu-mac`
(native Swift/AppKit overlay + zsh plugin + install script, no external
dependencies), that nudges the user to take care of their eyes while they
work in the terminal:

1. **Blink Reminder** — on a configurable interval, a smiley appears at
   the center of the screen, blinks twice, then disappears. Default: every
   1 minute (the user zones out while working and forgets to blink).
2. **Look-Away Reminder** — on a separate configurable interval, a smiley
   appears at the center of the screen, the background blurs, and the
   smiley's eyes look left → right → up → down before everything fades
   away. Default: every 20 minutes (the "20-20-20" eye-care rule).
3. **Terminal commands** to configure both frequencies independently.

## Success criteria

- Running `install.sh` and opening a new terminal starts the reminders
  with sane defaults — no configuration required to get value.
- `blinky blink-freq <minutes>` and `blinky lookaway-freq <minutes>`
  change behavior immediately on the running instance and persist across
  restarts.
- Both reminders are purely visual nudges: they never block mouse clicks
  and never steal keyboard focus, so they never interrupt active work.
- The app keeps running (and keeps firing reminders) even after every
  terminal window is closed, until the user explicitly quits it.

## Non-goals

- No notifications/sound — visual only, matching the ask.
- No iOS/cross-platform support — macOS only, same as shihtzu-mac.
- No analytics, update checker, or settings UI — terminal commands only.
- No pausing reminders based on activity/idle detection — out of scope
  for v1; frequency 0 is the escape hatch to turn a reminder off.

## Architecture

Mirrors shihtzu-mac's split exactly:

```
blinky-mac/
├── install.sh                   # compiles overlay, wires zsh plugin into ~/.zshrc
├── blinky.plugin.zsh            # defines `blinky` command, starts overlay on first shell
├── overlay/
│   ├── main.swift                # entry point, single-instance check, detach, CLI dispatch
│   ├── App.swift                 # window, menu-bar item, event-file polling, two timers
│   ├── ReminderView.swift        # NSView subclass that draws the smiley + background blur
│   ├── Smiley.swift               # smiley state & drawing (eyes open/closed/looking dir, mouth)
│   ├── BlinkReminder.swift       # blink animation state machine
│   ├── LookAwayReminder.swift    # look-away animation state machine
│   ├── Settings.swift            # frequencies, loaded from / saved to config file
│   ├── Paths.swift                # ~/.blinky/{bin,run,config}
│   └── CLI.swift                  # --list/--show/--demo one-shot flags
└── docs/superpowers/specs/...
```

(Exact file list may shift slightly during implementation planning;
this illustrates the responsibility split, not a final file-by-file
contract.)

### Process model

- `overlay/main.swift`: same single-instance guard as the dog (pid file
  check via `kill(pid, 0)`), then `signal(SIGHUP, SIG_IGN)` + `setsid()`
  to detach from the launching terminal so it survives the terminal
  closing. Activation policy `.accessory` (no Dock icon).
- `blinky.plugin.zsh` starts the overlay the same way the dog does: on
  first interactive shell open (`[[ -z "$SSH_CONNECTION" ... ]] && _blinky_start`),
  via `nohup ... &`. Because `main.swift` detaches via `setsid`, the
  process keeps running after every terminal closes — satisfying
  "persistent background app" without needing a launchd agent for v1.
- A `blinky start` / `blinky quit` command exists for manually
  starting/stopping outside of shell-open auto-start.

### Window & rendering

- One borderless, transparent, click-through (`ignoresMouseEvents =
  true`) `NSWindow` covering the full screen (`window.level = .statusBar`,
  `collectionBehavior` matching the dog's: `canJoinAllSpaces,
  stationary, fullScreenAuxiliary, ignoresCycle`).
- Normally fully transparent and empty. When a reminder fires, its
  state machine becomes active and `ReminderView` draws:
  - **Idle**: nothing drawn, zero CPU cost beyond the poll tick.
  - **Blink Reminder active**: a smiley drawn in Core Graphics at
    screen center; eyes animate closed → open → closed → open (two
    blinks, ~350ms per half-cycle, ~1.4s total), then the whole smiley
    fades out over ~300ms.
  - **Look-Away Reminder active**: background blur drawn first (a
    full-screen `NSVisualEffectView` with `.hudWindow`/`.fullScreenUI`
    material faded in behind the smiley, or a `CIGaussianBlur` over a
    screen-captured `CGImage` if a view-based blur proves insufficient
    over arbitrary content — decided during implementation), then the
    smiley with eye pupils animating: look left (~1s) → right (~1s) →
    up (~1s) → down (~1s) → center, then blur + smiley fade out over
    ~400ms.
- Only one reminder animates at a time; if both are due simultaneously,
  Blink Reminder is shown first and Look-Away Reminder's timer re-fires
  right after (simple sequential queue, no overlap — keeps the state
  machine simple and avoids a cluttered screen).
- A single `Timer` at ~30fps drives both reminder state machines and
  the event-file poll, same cadence as the dog's `tick()`.

### Config & control plane

Same mechanism as shihtzu-mac, renamed:

| shihtzu-mac | blinky-mac |
|---|---|
| `~/.terminal-animals/` | `~/.blinky/` |
| `~/.terminal-animals/config` | `~/.blinky/config` (`blink_freq_min=1`, `lookaway_freq_min=20`) |
| `~/.terminal-animals/run/events` | `~/.blinky/run/events` |
| `~/.terminal-animals/run/pid` | `~/.blinky/run/pid` |
| `shihtzu` zsh function | `blinky` zsh function |

Events file protocol (lines appended by the zsh function, polled by the
overlay, same as the dog's `cmd`/`hide`/`show`/`reload`/`quit`):

```
reload      # re-read config file (frequencies changed)
hide        # stop firing reminders (blinky off)
show        # resume firing reminders (blinky on)
quit        # exit the app
demo blink      # fire a Blink Reminder immediately (for testing)
demo lookaway   # fire a Look-Away Reminder immediately (for testing)
```

### Terminal commands (`blinky.plugin.zsh`)

```zsh
blinky on | off              # resume/pause both reminders (sends show/hide)
blinky start | quit          # launch / stop the overlay process
blinky blink-freq [minutes]  # get/set blink reminder interval; 0 disables
blinky lookaway-freq [min]   # get/set look-away reminder interval; 0 disables
blinky status                # print both frequencies and on/off state
blinky demo blink|lookaway   # trigger one reminder immediately, for trying it out
```

`blinky blink-freq 1` writes `blink_freq_min=1` to `~/.blinky/config`
(same key-rewrite helper pattern as `_ta_config_set`), starts the
overlay if not running, and sends `reload`. Calling with no argument
prints the current value (mirrors `shihtzu coat` with no name listing
choices — here it just prints the number).

### install.sh

Same shape as shihtzu-mac's: checks for `swiftc`, compiles
`overlay/*.swift` with `-framework AppKit`, copies the plugin into
`~/.blinky/`, appends a `source` line to `~/.zshrc` if not already
present, prints usage help on completion.

## Testing approach

- `overlay` binary gets `--demo blink` / `--demo lookaway` one-shot CLI
  flags (parsed in `CLI.swift`, same pattern as the dog's `--snapshot`)
  that launch the app and immediately fire one reminder, so animations
  can be visually checked without waiting on a timer.
- `blinky demo blink` / `blinky demo lookaway` shell commands wrap this
  via the events file for trying it out on a live running instance.
- Manual verification checklist for implementation: window is
  click-through (clicking through to the app underneath still works
  while a reminder is showing), app survives closing all terminals, Dock
  icon absent, menu-bar item present and its hide/show toggle works,
  frequency changes take effect without restarting the app.

## Open items for implementation planning

- Exact blur technique (NSVisualEffectView vs. CIFilter screen capture)
  — pick the simplest one that visibly blurs arbitrary desktop content
  behind the smiley; fall back to the alternative if the first choice
  looks wrong in manual testing.
- Exact smiley geometry/proportions — reuse the dog's drawing style
  (Core Graphics paths, no image assets) but this is a fresh, simple
  shape (circle face, two eyes, mouth) so no catalog system (coats/grooms)
  is needed for v1.
