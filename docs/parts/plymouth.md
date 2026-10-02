# Part: Plymouth boot splash and disk unlock (`plasma-fusion`)

Status 2026-10-01: reworked to the look of the log-in splash (Splash board, owner's wish: "it would
add a nice touch making it personal"), with the owner's name in the greeting. Built, checked
offline and tested in QEMU/KVM on the laptop with the real Plymouth 24.004.60 and systemd 259
(LUKS2 unlock with a wrong passphrase first, every prompt kind, messages, system update, shutdown
and reboot screens, simpledrm handover, 1440x900, 1920x1200, 2880x1800 at Plymouth device scale 1
and 2, two displays); install, greeting and rollback tested as fake root in a user and mount
namespace. Not yet installed on the ThinkPad: it still has the first version (Boot board, black
screen) from 2026-09-29, see "History". Evidence of this version:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-10-01-plymouth-splash/`.

The Plymouth theme takes the look of the Splash board (`design/boards/Splash.dc.html`, picture
`design/previews/Splash.webp`): the blurred Dusk Ridge wallpaper, the three-circle logo inside two
orbit rings with three small dots travelling along the outer ring, "Welcome back, <name>" in Space
Grotesk, a thin progress bar driven by Plymouth's boot progress, "Starting up" under it and the
"Plasma Fusion" mark in the bottom left corner. When a disk passphrase is asked, the unlock form of
the Boot board (`design/boards/Boot.dc.html`) takes the place of the greeting under the logo, then
the greeting returns. Shutdown, reboot and system updates show their own heading instead of the
greeting. Script plugin (`plymouth-plugin-script`), no compiled code. It is a system part (root),
outside the HOME stage.

## What it looks like

Board values are logical px of the 1440x900 board; the theme draws them at a scale factor chosen
from the screen size (see "Scaling"). On the ThinkPad (1920x1200, Plymouth device scale 1) the
factor is 4/3, the same as the Plasma session, so boot, log-in splash and desktop line up: at that
size the background is the log-in splash's own image, pixel for pixel, and the logo, rings,
greeting and bar sit where the log-in splash draws them.

| Element | Board | Implementation |
|---|---|---|
| Background | Dusk Ridge layer: `blur(26px)`, `scale(1.08)`, opacity 0.28 over `#0b0e1b` | one 1920x1200 image, made by `generators/look-and-feel/splash_background.py` (the same file as the log-in splash's `background.png`); the script scales it to cover the screen (Plymouth's bilinear `Image.Scale`), centred; on a portrait screen the sun stays at 68 % of the width, as in the log-in splash. Fades in from black over 0.5 s at boot, shutdown and reboot |
| Orbit rings | r 120 / 190 around (720, 380), 1.5 px white at 6 % / 4 % | one image |
| Logo | circles r 46 at (720, 352), (689, 406), (751, 406), group blended `screen` | opaque circles in the blended colours `#63a3ff`, `#f3ac6f`, `#46c8ba` (as `Splash.qml`); board render and theme agree within 1 level |
| Orbit dots | 10 px `#5b9dff` at 12 o'clock, 8 px `#f2a65a` at (900, 315), 8 px `#3cc4b0` at (555, 475) | they travel together clockwise along the outer ring, one turn in 16 s, from the board positions (as `Splash.qml`); each dot is drawn at the nearest of 2x2 sub-pixel positions (separate images, no crop) |
| Greeting | `Welcome back, Alex`, Space Grotesk 30 px / 600 `#e8ebf4`, column top 610 px | `Welcome back, <name>` drawn on the target by the installer (see "The greeting"); without a name `Welcome back` |
| Progress bar | 260x4, radius 2, `rgba(255,255,255,.1)` track, `#5b9dff` fill, 18 px under the greeting | the fill follows Plymouth's boot progress (`SetBootProgressFunction`, never backwards); drawn as a fixed rounded head, a one-pixel column stretched with `Image.Scale` and a rounded tail, so no `Image.Crop` is involved |
| Status | 13 px `#8f98b3`, 18 px under the bar | `Starting up`; a Plymouth message (`plymouth display-message`, e.g. fsck) takes its place |
| Mark | 18 px logo (opacities .9 / .9 / .85) + `Plasma Fusion` 13 px / 700 `#8f98b3`, 40 px left, 32 px bottom | one image, anchored to the bottom left corner of the screen |

While a prompt is shown (Boot board's form, moved under the emblem; the emblem and the moving dots
stay, the greeting, bar, status and mark are hidden):

| Element | Board (Boot) | Implementation |
|---|---|---|
| Prompt | 14 px Manrope 400 `#a3abc2` | at the greeting's line (top 610 px); pre-rendered image per prompt kind (see "Prompts"); other prompts are drawn from a glyph atlas |
| Field | 360x46, radius 23, `#111522`, 1.5 px `#5b9dff` border, 17 px lock icon `#a3abc2`, 34 px `#2f6fdf` round button with a white arrow | 14 px under the prompt; one pre-rendered image (focused look; the button is decorative, Enter submits) |
| Bullets | 15 px `•` `#e8ebf4`, letter-spacing 0.3 em | one sprite per typed character, three sub-pixel phases, up to 18 (then it stops growing) |
| Text cursor | (not on the board) | 1.5x18 px `#e8ebf4` after the last bullet, blinks 530 ms like Qt's |
| Caption | `Internal drive · 512 GB`, 12 px `#6f7892` | 13 px `#8f98b3` (the Splash board's status style, readable on the lighter background); the disk description from systemd's prompt (partition label or drive model, plus ` · /mountpoint` when systemd names one), else `Encrypted disk`. Plymouth does not know the size |
| Caps Lock | (not on the board) | `Caps Lock is on` in `#f2a65a` replaces the caption while Caps Lock is on (`Plymouth.GetCapslockState`) |
| Wrong passphrase | (not on the board) | `Wrong passphrase, try again` (`Wrong recovery key, try again`, `Wrong PIN, try again`) in `#f2a65a` replaces the caption when the same prompt is asked again (see "Wrong passphrase") |
| Esc hint | 11.5 px `#4a5168`, 32 px left, 28 px bottom | `#6f7892`, 40 px left, on the mark's centre line (it takes the mark's place); Esc itself is Plymouth's (details view) |
| Layout chip | keyboard icon 14 px + `EN` 11.5 px / 800 `#6f7892`, 32 px right, 28 px bottom | `#8f98b3`, 40 px right, on the same centre line; label from the installed theme file (see "Keyboard layout"), drawn from an A-Z atlas; hidden when unknown |

Modes:

* **Boot**: background, emblem, greeting, bar with the boot progress, `Starting up`, mark.
  Plymouth messages replace `Starting up`.
* **Password** (`SetDisplayPasswordFunction`): prompt, field, bullets, caption, Esc hint, layout
  chip. Messages go under the form. Unlocked: back to the greeting and the bar.
* **Question** (`plymouth ask-question`, rare): the prompt as given, a field without the lock icon,
  the typed answer in the prompt style (14 px `#a3abc2`; one atlas less in the initramfs).
* **Shutdown / reboot** (`Plymouth.GetMode()`): `Shutting down…` / `Restarting…` in the greeting's
  place, no bar, no status line (messages appear there), the mark.
* **System update** (offline updates, `plymouth system-update`): `Installing updates` (or
  `Upgrading the system`, `Updating the firmware`, `Resetting the system`) in the greeting's place,
  the bar with the update's progress, `42 %` (and ` · ` the update's message) on the status line,
  `Do not turn off your computer` under it. A mode change during the boot re-runs the script; only
  boot, shutdown and reboot fade in, so a change to the update mode does not flash.

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

