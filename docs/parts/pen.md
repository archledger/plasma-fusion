# Pen (stylus) support

Spec: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-tablet/PEN.md` (defaults in section 2,
Pen menu in section 3, hand checks V1-V6 in section 6.2). Device: ThinkPad X13 Yoga Gen 4, Wacom
WACF2200 `056a:534d`, libinput devices "Wacom HID 534D Pen" and "Wacom HID 534D Finger".

## Defaults (`tools/pen/pen-defaults.sh`)

Per user, run inside the session (or over SSH with the session bus). Every setting takes effect at
once; `--dry-run` prints the changes, `--restore <backup>` undoes them, `--no-install` skips the
package.

| Setting | Value | Where |
|---|---|---|
| Click button (BTN_STYLUS, 331) | right click | `kcminputrc [ButtonRebinds][TabletTool][Wacom HID 534D Pen] 331=MouseButton,273` |
| One pointer for pen, touchpad and TrackPoint | on | `kcminputrc [Tablet] SyncWithMouse=true` |
| Pen screen | built-in panel (`eDP-1`) | KWin D-Bus `outputName`; KWin writes `OutputUuid` |
| Notes and whiteboard app | Xournal++ | `dnf install --setopt=install_weak_deps=False xournalpp` (3 packages, about 8 MB; with weak dependencies its optional LaTeX tool pulls in about 260 MB of TeX Live) |
| Device description (X13 Yoga Gen 4 digitizer only) | `~/.config/libwacom/lenovo-x13-yoga-gen4-534d.tablet` | per user (libwacom reads `$XDG_CONFIG_HOME/libwacom` first); names the device, `Reversible=false` removes the left-handed option that mirrors a display pen; libinput reads it when KWin adds the device, i.e. from the next login. No `Styli` line until hand check V1 (every `isdv4-aes` stylus has one button) |

The internal output is found through sysfs (`/sys/class/drm/card*-eDP-*`), so no Qt tool runs. The
backup (`~/.local/state/plasma-fusion/pen-backup-<UTC>/`) holds a copy of `kcminputrc`, the old value
of each key the script set (`keys`) and the pen's previous output (`pen-output`).

Not yet built: the Pen menu plasmoid (PEN.md section 3). The click-button mapping assumes the
button that sends 331 is the one a user expects to right-click with (hand check V1).

## Live device

2026-09-30 01:17Z: applied to the ThinkPad's real session (backup `pen-backup-20260930T011729Z`);
01:41Z the libwacom description (backup `pen-backup-20260930T014140Z`; `libwacom-list-local-devices`
lists the pen as 'Lenovo ThinkPad X13 Yoga Gen 4 Pen', General Pen + Eraser, 2 buttons).
Undo: `~/.local/state/plasma-fusion/tools-pen/pen-defaults.sh --restore
~/.local/state/plasma-fusion/pen-backup-20260930T011729Z`; `sudo dnf remove xournalpp` for the app.
