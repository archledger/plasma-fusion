<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Copy text's selection overlay: `plasma-fusion-copytext-overlay`

Status: new in the release after 0.5.0 (the owner's request of 2026-10-17: copy text from the screen
as NormCap does it, one click, a box, done; the research, the CopyText board and the prototype's
measurements approved the same day). Package `plasma-fusion-copytext` (the fifth compiled part).
Last edited 2026-10-18.

## What it is

Copy text from the screen (docs/parts/device.md, "Copy text from the screen") takes an area of the
screen and puts its text on the clipboard. Its helper, `plasma-fusion-copytext` (a script in the
main package), used Spectacle's selection: Spectacle starts from scratch for every capture, about
2.5 s on the test laptop and 1 s on the UX5406SA before the selection shows. This program is a
selection of Plasma Fusion's own that stays running, so it shows at once:

1. **Start** (`org.plasmafusion.CopyTextOverlay`, `/`, `Start()` on the session bus): it takes a
   picture of every screen through KWin (`org.kde.KWin.ScreenShot2.CaptureScreen`, at native
   resolution, without the pointer; KWin 6.7.5 writes the raw image into a pipe passed with the call
   and answers with its width, height, stride, format and scale) and shows one window per screen
   over everything (LayerShellQt, the overlay layer, all four edges, the keyboard to itself): the
   screen as it was at the click under the veil, the hint "Draw a box around the text · Esc cancels"
   in the island's black 46 px from the top. Nothing moves while the box is drawn.
2. **The box** (the CopyText board): clear inside, a 2 px `#5b9dff` edge (radius 4) and a soft
   accent halo; the pointer a crosshair. As the drag ends (no Enter, as copy-text tools do) the
   box's native pixels (`nativeArea()`: every pixel the box touches, at the screen's scale) are cut
   from that screen's picture into a private directory in the runtime directory, the windows close,
   and `plasma-fusion-copytext --image FILE` reads, copies and says it ("Text copied" or "No text
   found"); the directory goes once the helper is done. Esc, a click without a drag or a box under 4
   px end it without a word. A second `Start()` while the box is being chosen, or while the helper
   still reads the last area, does nothing (the helper, which reads one area at a time, would drop a
   second).
3. **Waiting:** the program stays on the bus with no window. It draws with Qt Quick's software
   renderer: one still picture, a veil and a box, as fast as the GPU renderer and without keeping
   the GPU driver's memory (below). After each use it gives the freed memory back (glibc's
   `malloc_trim`).

When KWin refuses the pictures (the desktop file missing, another compositor) it runs the helper
with `PLASMA_FUSION_COPYTEXT_NO_OVERLAY=1`, which then uses Spectacle's selection as without this
package. Each `Start()` has a capture of its own: a picture that KWin still sends after a refusal
ended it is dropped, not kept until the next press. It goes the helper's way too when it has the
pictures but cannot make one window of them (the QML gives no window, a runtime error): it says
"no overlay window" in the journal, and the next `Start()` asks KWin again. "shown in" is said only
once a window is up (the release tests take that line as the overlay seen). 0.6.0 said it either
way, and the overlay then stayed busy with no window: every later `Start()` did nothing until it was
restarted.

## Starting it