### Wrong passphrase

systemd-cryptsetup asks again with the same prompt when a passphrase did not unlock the disk (in
between, Plymouth shows the splash while the key is checked). The script remembers the last password
prompt that was answered; when the next password prompt has the same text, the caption says
`Wrong passphrase, try again` (recovery key and PIN prompts: their own wording) until another
prompt comes. Caps Lock takes precedence. Two disks never share a prompt (the volume name is part
of it), except token or TPM2 PIN prompts, which name no disk: a second PIN prompt right after the
first would also show `Wrong PIN, try again`. After Esc (details) and back, Plymouth re-runs the
script and the caption is the disk name again. The first version showed only an empty field again.

### Keyboard layout

The script plugin has no keymap API (only two-step draws one), so `tools/system/plymouth-install.sh`
writes the label into the installed `plasma-fusion.plymouth` (`[script-env-vars]
PFKeyboardLayout=EN`; the script reads it as a global). It takes the first `XKBLAYOUT` (else
`KEYMAP`) from `/etc/vconsole.conf` and shows it as Plasma's layout indicator names it: the
`shortDescription` of that layout in `/usr/share/X11/xkb/rules/evdev.xml`, upper case (`us` ->
`EN`, `de` -> `DE`). After changing the console layout, run the installer again (with `--select`
to rebuild the initramfs). `--layout XX` sets it by hand, `--layout none` hides the chip.

