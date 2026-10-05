# Blinky

A native macOS menu-bar companion that nudges you to take care of your eyes while you work: a **blink reminder** on a short interval, and a **look-away reminder** (the 20-20-20 rule) on a longer one. Both are purely visual — click-through, no sound, no notifications, no stolen keyboard focus — and controlled entirely from the terminal.

Structured the same way as shihtzu-mac: a native Swift/AppKit overlay + a zsh plugin + an install script, with zero external dependencies.

## Install

```zsh
./install.sh        # compiles the overlay with swiftc (needs Xcode Command Line Tools)
source ~/.zshrc
```

Blinky starts the first time a new terminal opens, with sane defaults (blink every 1 minute, look away every 20 minutes). A 👁️ menu-bar item lets you hide it or quit.

## Commands

```zsh
blinky on | off                 # resume / pause both reminders
blinky start | quit             # launch / stop the overlay process
blinky status                   # print both frequencies and on/off state
blinky blink-freq [minutes]     # get/set the blink reminder interval; 0 disables
blinky lookaway-freq [minutes]  # get/set the look-away reminder interval; 0 disables
blinky demo blink | lookaway    # fire one reminder immediately, to try it out
```

Frequency changes apply to the running instance immediately and are saved to `~/.blinky/config`, so they persist across restarts.

## How it works

All art is drawn in code (no image assets), the same way as the reference project. The overlay is split by responsibility:

| File | Role |
| --- | --- |
| `overlay/main.swift` | Entry point: `--show`/`--demo` one-shot flags, single-instance check, app launch |
| `overlay/App.swift` | Overlay window, blur backdrop, menu-bar item, ~30fps timer, events-file polling |
| `overlay/ReminderView.swift` | Draws the smiley for whichever reminder is currently active |
| `overlay/BlinkReminder.swift`, `LookAwayReminder.swift` | Pure animation state machines (no AppKit) |
| `overlay/ReminderScheduler.swift` | Owns both timers; only one reminder animates at a time |
| `overlay/Smiley.swift` | The smiley's drawing code (face, eyes, mouth) |
| `overlay/Settings.swift`, `Paths.swift` | Config file parsing and `~/.blinky/*` filesystem locations |
| `overlay/CLI.swift` | `--show`, `--demo` |
| `blinky.plugin.zsh` | The `blinky` command: starts the overlay, writes the config, sends control events |

### Config & control plane

| Path | Purpose |
| --- | --- |
| `~/.blinky/config` | `blink_freq_min=1` / `lookaway_freq_min=20` |
| `~/.blinky/run/pid` | Single-instance guard |
| `~/.blinky/run/events` | Control events (`reload`, `hide`, `show`, `quit`, `demo blink`, `demo lookaway`) |
| `~/.blinky/run/hidden` | Present while reminders are paused — read by `blinky status` |

macOS only.
