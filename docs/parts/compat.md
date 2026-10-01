# Per-app compatibility (HIDPI-1)

Plasma Fusion works with Plasma's and KWin's own scaling: KScreen's per-screen scale, KWin's
"apply scaling themselves" mode for X11 apps (kwinrc `[Xwayland] Scale`, `Xft.dpi` 128 at 4/3) and
the normal launch paths. It never forces a global font DPI or scale factor (that is what makes apps
twice too big). Where one app has a known upstream bug, a narrow rule fixes that app only; each
rule names its bug, its test and when to remove it.

## Backend audit (2026-10-01)

Private Wayland sessions on the ThinkPad with the real session's X11 setup (1920 x 1200 at 4/3,
`[Xwayland] Scale=4/3`, `Xft.dpi: 128`), one app per toolkit, maximized, screenshots in
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-10-01-hidpi/`:

| Backend | App | At 4/3 | Scale change 4/3 -> 1 -> 2 -> 4/3 |
|---|---|---|---|
| Qt 6, Wayland | KWrite | right (reference) | right |
| Qt 6, XWayland (`QT_QPA_PLATFORM=xcb`) | KWrite | same size as Wayland | right (KWin scales X11 windows) |
| LibreOffice 26.2.6, kf6 (default), Wayland | Writer, Calc, Impress | right; also in tablet posture and at 1.325 | **twice too big at exactly 1.0** after 4/3; 1.25, 1.5, 1.05 right; started at 1.0 right |
| LibreOffice, kf6 through XWayland | Writer | right | right; global menu works; window class `soffice.bin` |
| LibreOffice, gtk3, Wayland | Writer | right, sharp | right at every step, but **no menu at all**: it hides its menu bar once `com.canonical.AppMenu.Registrar` is on the bus, and Plasma cannot show GTK menus on Wayland |
| LibreOffice, gtk4, Wayland | Writer | right | white glitch strips in the toolbars after 4/3 -> 1 |
| GTK 4 / libadwaita | GNOME Text Editor | right | not run |
| GTK 3 | Xournal++ | window did not come up in time in the scripted run | not run |

The owner's "LibreOffice far too big" came from the UX5406SA: its panel runs at 1.5 and the
external TCL HDMI monitor (1920 x 1080) at exactly 1.0 (`~/.config/kwinoutputconfig.json`), the one
case LibreOffice's Qt backends get wrong. The ThinkPad has only ever had its own panel. Upstream:
tdf#141578 and reports on Reddit, EndeavourOS, Ask LibreOffice and KDE Discuss (September 2026),
all "huge on the 100 % screen next to a scaled one"; the known workaround is XWayland.

## LibreOffice scale guard

- `packages/compat/plasma-fusion-libreoffice`, staged to `.local/libexec/plasma-fusion/` (RPM:
  `/usr/libexec/plasma-fusion/`). fusion-config.sh links `~/.local/bin/libreoffice` to it (first in
  the session's PATH, so menus, the dock and opening files all pass through it) and copies
  `soffice.desktop` (hidden) to `~/.local/share/applications/`. A `~/.local/bin/libreoffice` that
  is not Plasma Fusion's is left alone; both paths are in the backup (fusion-restore.sh removes
  them).
- At each start it asks KScreen (`kscreen-doctor -j`, about 30 ms) for the enabled screens. Only
  while one is at exactly 100 % and another is scaled, it starts LibreOffice through XWayland
  (`QT_QPA_PLATFORM=xcb`) and logs one line to `~/.local/state/plasma-fusion/compat.log`.
  Untouched: one screen or equal scales, `QT_QPA_PLATFORM` set, `SAL_USE_VCLPLUGIN` set to a
  non-Qt backend, `--headless`/`--convert-to`/`--cat`/`--print-to-file`, no Wayland display.
- `soffice.desktop` gives the XWayland windows (`WM_CLASS soffice.bin`, desktop file `soffice`) the
  name "LibreOffice" and its icon in the top bar, the dock and the switcher.
- Limits: LibreOffice is one process, so the choice holds until it exits; a screen plugged in while
  it runs natively still shows the bug there until LibreOffice restarts. Through XWayland it is
  sharp on the screens at KWin's X11 scale and scaled by KWin on the others, and the on-screen
  keyboard does not come up by itself (only relevant with an external screen, at a desk).
- Test: private session `hd7b` (two screens): equal scales native (`libreoffice-writer`); Virtual-1
  at 1.0: XWayland (`soffice.bin`), right size on both screens, top bar "LibreOffice" with the
  global menu; headless conversion untouched; native control twice too big on the 100 % screen.
- Remove when LibreOffice fixes tdf#141578: run `build/hidpi/scen-hd5.sh` (kf6 native through
  4/3 -> 1.0) and drop the rule when the 1.0 step is right.