- **On demand:** the package installs `org.plasmafusion.CopyTextOverlay.service` in the session
  bus's service directory (`share/dbus-1/services`). The helper calls `Start()` first; the bus
  starts the program on that first call and the program stays. Nothing runs before copy text is
  first used, and there is nothing to set up or undo per user. Without the package (or with the
  helper's `PLASMA_FUSION_COPYTEXT_NO_OVERLAY`) the call fails at once and the helper uses
  Spectacle; it hands over only where `tesseract` is installed, as nothing could read the area
  otherwise.
- **KWin's permission:** ScreenShot2 is restricted. KWin allows it to a process whose executable is
  the first word of `Exec=` in a desktop file that lists
  `X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2` (KWin 6.7.5 `utils/serviceutils.h`,
  the canonical path), as plasmashell's and Spectacle's do.
  `org.plasmafusion.copytextoverlay.desktop` is that file (hidden from menus, as plasmashell's); its
  `Exec=` and the D-Bus service's are written by CMake from `PF_HELPER_DIR`, so both name the
  installed program (the spec checks both). A script cannot be given the permission safely (it would
  go to its interpreter, every Python program); hence a compiled part.
- **NixOS:** the program is not wrapped (nixpkgs' KWin patch unwraps `.NAME-wrapped` for its Wayland
  checks only, not for this D-Bus one); the module lists the package in `services.dbus.packages`.
  The bus starts the program from its own store path, where nothing else of Plasma Fusion is, so the
  package links the shared package's helper beside it. Not run on NixOS (docs/parts/nixos.md).

## Files

| File | What |
|---|---|
| `packages/copytext-cpp/CMakeLists.txt`, `src/CMakeLists.txt` | ECM project: `copytextcore` (static library: KWin's picture, the box's arithmetic), `copytextoverlay` (static library: the overlay with its QML compiled in, `qt_add_qml_module`, `org.plasmafusion.copytextoverlay`), both shared with the tests; the program; `PF_HELPER_DIR`, the desktop and D-Bus service files, `built-against/copytext` |
| `src/capture.h`, `src/capture.cpp` | `ScreenCapture` (CaptureScreen, the pipe read off the main thread) and `readRawImage()` |
| `src/area.h` | `nativeArea()`: the box in native pixels |
| `src/overlay.h`, `src/overlay.cpp` | `Overlay`: `Start()`, the windows (LayerShellQt), the cut, the hand-over to the helper, the way back to Spectacle |
| `src/main.cpp` | the bus name, the software renderer, `--now` (a capture at once, for tests) |
| `src/qml/Overlay.qml` | one screen's overlay (CopyText board) |
| `data/org.plasmafusion.copytextoverlay.desktop.in`, `data/org.plasmafusion.CopyTextOverlay.service.in` | KWin's permission; the bus's on-demand start |
| `tests/coretest.cpp`, `tests/overlaytest.cpp`, `tests/capturetest.cpp`, `tests/flowtest.cpp` | `copytext-core`, `copytext-overlay`, `copytext-capture`, `copytext-flow` (QTest) |
| `tests/fakekwin.h`, `tests/fake-helper.sh` | the stand-ins for KWin's ScreenShot2 and for the helper |
| `tests/vsession/scenario-overlay.sh` | the program in a private session (below) |

## Build

```
cmake -S packages/copytext-cpp -B build/copytext -G Ninja -DBUILD_TESTING=ON
cmake --build build/copytext
QT_QPA_PLATFORM=offscreen ctest --test-dir build/copytext --output-on-failure
```

Needs Qt 6.8 (Core, Concurrent, DBus, Gui, Qml, Quick), KDE Frameworks 6.10 (I18n) and LayerShellQt
(Plasma's `layer-shell-qt`); at run time the QtQuick, QtQuick.Shapes and QtQuick.Window QML modules
and Tesseract. `-DPF_HELPER_DIR=` sets where the program goes (default
`PREFIX/libexec/plasma-fusion`). Packages: Fedora `plasma-fusion-copytext` (Requires
qt6-qtdeclarative, layer-shell-qt, tesseract; its QML gets a time stamp derived from its sources, as
Quick Look's), Debian `plasma-fusion-copytext` (layer-shell-qt, the qml6-module-qtquick* packages,
tesseract-ocr), Arch `plasma-fusion-copytext` (the helper directory is `/usr/lib/plasma-fusion`
there), Nix `plasma-fusion-copytext`. The main package recommends it (Arch: optdepends).

## Tests

- `copytext-core` (`tests/coretest.cpp`, ctest; CI `compiled`, `sanitizers` and `coverage`): KWin's
  raw picture through a real pipe (rows with a stride above the row, the scale kept), and every
  doubt refused (a short read, a stride under the row, no format, an unknown one, no width, a type
  other than raw); rows of 20 KiB written slowly in pieces of 1000 bytes arrive whole (a pipe hands
  over what is there; Qt's `QFile::read()` reads on to the full length, Qt 6.11
  `QFSFileEnginePrivate::readFdFh`); no scale (KWin before version 4) reads as 1; the box in native
  pixels at scale 1, 2 and 1.75 (every pixel the box touches) and past the picture's edge.
- `copytext-overlay` (`tests/overlaytest.cpp`, offscreen, the software renderer): the QML against
  the board: the hint 46 px from the top, 32 px high, centred within half a pixel, gone once the
  drag starts; the veil's colour over the picture outside the box, the picture clear inside, the
  accent edge beside it; a drag chooses its box (downwards and upwards), Esc, a click and a box
  under 4 px cancel without choosing.
- `copytext-capture` (`tests/capturetest.cpp`, ctest under dbus-run-session): a stand-in for KWin's
  ScreenShot2 on the private bus answers CaptureScreen as KWin 6.7.5 does; the picture arrives with
  its size, scale and pixels, asked for by the screen's name, at native resolution, without the
  pointer; KWin's refusal ends in `failed()`.
- `copytext-flow` (`tests/flowtest.cpp`, ctest under dbus-run-session): the overlay itself with the
  stand-in for KWin, offscreen on two screens (DP-1 at scale 2, HDMI-1 at scale 1, from a file for
  Qt's offscreen platform), and a stand-in for the helper beside the test program, where the overlay
  looks for it. `Start()` called on the bus as the helper calls it shows one window per screen, on
  its screen and of its size, after one picture per screen; a box drawn on DP-1 reaches the helper
  as `--image FILE` with exactly that box's native pixels (each pixel of the stand-in's picture says
  where it is), the windows gone; a box on HDMI-1 is cut from HDMI-1's picture; the file is in a new
  directory of mode 700 in the runtime directory, removed once the helper ends. A second `Start()`
  while the box is chosen asks KWin for nothing more; one while the helper still reads (the stand-in
  held) shows nothing, and the next after it does; Esc and a click close every window and run
  nothing; KWin's refusal runs the helper once, with `PLASMA_FUSION_COPYTEXT_NO_OVERLAY=1`, and
  shows no window; with one screen refused, the other's picture is dropped when it comes; a capture
  that makes no window (QML that gives an item, or a window that cannot be made: a required property
  the overlay does not set) runs the helper the same way, does not say "shown in", and the next
  `Start()` asks KWin again and goes the same way. Against 0.6.0's `overlay.cpp` both of these
  cases fail (2026-10-18: no helper run; the overlay stayed busy).
- All pass with `-Werror` and under AddressSanitizer and UndefinedBehaviorSanitizer with leak
  detection (`tools/sanitizers/run.sh`, Fedora 44 container, 2026-10-18). Line coverage
  (`tools/tests/coverage.sh cpp:copytext-cpp`, docs/parts/coverage.md): 82.2 % (189 of 230),
  `main.cpp` not at all (the program's start runs only in a session, below). The RPMs build with the
  new package and rpmlint reports 0 errors over all 14 packages (its one warning, no-documentation,
  as the decoration's and Quick Look's).
- The helper's side: `packages/copytext/tests/helper-unit.sh` (CI `build`, 32 checks): the overlay
  on the bus gets `Start()` and nothing else runs; its way back
  (`PLASMA_FUSION_COPYTEXT_NO_OVERLAY`) is Spectacle's capture; `--image FILE` reads that picture
  with no capture and leaves it to its owner; `--image` without a picture exits 2.
- `tests/vsession/scenario-overlay.sh`: the program in a private session (the real KWin, Tesseract
  and Klipper; the setup's Meta+Shift+T), installed as the packages install it: its desktop file and
  its D-Bus service file. 2026-10-17, the UX5406SA (Fedora 44, Plasma 6.7.5, Intel GPU), 2880 x 1800
  at scale 1.75: 8 checks pass - the overlay does not run before the first copy text; the first
  starts it and it shows 235 ms after the helper started (its own start included); Meta+Shift+T, a
  drag around a line, released: exactly that line on Klipper's clipboard, "Text copied", the overlay
  gone; Esc: gone, nothing copied or said. Later uses: the overlay 74-96 ms after the helper
  started, Spectacle's selection 888-1063 ms on the same machine, measured the same way; memory
  after a use 72-92 MB, no CPU while it waits. Earlier runs of the same scenario (the program
  started by hand): scale 1 and two screens on the UX5406SA, all copy checks pass; the ThinkPad
  (scale 1): the overlay 43-54 ms after the hand-over. The GPU renderer against the software one
  (2880 x 1800): 90-100 ms against 71-89 ms to the overlay, 120-140 MB against 74-95 MB after a use:
  hence the software renderer. The private session's bus finds the D-Bus service file only with
  `XDG_DATA_HOME` set to the private HOME's (tools/vsession/vsession.sh: dbus-daemon takes the home
  from the account database).
- Red runs (2026-10-17, Fedora 44 container), one change at a time, each failing its test:
  `copytext-overlay` - a 12.5 px `font.pixelSize` (the prototype's first run: the QML did not load
  and the overlay never showed), the hint at 40 px, the hint kept while drawing, the veil over the
  box, a click choosing, no Esc, the edge in another colour; `copytext-core` - the box rounded
  instead of every pixel it touches, the box not kept inside the picture, the stride ignored, the
  scale dropped, the type not checked; `copytext-capture` - a logical-resolution picture, the
  pointer included; `copytext-flow` - the box at scale 1, the first screen's picture for every box,
  a second `Start()` starting again, the way back without its variable or once per screen, the
  private directory kept, another D-Bus interface name, the windows without their geometry, the
  helper run on a cancel, the directory's mode (the stand-in reporting 755), `Start()` not waiting
  for the helper, a picture kept after a refusal (and the overlay before these two, both cases);
  `copytext-core` again - one `read()` per row instead of `QFile::read()`. The window's screen alone
  (`setScreen()` without the geometry change) passes offscreen, where the geometry places the
  window: the layer shell's choice of output shows only on Wayland (the two-screen session run
  below). The helper's unit test against main's helper: three of the four new cases fail (the
  fourth, the way back to Spectacle, is main's behaviour).

Not verified: by a person on a real screen (how the box follows the pointer with the software
renderer: the ThinkPad's live session once it can be charged), NixOS, KDE neon and Arch at run time
(their packages build in CI's package jobs), and a screen added while the program waits (its windows
are made at each `Start()` from the screens there are then).
