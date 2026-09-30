# Integration build and test gate (INT-1, 2026-09-30)

The one-pass build's last step before the deploy (PLAN.md section 5, INT-1). Built from
`git archive 321228a` (the frame flip) with `PF_LINTS=fail`; the stage is byte-identical to the
working-tree stage the lane runs used. The fix round `5417df4` changed test tooling and one test
hook in the pen widget (no user-visible change). Evidence:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/INT-1/`.

## What INT-1 changed

- **Panel frames flipped** (STYLE-1's switches): `tools/build.d/20-plasma-style.sh` defaults to the
  plain south frame and top-bar side margin 0. The dock panel is 72 px (the plate; its 16 px
  headroom is the floating margin above it), 80 px in tablet posture; the layout script,
  `fusion-config.sh`'s thickness repair (which also moves a deployed 88 px dock) and the tablet
  script use them; a laptop height saved as 88 or 96 counts as 72.
- **Lints fail the build** by default (`tools/build.sh`); the last accessibility finding (the log-out
  screen's click-to-cancel area) is resolved.
- **Fix round:** the desktop-icon test re-flows positions Folder View saved for a taller area; the
  matrix's panel check allows a floating panel's 16 px frame inset; the settings test expects the
  layout's adaptive top bar; the pen widget reports its button's place after layout.

## Results

| Suite | Result |
|---|---|
| Lints (motion, accessibility), fail mode | 0 findings |
| Offscreen: lock-screen harness (idle, prompt, messages, no password) | 4 states rendered, rc 0 |
| Offscreen: switcher key test | both cases "handled" |
| Login check unit tests (M27) | 125/125 |
| Power service offline test | 79/79 |
| Adaptive matrix (18 configurations: M01, M03, M03b, M09, M10, M10L, M11, M12, M13, M14, M16, M17, M18, M19, M22, M23, M24, M25) | 18/18 PASS (M11 touch-target dump NOT RUN, as before) |
| Desktop icons (M2), 11 steps over three sessions | 8 PASS, 3 REWRITTEN, 0 FAIL (as on 282b1a5) |
| Desktop icons, upgrade from the deployed d4afee8 | upgrade PASS (panels, dock pins, cards kept; the desktop becomes Folder View), 8 PASS, 3 REWRITTEN, 0 FAIL |
| Lane sessions on the integration stage | dock 20/20, tablet windows 35/35 and T16 7/8, layout 24/24 and 19/19, top bar 27 bars centred, quick settings 24/24 (+ M12, 960x600), launcher 8/9 and M18/M19, tablet launcher 18/19, desktop cards 5/5 and 2/2, pen 37/37, clock pill, KWIN-2 switcher/snap/hot-plug/Light |
| Settings module controls (every switch; glass Full/Reduced/Solid = X5) | 96/96 |
| Power tiers in a session (X6) | 29/29 |
| Decoration 1.0-3 with the settings page | loaded in every state; right glyphs, left circles, show on hover, Light, Defaults |
| Board side-by-sides, dark and light (desktop, launcher, overview, quick settings, snap, Alt+Tab) | on the share (`side-by-side/`) |
| Perf gate `--strict-budget`, 3 quiet runs | 10 of 25 budget rows met; against the 282b1a5 baseline everything better or the same except launcher Meta → first frame (below) |
| Repository and 50 commit messages: AI mentions | none |
| `coredumpctl` on the ThinkPad since the start of INT-1 | none |

Perf, the rows that changed most against the baseline: idle frames 0.07/s (1.23), plasmashell idle
0.50 % (1.00), KWin idle 0.03 % (0.40), dock sweep plasmashell 30.6 % (41.2), Alt+Tab first frame
226 ms (255), Alt+Tab settled 412 ms (489).

## Exceptions (for the deploy note)

- **Launcher Meta → first frame 67 ms** (63..69; baseline 51, budget 50): the median of three
  openings, whose first frames come at about 85, 65 and 43 ms. The same on the build before the
  flip (d99756b: 60-73 ms for the second opening), so it came with the launcher lanes, not with
  INT-1. Most of the launcher's first-open time and memory is the full-screen dim layer (LAUNCH-1:
  without it the first open takes 111 instead of 224 ms): the owner's dim decision.
- **Budget rows still missed** (as before INT-1, all measured better or the same as the baseline):
  whole-session idle CPU 1.07 % (0.8), dock sweep CPU and GPU, plasmashell and session memory,
  plasmashell GEM, launcher first-open GEM +71 MiB (30), KWin RSS, overview late frames and render
  time, KWin render p95 6.2 ms (3.5; the switcher's and launcher's full-screen dim layers).
- **T16** (a device folded at login, then unfolded): the windows come back 0.75 px (one device
  pixel at 4/3) taller than before when the title-bar decoration changed while folded (the test
  installs Plasma Fusion in tablet posture); with the same decoration the geometry is exact (T1).
- **T14** (panels on a fold): 62 ms with the dock's one-time gesture card already shown; the first
  fold that shows the card took 102-103 ms (budget 100).
- **Greeter preview with the new package** waits for DEPLOY-1 step 5 (the package must be
  installed system-wide first).
- Hand checks from the lanes stay hand checks: touchpad three-finger swipes, Meta+N in a real
  session, pen hardware (V1-V7), H3/H8.
