# On-screen keyboard: terminal keys (2026-10-01)

Research E-phone 4.3 (MUST): the on-screen keyboard needs Esc, Tab and arrows (Linux keyboards miss
terminal keys, about 7 sources). plasma-keyboard 6.7.5 and 6.8 have none.

## What it does

The second page of the symbols layout (&123, then 1/2) has a row of rare symbols (™ ® « » “ ”).
`plasma-fusion-keyboard-keys` turns that row into **Esc, Tab, ←, ↓, ↑, →** (the arrows repeat while
held; `;` and `\` stay), and moves the six symbols to the long-press lists of the `§` key (™ ®) and
the `"` key (“ ” « »). Same number of keys and rows, so nothing else moves.

How: plasma-keyboard reads its layouts from the first `plasma/keyboard/layouts` directory of the data
directories, and nowhere else (the system's: the first in `XDG_DATA_DIRS`, `/usr/share` on Fedora, the
system profile on NixOS; a directory the tool built is never taken for it). The tool builds
`~/.local/share/plasma/keyboard/layouts` with a link
to every system language directory and a `fallback` directory (English and every language without
its own layout) whose files link to the system's, except `symbols.qml`: a copy of the *installed* file
with that row replaced (exact text matches; if one fails, the directory is removed and the stock
keyboard stays). Plasma Fusion ships no copy of the Qt layout (LicenseRef-Qt-Commercial OR
GPL-3.0-only); the patched copy is made on the machine. Marker file `.plasma-fusion`: a layouts
directory without it (the user's own) is never touched.

Keys reach apps as keysyms (plasma-keyboard sends non-text keys that way), so they work in every app;
in Konsole `cat -v` shows `^[`, a tab and `^[[D ^[[B ^[[A ^[[C` (6.7.5 and 6.7.91 containers).

## Commands and lifecycle

- `plasma-fusion-keyboard-keys install | refresh | remove | status` (`/usr/libexec/plasma-fusion/`,
  per user in `~/.local/libexec/plasma-fusion/`). Record: `~/.local/state/plasma-fusion/keyboard-keys`.
  `fusion-config.sh` (and the stub it writes) and `fusion-restore.sh` use the first copy of
  `~/.local/libexec`, `/usr/local/libexec`, `/usr/libexec` and `/usr/lib` (each `/plasma-fusion`), so
  a system-wide install gets the keys too (before 2026-10-02 only the user's copy counted).
- `fusion-config.sh --install` runs `refresh` (builds on first run; keeps a user's `remove`).
- Login: the env stub of the login check runs `refresh` only when a package database (the rpm
  database; on other distributions `/var/lib/pacman/local`, `/var/lib/dpkg/status` or the Nix
  profiles directory) is newer than the record (about 2 ms otherwise); a plasma-keyboard update
  rebuilds the copy from the new file. The tool's own stamp is the rpm database's size and time
  (with pacman's, dpkg's and the NixOS system profile's where they exist), and plasma-keyboard's
  version comes from rpm, pacman or dpkg, on NixOS from the store path of its layouts. A `refresh`
  that finds the stamp unchanged touches the record, so the next login skips the tool again.
- `fusion-restore.sh` removes the layouts and the record (a later install builds them again).

## Checks

`tools/build.d/88-keyboard-keys.sh`: compile and `packages/keyboard/tests/patch_test.py` (the row
becomes Esc, Tab and the arrows at its indent, the symbols go to the long-press lists; a page without
the row is left alone; 32 KiB of spaces or tabs is turned down within a second; standard library
only). `fuzz/keyboard_keys_fuzzer.py` patches arbitrary text (docs/parts/ci.md, "Fuzzing").

## Not here (upstream plasma-keyboard)

Ctrl and Alt (keysyms are sent with no modifiers and letters are committed as text, so a modifier key
needs plasma-keyboard C++), and moving the cursor by dragging on the space bar (Qt Virtual Keyboard
handles the keyboard's touches in one area, so a layout cannot add a gesture to a key). Drafts for an
upstream merge request: `artifacts/plasma-fusion/2026-10-01-tablet2/KEYBOARD/` on the shared drive.
