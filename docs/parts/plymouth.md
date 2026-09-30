# Part: Plymouth boot splash and disk unlock (`plasma-fusion`)

Status 2026-09-29: built, checked offline, tested in a QEMU/KVM VM on the ThinkPad (LUKS2 unlock,
splash, simpledrm handover, other prompts, messages, system update, several resolutions, two
displays), then installed and selected on the ThinkPad (initramfs of the running kernel rebuilt;
not rebooted). Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/plymouth/`.

The Plymouth theme for the Boot board (`design/boards/Boot.dc.html`, render `startup-1`): black
screen, the three-circle logo, three pulsing dots, and, when a disk passphrase is asked, the unlock
field as on the board. Script plugin (`plymouth-plugin-script`), no compiled code. It is a system
part (root), outside the HOME stage.

## What it looks like

Board values are logical px of the 1440x900 board; the theme draws them at a scale factor chosen
from the screen size (see "Scaling"). On the ThinkPad (1920x1200, Plymouth device scale 1) the
factor is 4/3, the same as the Plasma session, so boot, login and desktop line up.

| Element | Board | Implementation |
|---|---|---|
| Background | `#000000` | `Window.SetBackground{Top,Bottom}Color(0,0,0)` |
| Logo | 96 px, top edge 250 px down, circles `#5b9dff` / `#f2a65a` / `#3cc4b0` (r 5.5 on a 24 grid), group blended `screen` | pre-rendered; over black the group's screen blend changes nothing, so the circles are opaque, blue under orange under teal, exactly as the render. Fades in over 0.4 s |
| Prompt | 14 px Manrope 400 `#a3abc2`, 44 px under the logo | pre-rendered image per prompt kind (see "Prompts"); other prompts are drawn from a glyph atlas |
| Field | 360x46, radius 23, `#111522`, 1.5 px `#5b9dff` border, 17 px lock icon `#a3abc2`, 34 px `#2f6fdf` round button with a white arrow | one pre-rendered image (focused look; the button is decorative, Enter submits) |
| Bullets | 15 px `•` `#e8ebf4`, letter-spacing 0.3 em | one sprite per typed character, three sub-pixel phases, up to 18 (then it stops growing) |
| Text cursor | (not on the board) | 1.5x18 px `#e8ebf4` after the last bullet, blinks 530 ms like Qt's |
| Hint | `Internal drive · 512 GB`, 12 px `#6f7892` | the disk description from systemd's prompt (partition label or drive model, plus ` · /mountpoint` when systemd names one), else `Encrypted disk`. Plymouth does not know the size |
| Caps Lock | (not on the board) | `Caps Lock is on` in `#f2a65a` replaces the hint while Caps Lock is on (`Plymouth.GetCapslockState`) |
| Dots | 8 px, 10 px apart, 120 px above the bottom; opacities 1 / .55 / .25 | the throbber: a raised cosine per dot, a quarter period (0.35 s) apart, period 1.4 s, 0.25..1; its first frame is the board's 1 / .55 / .25 |
| Esc hint | 11.5 px `#4a5168`, 32 px left, 28 px bottom | pre-rendered; Esc itself is Plymouth's (details view) |
| Layout chip | keyboard icon 14 px + `EN` 11.5 px / 800 `#6f7892`, 32 px right, 28 px bottom | label from the installed theme file (see "Keyboard layout"), drawn from an A-Z atlas; hidden when unknown |

Modes:

* **Splash** (no LUKS, as on the ThinkPad; also shutdown and reboot): logo and dots only.
  Plymouth messages (`plymouth display-message`, e.g. fsck) appear on the prompt line.
* **Password** (`SetDisplayPasswordFunction`): prompt, field, bullets, hint, Esc hint, layout chip.
  Messages go under the form. Unlocked: back to logo and dots.
* **Question** (`plymouth ask-question`, rare): the prompt as given, a field without the lock icon,
  the typed answer in the prompt style (14 px `#a3abc2`; one atlas less in the initramfs).
* **System update** (offline updates, `plymouth system-update`): `Installing updates` (or
  upgrade / firmware / reset), a 260x4 bar in the Splash board's style (`rgba(255,255,255,.1)`
  track, `#5b9dff` fill), the percentage, the update's message, `Do not turn off your computer`.

