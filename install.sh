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
echo "Frequencies: blinky blink-freq [min|secs] | blinky lookaway-freq [min|secs]  (e.g. 5 or 30s; 0 disables)"
echo "Try it: blinky demo blink | blinky demo lookaway"