### The greeting

Nobody is logged in at boot, so the greeting names the machine's owner: the only human account
(UID from `UID_MIN` to `UID_MAX` of `/etc/login.defs`, default 1000-60000; a login shell listed in
`/etc/shells`, not `nologin` or `false`; not `nobody`, `nfsnobody` or `plasmalogin`), with the same
rule as the log-in splash (`Splash.qml`): the first word of the account's full name (GECOS, up to
the first comma), else the login name. With no human account or several, the line is only
`Welcome back`. `--user LOGIN` picks the account on a machine with several (the test device has a
`test` account besides the owner's), `--name TEXT` sets any text, `--name none` shows no name; the
choice is remembered in `/var/lib/plasma-fusion/plymouth/greeting` (`user=LOGIN`, `name=TEXT` or
`none`) and used by later runs, `--name auto` forgets it. A name the font cannot draw (characters
outside Space Grotesk's coverage) falls back to the login name, then to no name; a name wider than
1000 px ends with `…`.

The early boot has only `label-freetype` with one font file and no family names, so the greeting
is an image: `NNN-greeting.png` per scale, drawn by `greeting/greeting.py` (Pillow; HarfBuzz
shaping through libraqm, which Fedora's `python3-pillow` has) with the Space Grotesk file next to
it. The build draws the generic `Welcome back` with the same program; the installer draws the name
over the copies it installs. The name changes only when the installer runs again: after renaming
the account (or to change the choice) run `plymouth-install.sh --select` again, which draws the
greeting and rebuilds the initramfs. Without `python3-pillow` the installer keeps the generic
greeting and says so (it does not install Pillow; the plasma-fusion package requires it anyway).

## How it is built

`generators/plymouth/build.sh [OUTDIR]` (default `stage/plymouth/plasma-fusion`, about 8 s;
byte-identical output between runs, checked) runs `generators/plymouth/gen_plymouth.py` and then
`generators/plymouth/tests/check_theme.py`. Needs Python 3 with PySide6 (QtGui, QtSvg), Pillow
(with libraqm) and NumPy; offscreen, no network.

* Every fixed text is drawn at build time with the repository's static Manrope and Space Grotesk
  files (`fonts/*/static`), so nothing depends on fonts or the label plugin in the initramfs and no
  dracut change is needed. Fixed texts are shaped by HarfBuzz (Qt `QTextLayout`, kerning) and
  drawn with `QRawFont` at the exact fractional size (Qt's `QFont` rounds 18.67 px to 19 px).
* The greeting is drawn by `generators/plymouth/greeting.py` (see "The greeting"); the build copies
  it, its layout (`layout.json`: font, size, colour, the box and pen of every scale, the font's
  character coverage) and the font with its licence into `OUTDIR/greeting/`.
* Text only known at boot uses glyph atlases (`NNN-atlas-{prompt,status,chip}.png`): ASCII, Latin-1
  letters and `· … – — ‘ ’ “ ”`, two horizontal sub-pixel phases (chip: one), plus advance and GPOS
  kerning tables (pairs of at least 0.02 em) in the script. Unknown characters show as one `?`.
* Shapes (logo, rings, dots, field, icons, bar) are SVG rendered with QtSvg. Positions that fall
  between device pixels are baked into the images, so the result equals a full-frame rendering.
* The lock icon and bullets sit 1 px lower than the exact CSS geometry, as in the board render.
* Crop compensation: the script cuts glyphs out of the atlases with `Image.Crop`, which copies into
  a transparent buffer where libply multiplies translucent colours by their alpha a second time
  (`blend_two_pixel_values`), so antialiased edges came out about 30 % too dark. Atlases are stored
  with the colour divided by that alpha; where that would pass 255 the alpha is raised and the
  background colour that the extra alpha hides is added in. The background is the mean colour of
  the Dusk Ridge image under each atlas's lines (prompt line, status line, bottom right corner), so
  the result is exact over that colour and within a few levels elsewhere (VM against the offline
  preview: at most 5/255 apart from the moving dots, the caret and the bar). Nothing else is
  cropped: the dots have one image per sub-pixel position and the bar fill is stretched.

Theme directory (351 PNGs + 2 files, 2.4 MB, all copied into the initramfs by
`plymouth-populate-initrd`; `greeting/` is not installed):

| File | Content |
|---|---|
| `plasma-fusion.plymouth` | `ModuleName=script`, `ImageDir`, `ScriptFile`, `[script-env-vars]` |
| `plasma-fusion.script` | `packages/plymouth/plasma-fusion.script.in` with the generated tables at `#@PF_DATA@` |
| `background.png` | the blurred wallpaper, 1920x1200, for every scale (270 KB) |
| `NNN-*.png` | per scale `NNN` = 100, 125, 133, 150, 175, 200, 250: rings, logo, 3 dots x 4 sub-pixel positions, greeting, 6 headings, bar (track, head, body, tail), 7 status-size texts, 6 prompt texts, field (with / without lock), bullets (3 phases), caret, Esc hint, keyboard icon, mark, 3 atlases |
| `greeting/` | `greeting.py`, `layout.json`, `SpaceGrotesk-SemiBold.ttf`, `OFL-SpaceGrotesk.txt`: for the installer only |

Sources:

| Path | Role |
|---|---|
| `packages/plymouth/plasma-fusion.script.in` | the script (layout, background, orbit, bar, prompt parsing, glyph runs, animation, callbacks) |
| `packages/plymouth/plasma-fusion.plymouth.in` | theme key file |
| `generators/plymouth/gen_plymouth.py` | images, atlases, tables, `greeting/` |
| `generators/plymouth/greeting.py` | draws the greeting (build and target) |
| `generators/look-and-feel/splash_background.py` | the background (shared with the log-in splash) |
| `generators/plymouth/build.sh` | build + checks |
| `generators/plymouth/tests/check_theme.py` | static checks: key file, every image named exists and is used, 8-bit RGBA, `greeting/` complete and matching the greeting images, balanced brackets, only the string escapes Plymouth's scanner knows (`"\t"` would be `t`), no member names with a dash (`L.t-x` is a subtraction), installed part at most 3 MB |
| `generators/plymouth/tests/preview.py` | offline preview: composes a screen the way the script does (including the crop effect), for comparison with the board |
| `generators/plymouth/tests/vmtest.sh`, `vmrun.py`, `selftest/` | the VM test (below) |
| `tools/system/plymouth-install.sh`, `plymouth-uninstall.sh` | install, greeting, select, undo (root) |

### Scaling

Plymouth's own device scale is 1 or 2 (libply 24.004.60 `get_device_scale`: 2 when the mode is at
least 1200 px tall and denser than 192 dpi in both directions, or, when the physical size is
unknown, at least 2560 px wide; Fedora 44 does not patch this. The ThinkPad's panel reports
286x179 mm in its EDID, 170 dpi, so it gets 1; simpledrm reports a 96 dpi size, also 1; a 14"
2880x1800 panel gets 2). `Window.GetWidth/Height` are in its logical px and the script plugin
cannot draw finer than that, so on a device-scale-2 screen the images are upscaled by Plymouth
(softer). The script takes the area every display shows (displays are centred on the largest
one), computes `min(W/1440, H/900)` and uses the largest prepared factor up to that value + 0.06,
at least 1: 1280x800 and 1366x768 -> 1 (the 1440x900 frame is centred and cut), 1920x1080 -> 1.25,
1920x1200 -> 4/3, 2560x1440 -> 1.5, 2560x1600 -> 1.75, 3840x2160 -> 2. The emblem, the column and
the form are placed in the centred frame (so the emblem's centre is 70 px above the middle of the
screen and the greeting 160 px below it, as in `Splash.qml`); the mark, the Esc hint and the layout
chip are anchored to the bottom corners. The background covers the largest display. Re-laid out on
display hotplug (the simpledrm -> native driver switch at boot).

## Install and select (root, on the target)

With the plasma-fusion package installed, the theme ships in
`/usr/share/plasma-fusion/plymouth/plasma-fusion/` (built in the package's `%build`; installing the
package does not change the boot splash) and the scripts default to it:

```
sudo /usr/share/plasma-fusion/tools/system/plymouth-install.sh           # files only
sudo /usr/share/plasma-fusion/tools/system/plymouth-install.sh --select  # also select it, rebuild the initramfs
sudo /usr/share/plasma-fusion/tools/system/plymouth-install.sh --select --user LOGIN  # greet that account's owner
```

Without the package:

```
# on the build machine
generators/plymouth/build.sh                      # -> stage/plymouth/plasma-fusion (with greeting/)
# copy stage/plymouth/plasma-fusion (with greeting/) and tools/system/plymouth-*.sh to the target, then there:
sudo bash plymouth-install.sh THEME_DIR           # files only (installs plymouth-plugin-script with dnf if missing)
sudo bash plymouth-install.sh --select THEME_DIR  # also select it and rebuild the running kernel's initramfs
```

The installer first decides whom to greet (and stops, changing nothing, when `--user` names no
account), then installs the plugin if needed, the files (a fresh copy swapped in), the keyboard
label and the greeting (`python3 -I -B THEME_DIR/greeting/greeting.py`: isolated, nothing from the
user's environment), and `restorecon`s the directory. `--select` saves first, once: the previous
theme name and `/etc/plymouth/plymouthd.conf` in `/var/lib/plasma-fusion/plymouth/`, and the
current initramfs as `/boot/initramfs-<kernel>.img.pre-plasma-fusion`; then runs `nice -n 10
plymouth-set-default-theme -R plasma-fusion` and checks with `lsinitrd` that the new image holds the
theme and `script.so`. `-R` rebuilds only the running kernel's image; kernels installed later get
the theme automatically; other installed kernels keep their old splash until `dracut -f
--regenerate-all`. Re-running the installer (after a rebuild of the theme or a name change) is
safe; add `--select` to put the new files into the initramfs (without it the installer says so
when the theme is the selected one). Shutdown and reboot read the installed files directly, so
they show a new build at once. When `plymouth-plugin-script` is missing the installer runs `dnf
install`; it refuses while an offline update is scheduled for the next boot (`/system-update`),
because the transaction changes the package database that update was prepared against, and prints
a note when one is only prepared.

### Rollback

* `sudo bash plymouth-uninstall.sh` puts the saved `plymouthd.conf` back (or selects the saved
  previous theme, default `bgrt`), rebuilds the running kernel's initramfs (`--all-kernels`: all;
  it also rebuilds when the theme was deselected by hand but the image still holds it), checks
  the theme is gone and removes the theme directory (`--keep-files` keeps it; `--remove-plugin`
  also removes `plymouth-plugin-script`, which the installer recorded as installed by it) and the
  remembered greeting choice. A `.pre-plasma-fusion` copy is removed only once its kernel's image
  is verified free of the theme, or when that kernel has been removed since; copies for kernels
  whose image still holds the theme are kept with a note. `--dry-run` prints the steps (run it
  with sudo for the exact list; as a normal user the saved state is not readable).
* Back to the first version (Boot board, black screen) without uninstalling: run the installer of
  that build with `--select` (its theme directory replaces this one).
* By hand: `sudo plymouth-set-default-theme -R bgrt`.
* If a boot ever looks wrong: at the GRUB menu press `e` and add `plymouth.splash=details` (text
  view; that theme is always in the initramfs) or `plymouth.enable=0`, or change the `initrd` line
  to the `.pre-plasma-fusion` copy; the older kernel's entry also still has its own splash. A theme
  error cannot stop the boot: Plymouth falls back to text, and Esc always shows the details view.

## Verification (2026-10-01, on the laptop)

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-10-01-plymouth-splash/`.

* Build: `build.sh` twice gives byte-identical output; `check_theme.py` ok (351 images, 2485 KiB);
  shellcheck clean on all shell scripts; `tools/build.sh` (whole tree, scratch stage) passes;
  `reuse lint` (6.2.0) compliant.
* Board: `tests/preview.py` at 2880x1800 (scale 2) with the greeting drawn for `Alex`, against
  `design/previews/Splash.webp`: the greeting's ink box identical within 2 px, the mark identical,
  the logo colours within 1 level, the bar 1 px lower (Chrome lays the 30 px line out at 38.5 px
  at 2x; the theme uses the 1x board's 39 px), the background within 5 levels (99th percentile)
  (`compare-board-vs-preview-*.png`). The real Plymouth frame from the VM at 2880x1800 against the
  board: the same (`compare-board-vs-vm-2880x1800.png`).
* Previews (`preview.py`): boot at 1440x900 (scale 1), 1920x1200 (4/3), 2880x1800 (2), 1366x768,
  portrait 1200x1920; the fade-in; password empty, typing, wrong passphrase, Caps Lock; recovery
  key with a drive model and mount point; question; boot message; system update; shutdown; reboot.
* VM (QEMU/KVM, the laptop's kernel 7.2.7-200.fc44, an initramfs built by dracut as a normal user
  with the laptop's own theme, plus an overlay with this theme, `plymouthd.conf` selecting it and
  `script.so` taken from the signed `plymouth-plugin-script-24.004.60-24.fc44` RPM without
  installing it; the laptop has neither installed):
  * password at 1920x1200 with real systemd-cryptsetup: a wrong passphrase first, which showed
    `Wrong passphrase, try again` on the prompt asked again; typing adds bullets; Caps Lock shows
    the warning and clears it; Esc shows the details view and Esc returns to the form; Enter with
    the right passphrase unlocks and the screen goes back to the greeting, the bar (boot progress
    still rising) and `Starting up`;
  * self-test: message on the status line, a prompt asked twice, question with typed answer
    (`backup-01` returned to the caller), recovery-key prompt with an ATA model and mount point,
    token PIN, a long foreign prompt (cut with `…`), system update at 42 % and 87 % with a message,
    `plymouth change-mode --shutdown` and `--reboot` (`Shutting down…`, `Restarting…`), back to
    boot;
  * splash at 1440x900, 2880x1800 and, through OVMF, 1920x1200 starting on simpledrm and moving to
    bochs-drm (hotplug path): orbit, bar and layout as in the previews; VM against the offline
    preview at most 4/255 (1920x1200) and 5/255 (scaled background at the other sizes) apart from
    the dots, the caret and the bar (`diff-vm-vs-preview-*.png`);
  * 2880x1800 with `plymouth.force-scale=2` (as on a 14" 2880x1800 panel): the 1x layout upscaled
    by Plymouth, softer, everything in place;
  * two displays 1920x1200 + 1280x800: laid out for the smaller one, the background covers both
    (the harness's automatic wait assumes the larger display's scale, so this run ended with the
    "no field" screenshot, which shows the form correctly on both);
  * no script errors in the Plymouth debug logs.
* Install and rollback, end to end, as fake root in a user and mount namespace (`unshare -r -m`,
  copies of `/boot`, `/etc/plymouth`, the themes, `/usr/lib64/plymouth` with `script.so`, and an
  empty `/var/lib` bound over the real paths; real dracut, `plymouth-set-default-theme`,
  `lsinitrd`; `restorecon` stubbed): 26 of 26 checks pass (`sandbox-install-uninstall.log`,
  script `sandbox-inner.sh`), among them: `--select` with the default rule draws the only account's
  name, the image holds exactly the installed greeting and no `greeting/`, files are 0644,
  `--name none` installs the generic image byte for byte and is remembered, a later run without
  options keeps it, a long name with accents ends with `…`, `--user` and `--name auto` record and
  forget the choice, an unknown `--user` stops before any change, without Pillow the install goes
  on with the generic greeting, the uninstaller restores `plymouthd.conf` byte for byte, cleans
  the image and removes the backup, the theme and the state including the greeting record.
* Not checked: a real boot on hardware (the ThinkPad still has the first version; nothing was
  installed there by this work), Plymouth's boot progress over a whole real boot (it is
  time-based from `/var/lib/plymouth/boot-duration`, which the initramfs only reads after the
  switch to the real root; on the first boot with the theme it estimates 60 s), the plasma-fusion
  RPM build with the new `greeting/` (the spec copies the whole theme directory, so no change is
  needed).

## History: the first version (Boot board, 2026-09-29)

The first version followed the Boot board only: black screen, a 96 px logo 250 px from the top,
three pulsing dots 120 px above the bottom, and the same unlock form. It was tested in a VM on the
ThinkPad and installed and selected there; the notes below are its record and still describe what
the ThinkPad has until this version is installed. Evidence:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/plymouth/`.

VM test of the first version (on the ThinkPad, as user `test`, no root; work dir
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

### Changes made on the ThinkPad (all root, first version)

| Change | Backup | Undo |
|---|---|---|
| `dnf install plymouth-plugin-script` (24.004.60-24.fc44; dnf transaction 16, 2026-09-29 21:41 UTC, one package). dnf mentioned the offline update that Discover (dnf5daemon-server) had prepared on 2026-09-25 11:09 (status `download-complete`, not scheduled: no `/system-update`). That update was already stale before this part: transactions 7 to 15 (2026-09-25 14:32 onwards, other work) had changed the package database it was prepared against. It has to be prepared again either way (Discover or `dnf offline`) | — | `plymouth-uninstall.sh --remove-plugin` or `dnf remove plymouth-plugin-script` |
| `/usr/share/plymouth/themes/plasma-fusion/` (212 files) | new directory | `plymouth-uninstall.sh` or `rm -r` |
| `/etc/plymouth/plymouthd.conf`: `[Daemon] Theme=plasma-fusion` (by `plymouth-set-default-theme`) | `/var/lib/plasma-fusion/plymouth/plymouthd.conf.orig`, previous theme `bgrt` in `…/previous-theme` | `plymouth-uninstall.sh` or `plymouth-set-default-theme -R bgrt` |
| `/boot/initramfs-7.2.7-200.fc44.x86_64.img` rebuilt (dracut -f) | `/boot/initramfs-7.2.7-200.fc44.x86_64.img.pre-plasma-fusion` (the 2026-09-24 image) | as above; the uninstaller deletes the copy after a successful rebuild |
| `/var/lib/plasma-fusion/plymouth/` (state: previous theme, saved conf, `installed-packages`) | new | removed by the uninstaller |

Unprivileged: `~test/.local/state/plasma-fusion/plymouth/` (theme copy, scripts, tests) and
`~test/.local/state/plasma-fusion/vmtest/out/` (VM screenshots and logs).

### Bugs found and fixed during the first version

1. Keys with a dash were emitted as `L.t-passphrase.file`, so the fixed prompt texts never
   loaded; now `L["t-passphrase"]` (and `check_theme.py` rejects the form).
2. `"\t"` in the script is the letter `t` (Plymouth's scanner knows only `\n \e \0 \"`), which
   turned every `t` of drawn text into a space; removed (and checked).
3. Glyph edges ~30 % too dark after `Image.Crop` (libply blending); fixed by crop compensation.
4. The installer's `lsinitrd | grep -q` check reported a false failure under `pipefail` on the
   first `--select` (the selection itself had worked); fixed, re-run cleanly.

### Review of the first version (2026-09-29)

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

## Deviations from the boards

* Greeting: the board's `Alex` is the first word of the owner's full name (the log-in splash's
  rule), drawn at install time; with no or several human accounts and no `--user`, only `Welcome
  back`.
* Status line: `Starting up` (Plymouth knows no Plasma stages); messages replace it.
* Progress: Plymouth's time-based boot progress, not Plasma's start-up stages.
* Orbit dots move (as in the log-in splash); the board is a still picture.
* The unlock form sits under the emblem (Splash layout) instead of under the Boot board's 96 px
  logo; the Boot board's three pulsing dots are replaced by the orbiting dots.
* Caption under the field: 13 px `#8f98b3` instead of 12 px `#6f7892`; Esc hint `#6f7892` instead
  of `#4a5168`, layout chip `#8f98b3` instead of `#6f7892`: the Boot board's greys are for black and
  get too faint on the lighter background. Both corners are 40 px from the edges on the mark's
  centre line (the Boot board: 32 px, 28 px from the bottom), so the Esc hint takes the mark's place.
* Size under the disk name: Plymouth only gets systemd's prompt, which has no size; the caption
  shows the partition label or drive model (plus mount point), else `Encrypted disk`.
* Added (not on the boards): text cursor, Caps Lock warning, wrong-passphrase caption, the question,
  update, shutdown and reboot states, the fade-in.
* The keyboard label is fixed at install time (no keymap API in the script plugin).
* On screens that Plymouth itself scales by 2 the images are upscaled by Plymouth (softer).
* With two displays of different size, the content is laid out for the smaller one.
* The question answer uses the prompt style, not the field's 15 px `#e8ebf4`.

## Needs from other parts

* None required. The background comes from `generators/look-and-feel/splash_background.py`; a
  change there changes both splashes. The lead may want to add `stage/plymouth/` and the two
  `tools/system/` scripts to the deployment notes; this part is root-only and not in
  `tools/build.sh` (its output is not a HOME tree).

## Maintenance

* After changing the script or images: `generators/plymouth/build.sh`, preview with
  `PF_PLYMOUTH_META=build/meta.json generators/plymouth/build.sh OUT` and
  `generators/plymouth/tests/preview.py OUT build/meta.json out.png --size 1920x1200 --state
  splash` (or `password`, `question`; `--mode shutdown|reboot|updates`, `--progress P` for an
  update, `--boot F` for the boot progress, `--retry`, `--frame N`). To see a name, draw it into a
  copy first: `python3 OUT/greeting/greeting.py OUT/greeting/layout.json OUT --name Alex`.
* VM test: `vmtest.sh WORK setup`, `overlay THEME_DIR`, `run NAME password|splash|selftest SIZE
  test disk [uefi]`. On a machine without the theme and plugin installed (the laptop):
  `PF_BASE_THEME= vmtest.sh WORK setup`, then `PF_SCRIPT_SO=…/script.so PF_GREETING_NAME=Alex
  PF_LAYOUT_LABEL=EN vmtest.sh WORK overlay THEME_DIR` (`script.so` from `dnf download
  plymouth-plugin-script` and `rpm2cpio | cpio -id`) and only `test` runs; `PF_APPEND=
  "plymouth.force-scale=2"` emulates a HiDPI panel, `PF_SECOND_HEAD=1280x800` a second display.
* Then `plymouth-install.sh --select` on the target.
* Plymouth script pitfalls met here: bare names inside functions resolve to globals of the same
  name (use `local.`/`global.`); `a && b` yields an operand, not 0/1; `"\t"` is `t`; `L.a-b` is a
  subtraction; sprite positions are truncated, not rounded; `Image.Crop` darkens translucent
  pixels (see above); `SetX`/`SetOpacity` only redraw when the value changes, `SetImage` always;
  a mode change re-runs the script; `lsinitrd … | grep -q` fails under `pipefail`.