### Prompts

systemd 259 (`src/cryptsetup/cryptsetup.c`) asks `Please enter passphrase for disk NAME:` with
`recovery key` / `passphrase or recovery key` variants, a `(verification)` suffix, and
`Please enter LUKS2 token PIN:`, `Please enter TPM2 PIN:`, `Please enter security token PIN:`.
NAME is `DESCRIPTION (VOLUME) on MOUNT`, `VOLUME on MOUNT`, `DESCRIPTION (VOLUME)` or `VOLUME`
(DESCRIPTION: GPT partition name, else `ID_MODEL_FROM_DATABASE`/`ID_MODEL`). The script maps these
to fixed texts: `Enter the passphrase to unlock this disk`, `Enter the recovery key to unlock this
disk`, `Enter the passphrase or recovery key to unlock this disk`, `Enter the passphrase again to
confirm`, `Enter the PIN to unlock this disk`. Anything else (another program's prompt) is shown as
given, without a trailing colon. Udev writes ATA models with `_` for spaces; a description with
underscores and no space is shown with spaces. The volume name (`luks-UUID`) is never shown.

### Keyboard layout

The script plugin has no keymap API (only two-step draws one), so `tools/system/plymouth-install.sh`
writes the label into the installed `plasma-fusion.plymouth` (`[script-env-vars]
PFKeyboardLayout=EN`; the script reads it as a global). It takes the first `XKBLAYOUT` (else
`KEYMAP`) from `/etc/vconsole.conf` and shows it as Plasma's layout indicator names it: the
`shortDescription` of that layout in `/usr/share/X11/xkb/rules/evdev.xml`, upper case (`us` ->
`EN`, `de` -> `DE`). After changing the console layout, run the installer again (with `--select`
to rebuild the initramfs). `--layout XX` sets it by hand, `--layout none` hides the chip.

## How it is built

`generators/plymouth/build.sh [OUTDIR]` (default `stage/plymouth/plasma-fusion`, about 2 s;
byte-identical output between runs, checked) runs `generators/plymouth/gen_plymouth.py` and then
`generators/plymouth/tests/check_theme.py`. Needs Python 3 with PySide6 (QtGui, QtSvg), Pillow
and NumPy; offscreen, no network.

* Every text is drawn at build time with the repository's static Manrope files
  (`fonts/manrope/static`), so nothing depends on fonts or the label plugin in the initramfs and
  no dracut change is needed. Fixed texts are shaped by HarfBuzz (Qt `QTextLayout`, kerning) and
  drawn with `QRawFont` at the exact fractional size (Qt's `QFont` rounds 18.67 px to 19 px).
* Text only known at boot uses glyph atlases (`NNN-atlas-{prompt,hint,chip}.png`): ASCII, Latin-1
  letters and `· … – — ‘ ’ “ ”`, two horizontal sub-pixel phases (chip: one), plus advance and GPOS
  kerning tables (pairs of at least 0.02 em) in the script. Unknown characters show as one `?`.
* Shapes (logo, field, icons, dots, bar) are SVG rendered with QtSvg. Positions that fall between
  device pixels are baked into the images, so the result equals a full-frame rendering.
* The lock icon and bullets sit 1 px lower than the exact CSS geometry, as in the board render.
* Crop compensation: the script cuts glyphs out of the atlases with `Image.Crop`, which copies into
  a transparent buffer where libply multiplies translucent colours by their alpha a second time
  (`blend_two_pixel_values`), so antialiased edges came out about 30 % too dark. Atlases and the
  bar fill are stored with the colour divided by that alpha (alpha raised where the division would
  pass 255), which makes the result exact over the black background (verified in the VM: apart from the
  blinking caret and the dots' phase, no pixel differs from the offline preview by more than 3/255).

Theme directory (210 PNGs + 2 files, 1.7 MB; `plymouth-populate-initrd` copies it into the
initramfs):

| File | Content |
|---|---|
| `plasma-fusion.plymouth` | `ModuleName=script`, `ImageDir`, `ScriptFile`, `[script-env-vars]` |
| `plasma-fusion.script` | `packages/plymouth/plasma-fusion.script.in` with the generated tables at `#@PF_DATA@` |
| `NNN-*.png` | per scale `NNN` = 100, 125, 133, 150, 175, 200, 250: logo, field (with / without lock), bullets (3 phases), caret, 3 dots, Esc hint, keyboard icon, bar track and fill, 10 prompt texts, 3 hint texts, 3 atlases |

Sources:

| Path | Role |
|---|---|
| `packages/plymouth/plasma-fusion.script.in` | the script (layout, prompt parsing, glyph runs, animation, callbacks) |
| `packages/plymouth/plasma-fusion.plymouth.in` | theme key file |
| `generators/plymouth/gen_plymouth.py` | images, atlases, tables |
| `generators/plymouth/build.sh` | build + checks |
| `generators/plymouth/tests/check_theme.py` | static checks: key file, every image named exists and is used, 8-bit RGBA, balanced brackets, only the string escapes Plymouth's scanner knows (`"\t"` would be `t`), no member names with a dash (`L.t-x` is a subtraction), size limit 2 MB |
| `generators/plymouth/tests/preview.py` | offline preview: composes a screen the way the script does (including the crop effect), for comparison with the board |
| `generators/plymouth/tests/vmtest.sh`, `vmrun.py`, `selftest/` | the VM test (below) |
| `tools/system/plymouth-install.sh`, `plymouth-uninstall.sh` | install, select, undo (root) |

### Scaling

Plymouth's own device scale is 1 or 2 (libply 24.004.60 `get_device_scale`: 2 when the mode is at
least 1200 px tall and denser than 192 dpi in both directions, or, when the physical size is
unknown, at least 2560 px wide; Fedora 44 does not patch this. The ThinkPad's panel reports
286x179 mm in its EDID, 170 dpi, so it gets 1; simpledrm reports a 96 dpi size, also 1). `Window.GetWidth/Height` are in its logical px and
the script plugin cannot draw finer than that, so on a device-scale-2 screen the images are
upscaled by Plymouth (softer). The script takes the area every display shows (displays are
centred on the largest one), computes `min(W/1440, H/900)` and uses the largest prepared factor up
to that value + 0.06, at least 1: 1280x800 and 1366x768 -> 1 (the 1440x900 frame is centred and
cut), 1920x1080 -> 1.25, 1920x1200 -> 4/3, 2560x1440 -> 1.5, 2560x1600 -> 1.75, 3840x2160 -> 2.
The logo and form are placed in the centred frame; dots and the bottom corners are anchored to
the bottom of the screen, like the board. Re-laid out on display hotplug (the simpledrm -> native
driver switch at boot).

## Install and select (root, on the target)

With the plasma-fusion package installed, the theme ships in
`/usr/share/plasma-fusion/plymouth/plasma-fusion/` (built in the package's `%build`; installing the
package does not change the boot splash) and the scripts default to it:

```
sudo /usr/share/plasma-fusion/tools/system/plymouth-install.sh           # files only
sudo /usr/share/plasma-fusion/tools/system/plymouth-install.sh --select  # also select it, rebuild the initramfs
```

Without the package:

```
# on the build machine
generators/plymouth/build.sh                      # -> stage/plymouth/plasma-fusion
# copy stage/plymouth/plasma-fusion and tools/system/plymouth-*.sh to the target, then there:
sudo bash plymouth-install.sh THEME_DIR           # files only (installs plymouth-plugin-script with dnf if missing)
sudo bash plymouth-install.sh --select THEME_DIR  # also select it and rebuild the running kernel's initramfs
```

`--select` saves first, once: the previous theme name and `/etc/plymouth/plymouthd.conf` in
`/var/lib/plasma-fusion/plymouth/`, and the current initramfs as
`/boot/initramfs-<kernel>.img.pre-plasma-fusion`; then runs `nice -n 10 plymouth-set-default-theme
-R plasma-fusion` and checks with `lsinitrd` that the new image holds the theme and `script.so`.
`-R` rebuilds only the running kernel's image; kernels installed later get the theme
automatically; other installed kernels keep their old splash until `dracut -f --regenerate-all`.
Re-running the installer (after a rebuild of the theme) is safe; add `--select` to put the new
files into the initramfs (without it the installer says so when the theme is the selected one).
When `plymouth-plugin-script` is missing the installer runs `dnf install`; it refuses while an
offline update is scheduled for the next boot (`/system-update`), because the transaction changes
the package database that update was prepared against, and prints a note when one is only
prepared.

### Rollback

* `sudo bash plymouth-uninstall.sh` puts the saved `plymouthd.conf` back (or selects the saved
  previous theme, default `bgrt`), rebuilds the running kernel's initramfs (`--all-kernels`: all;
  it also rebuilds when the theme was deselected by hand but the image still holds it), checks
  the theme is gone and removes the theme directory (`--keep-files` keeps it; `--remove-plugin`
  also removes `plymouth-plugin-script`, which the installer recorded as installed by it). A
  `.pre-plasma-fusion` copy is removed only once its kernel's image is verified free of the theme,
  or when that kernel has been removed since; copies for kernels whose image still holds the
  theme are kept with a note. `--dry-run` prints the steps (run it with sudo for the exact list;
  as a normal user the saved state is not readable).
* By hand: `sudo plymouth-set-default-theme -R bgrt`.
* If a boot ever looks wrong: at the GRUB menu press `e` and add `plymouth.splash=details` (text
  view; that theme is always in the initramfs) or `plymouth.enable=0`, or change the `initrd` line
  to the `.pre-plasma-fusion` copy; the older kernel's entry also still has `bgrt`. A theme error
  cannot stop the boot: Plymouth falls back to text, and Esc always shows the details view.

## Verification

Offline (laptop): `build.sh` twice (identical SHA-256), `check_theme.py` (and it catches both bugs
found during the work, see below), `tests/preview.py` at 1440x900 against `startup-1`: every element
within 1 px of the render (the render itself is offset by about +0.5 px), ink of each text within
3 % of the board.

VM test on the ThinkPad (`generators/plymouth/tests/vmtest.sh`, as user `test`, no root; work dir
`~test/.local/state/plasma-fusion/vmtest`):

* Disk: 40 MB raw image, GPT, one partition named `Internal drive` holding a LUKS2 container
  (pbkdf2, passphrase `fusion-test`), made with `cryptsetup luksFormat` on a file (no root); a
  second image with the container on the whole disk (no description).
* Initramfs: `dracut --no-hostonly` for the running kernel 7.2.7-200.fc44 as a normal user with
  modules `systemd … systemd-ask-password systemd-cryptsetup crypt dm drm plymouth` (big GPU
  drivers omitted) and `PLYMOUTH_THEME_NAME=plasma-fusion`, which changes only the initramfs's copy
  of `plymouthd.conf`; 64 MB, built in 18 s. For quick iterations `overlay` appends a cpio with a
  new theme build and a self-test unit (the base must be padded to a 4-byte boundary first, or the
  kernel ignores the appended archive).
* Boot: `qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 -machine q35 -kernel /boot/vmlinuz-$(uname -r)
  -initrd … -append 'rd.luks.uuid=… root=LABEL=pf-no-root rhgb quiet plymouth.enable=1
  plymouth.debug=stream:/dev/ttyS1 …' -device VGA,edid=on,xres=…,yres=… -display none -qmp unix:…`
  under `nice -n 10`; screenshots with QMP `screendump`, typing with `send-key`
  (`generators/plymouth/tests/vmrun.py`). `uefi` runs use OVMF, so Plymouth starts on simpledrm
  and moves to bochs-drm, like the ThinkPad (simpledrm, then i915).
* Results (all on the final build, dracut-built initramfs without overlay unless noted):
  password prompt at 1920x1200 matches the board scaled 4/3 within 1-2 px per element
  (`board-vs-vm-1920x1200.png`); typing adds bullets; Caps Lock shows the warning and clears it;
  Esc shows the details view (which also shows systemd's real prompt text) and Esc returns to the
  form; Enter with the right passphrase unlocks (no second prompt 4 s later) and the screen goes
  back to logo and dots; splash-only boot shows logo and pulsing dots; UEFI/simpledrm run
  identical to the BIOS one (hotplug path); 1280x800 with the bare disk (`Encrypted disk`),
  2560x1600 (scale 1.75), 3840x2160 splash (scale 2), two displays 1920x1200 + 1280x800 (layout for
  the shared area, everything visible on both). Self-test (overlay): message, question with typed
  answer (`backup-01` returned to the caller), recovery-key prompt with an ATA model and mount
  point (`Samsung SSD 870 EVO 1TB · /home`), token PIN, a long foreign prompt, system update at
  42 % and 87 % with a message. No script errors in the Plymouth debug logs.
* The VM work files (disk images, initramfs images) were deleted afterwards; screenshots and logs
  are in the evidence folder.

On the ThinkPad after `--select`: `plymouth-set-default-theme` prints `plasma-fusion`;
`lsinitrd /boot/initramfs-7.2.7-200.fc44.x86_64.img` lists the theme (210 images, script, key file
with `PFKeyboardLayout=EN`), `usr/lib64/plymouth/script.so` and `etc/plymouth/plymouthd.conf` with
`Theme=plasma-fusion`. Not rebooted (the rules forbid it): the first real boot is still to be seen.

## Changes made on the ThinkPad (all root)

| Change | Backup | Undo |
|---|---|---|
| `dnf install plymouth-plugin-script` (24.004.60-24.fc44; dnf transaction 16, 2026-09-29 21:41 UTC, one package). dnf mentioned the offline update that Discover (dnf5daemon-server) had prepared on 2026-09-25 11:09 (status `download-complete`, not scheduled: no `/system-update`). That update was already stale before this part: transactions 7 to 15 (2026-09-25 14:32 onwards, other work) had changed the package database it was prepared against. It has to be prepared again either way (Discover or `dnf offline`) | — | `plymouth-uninstall.sh --remove-plugin` or `dnf remove plymouth-plugin-script` |
| `/usr/share/plymouth/themes/plasma-fusion/` (212 files) | new directory | `plymouth-uninstall.sh` or `rm -r` |
| `/etc/plymouth/plymouthd.conf`: `[Daemon] Theme=plasma-fusion` (by `plymouth-set-default-theme`) | `/var/lib/plasma-fusion/plymouth/plymouthd.conf.orig`, previous theme `bgrt` in `…/previous-theme` | `plymouth-uninstall.sh` or `plymouth-set-default-theme -R bgrt` |
| `/boot/initramfs-7.2.7-200.fc44.x86_64.img` rebuilt (dracut -f) | `/boot/initramfs-7.2.7-200.fc44.x86_64.img.pre-plasma-fusion` (the 2026-09-24 image) | as above; the uninstaller deletes the copy after a successful rebuild |
| `/var/lib/plasma-fusion/plymouth/` (state: previous theme, saved conf, `installed-packages`) | new | removed by the uninstaller |

Unprivileged: `~test/.local/state/plasma-fusion/plymouth/` (theme copy, scripts, tests) and
`~test/.local/state/plasma-fusion/vmtest/out/` (VM screenshots and logs).

## Deviations from the board

* Size under the disk name: Plymouth only gets systemd's prompt, which has no size; the hint shows
  the partition label or drive model (plus mount point), else `Encrypted disk`.
* Added (not on the board): text cursor, Caps Lock warning, the question and update states.
* The keyboard label is fixed at install time (no keymap API in the script plugin).
* The layout of the no-password splash keeps the logo at the board's position (not centred), so
  nothing moves when the prompt appears.
* On screens that Plymouth itself scales by 2 the images are upscaled by Plymouth (softer).
* With two displays of different size, the content is laid out for the smaller one.
* The question answer uses the prompt style, not the field's 15 px `#e8ebf4`.

## Needs from other parts

* None required. The lead may want to add `stage/plymouth/` and the two `tools/system/` scripts to
  the deployment notes; this part is root-only and not in `tools/build.sh` (its output is not a
  HOME tree).

## Maintenance

* After changing the script or images: `generators/plymouth/build.sh`, preview with
  `PF_PLYMOUTH_META=build/meta.json generators/plymouth/build.sh OUT` and
  `generators/plymouth/tests/preview.py OUT build/meta.json out.png --size 1920x1200`, then the VM
  test (`vmtest.sh WORK setup`, `overlay`, `run NAME password|splash|selftest SIZE test disk
  [uefi]`), then `plymouth-install.sh --select` on the target.
* Plymouth script pitfalls met here: bare names inside functions resolve to globals of the same
  name (use `local.`/`global.`); `a && b` yields an operand, not 0/1; `"\t"` is `t`; `L.a-b` is a
  subtraction; sprite positions are truncated, not rounded; `Image.Crop` darkens translucent
  pixels (see above); `lsinitrd … | grep -q` fails under `pipefail`.

## Bugs found and fixed during the work

1. Keys with a dash were emitted as `L.t-passphrase.file`, so the fixed prompt texts never
   loaded; now `L["t-passphrase"]` (and `check_theme.py` rejects the form).
2. `"\t"` in the script is the letter `t` (Plymouth's scanner knows only `\n \e \0 \"`), which
   turned every `t` of drawn text into a space; removed (and checked).
3. Glyph edges ~30 % too dark after `Image.Crop` (libply blending); fixed by crop compensation.
4. The installer's `lsinitrd | grep -q` check reported a false failure under `pipefail` on the
   first `--select` (the selection itself had worked); fixed, re-run cleanly.

## Review (2026-09-29)

Adversarial review of the part as built, then fixes in the files it owns. Evidence:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/plymouth/review-*`.

What was checked:

* Build: `build.sh` twice gives byte-identical output (212 files, identical to
  `stage/plymouth/plasma-fusion`); `check_theme.py` ok; shellcheck clean on all shell scripts;
  Python files compile. No AI attribution anywhere in the part; SPDX headers present.
* Board, independently of the builder's preview: `Boot.dc.html` rendered by headless Chrome at
  device scale 4/3 (1920x1200, Google's Manrope) against the VM screenshot `vm-1920-02-typed.png`.
  Ink bounding boxes: logo, prompt, dots and Esc text identical or within 1 px; field 1 px higher
  (Chrome lays the 14 px prompt line out at 19.5 px at 4/3, the theme uses the 1x board's 19 px);
  lock icon, bullets, hint line and EN chip within 1 px. Colours exact (`#111522`, `#2f6fdf`, the
  three logo colours, text ink `#a3abc2`, `#6f7892`, `#4a5168`). `review-board-chrome133-vs-vm.png`.
* Plymouth source (24.004.60) for the calls the script relies on: `Window.GetWidth(i)` returns
  NULL past the last display (loop ends), `Window.GetX()` is the largest display offset (the
  shared area), comparisons yield 0/1, `SetRefreshRate` exists, a mode change re-runs the script
  (update state cannot stick), simpledrm devices: Fedora's `UseSimpledrmNoLuks=1` uses them at once
  when there is no LUKS.
* The exact installed boot image: a copy of `/boot/initramfs-7.2.7-200.fc44.x86_64.img` (read
  with sudo, kept 0600, deleted after) booted in a UEFI VM with the ThinkPad's own kernel and
  command line. Plymouth runs on simpledrm at 1920x1200, loads `plasma-fusion` (the image holds
  only `plasma-fusion`, `details` and `text`, plus `script.so`, `label-freetype.so`, i915 and xe),
  no script errors in its debug log; the frame is pixel-identical to the builder's splash apart
  from the dots' phase. `review-real-initramfs-uefi-splash.png`.
* ThinkPad state (read-only, sudo only to read root-only files): installed theme = the build
  byte for byte except the key file's `PFKeyboardLayout=EN`, root 0644, SELinux `usr_t`;
  `rpm -V plymouth plymouth-plugin-script` shows only `/etc/plymouth/plymouthd.conf` changed
  (`Theme=plasma-fusion`);
  `/var/lib/plasma-fusion/plymouth/` holds `previous-theme` (bgrt), `plymouthd.conf.orig`
  (72 bytes, comments only), `installed-packages`; the `.pre-plasma-fusion` backup lists bgrt,
  spinner, details and text and no Plasma Fusion file; `/boot` has 1.3 GB free. The last real boot
  (with bgrt) showed plymouth from 2.1 s to 7.2 s, simpledrm then i915 2 s later. PAM, irlume,
  fprintd and the display manager untouched: `/etc/pam.d` last changed 2026-09-28, `rpm -V` of
  pam, fprintd and irlume shows no modification, `plasmalogin.service` active since the boot at
  11:16; dnf transaction 16 installed one package.
* Rollback, end to end, without touching the system: on the ThinkPad as user `test` in a user +
  mount namespace (`unshare -r -m`) with copies of `/boot`, `/etc/plymouth`,
  `/usr/share/plymouth/themes` and an empty `/var/lib` bind-mounted over the real paths (the fake
  root has no rights on host files); real dracut, `plymouth-set-default-theme`, `lsinitrd`;
  `restorecon` stubbed. Original state (bgrt image built by dracut) -> `install --select` ->
  again (idempotent) -> without `--select` -> `uninstall --dry-run` (touches nothing) ->
  `uninstall` -> theme deselected by hand without `-R`, then `uninstall` -> a second kernel whose
  image still holds the theme -> plugin hidden (dnf path, dry run): 30 of 30 checks pass with
  the final scripts, among them: the backup is the original image (SHA-256), `plymouthd.conf`
  restored byte for byte, the rebuilt image holds bgrt and no Plasma Fusion file, the state
  directory is removed. Log:
  `review-logs/sandbox-install-uninstall.log`. `sudo plymouth-uninstall.sh --dry-run` on the
  real system prints the expected steps and changes nothing.
* Integrated: the full current stage (`tools/build.sh`) in the virtual session `rpl-int`
  (`fusion-config.sh --install` rc 0, plasmashell restarted), then the Plasma splash and the
  desktop, next to the boot frame: the same logo and colours through the sequence
  (`review-boot-sequence-integrated.png`). Plymouth itself cannot run in a virtual session.
* Core dumps on the ThinkPad since the review started (18:08): none from this review (no qemu,
  dracut, unshare, bash or plymouth entries, none during its virtual session 18:23-18:25; the
  kwin_wayland, spectacle, kscreen-doctor and kstart entries at 18:10-18:16 and 18:30-18:34
  belong to other agents' virtual sessions; the real session's KWin has run since 11:17).

Findings and fixes:

1. (medium, fixed) `plymouth-uninstall.sh` deleted the running kernel's `.pre-plasma-fusion`
   backup even when it had rebuilt nothing: with the theme deselected by hand without `-R`, the
   image still held Plasma Fusion and its backup was gone. It now rebuilds when the running
   image still holds the theme, and removes a backup only after `lsinitrd` shows that kernel's
   image is clean (an image it cannot list keeps its backup).
2. (low, fixed) Backups of other kernels were never removed: once dnf removes an old kernel, its
   55 MB copy would stay in `/boot` for good. The uninstaller now removes copies whose kernel is
   gone and keeps (with a note) copies whose image still holds the theme.
3. (low, fixed) `plymouth-install.sh` ran `dnf install` without regard to a scheduled offline
   update; it now refuses while `/system-update` exists and notes a prepared one.
4. (low, fixed) Re-running `plymouth-install.sh` without `--select` while the theme is selected
   left the initramfs copy older than the files on disk without a word; it now says so. Dry-run
   messages no longer claim that files were installed.
5. (low, fixed) `--help` of both scripts printed code lines after the comment block.
6. (low, docs, fixed) The builder's report put the invalidated Discover offline update down to
   the plugin install; dnf history shows it was stale well before (see the table above).
7. (low, docs, fixed) The device-scale rule was described as a Fedora 1.75 patch; Fedora 44's
   libply uses upstream's rule (see Scaling).

Checked and left as they are: the script, the images and the generator (no defect found in
normal use, prompts, hotplug, small and large screens, several displays). The splash-only
layout keeps the logo at the board position rather than centring it vertically (documented
deviation). The first real boot of the ThinkPad with the theme is still not observed (no
reboot allowed); the real boot image has now been booted in a VM, which is the closest check
short of that.

Rollback of the review's own changes: none on the system. The review replaced the user-owned
copies `~test/.local/state/plasma-fusion/plymouth/plymouth-{install,uninstall}.sh` with the fixed
versions (the documented rollback command now runs the fixed uninstaller); the builder's
versions are kept on the laptop in `build/rpl/orig/`.
