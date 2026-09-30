# Text scale and pixel grid (FusionMetrics)

Implements ADAPTIVE.md fix 2 (every Fusion text follows the user's font size) and fix 29 (font
family resolved once per window). Audit: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-adaptive/ADAPTIVE.md`
sections 3 and 3.1.

## How it works

`packages/common/FusionMetrics.qml` is the only source; `tools/build.d/{60,70,71,72,73,74,80,90}`
copy it into every package that shows text (quick settings: `contents/ui/components/`, lock screen:
`contents/lockscreen/`, splash: `contents/splash/`, the others: `contents/ui/`). Do not edit the
copies. One instance per window (an applet's root, each pop-up or Dialog item, the window
switcher, the snap flyout, the lock screen), passed down as `metrics`.

| Member | Meaning |
|---|---|
| `ts` | text scale: UI font point size / 9.75 (Manrope 13 px), clamped to 0.85-1.6, falling back to `gridUnit / 18`; exactly 1 at the Plasma Fusion default |
| `font(v)` | board px of text -> pixel size (`v * ts`) |
| `px(v)` | sizes that hold text (control heights, padding next to text, widths that hold text), snapped to whole device pixels |
| `snap(v)`, `hairline` | device-pixel grid; `hairline` is 1 device px up to scale 1.5, 2 from 1.75 |
| `dpr`, `screenScale` | the window's device pixel ratio; the switcher sets `screenScale` from its output because it sizes itself before its window exists |
| `step`, `windowSize(v)` | window sizes on a whole number of device pixels (3 px steps at 4/3; none at 1.325) |
| `family`, `displayFamily` | Manrope and Space Grotesk, resolved once (one `Qt.fontFamilies()` per window) |
| `touch`, `portrait`, `compactWidth`, `compactHeight`, `wide`, `hit(v, edge)` | modes and breakpoints for the adaptive and tablet work (44/48 px touch targets) |

Three classes of values: design constants (radii, 1 px edges, focus rings, shadows, dots, glyph
strokes, the clock's large figures, the dock tile) are never scaled; text and everything that holds
text goes through `font()` / `px()`; screen-driven values come from `area`. FusionMetrics holds
only bindings (no timers, nothing per frame).

The layout script (`packages/look-and-feel/common/contents/layouts/org.kde.plasma.desktop-layout.js`)
computes the same text scale at layout time from `kdeglobals [General] font`: top bar
`round(34 * TS)` px, `GRID_UNIT = 2 * round(9 * TS)`, card sizes `cells(content * TS + 28)`. A font
change after the layout was built resizes the widgets' contents at once; the top-bar thickness and
card sizes follow at the next layout rebuild.

## Verification (2026-09-30, builder `fm`, finished by the lead)

- Default font, new vs old build in private sessions: 1440x900 scale 1 dark/light 99.8 % of pixels
  identical (mismatches only in live values: clock, CPU/memory, weather); 1920x1200 at 4/3 and at
  1.325 within run-to-run noise (98.4-98.6 % both between two runs of the same build and old vs
  new); switcher captions within 1 px.
- +3 pt (12.75): top bar 44 px; app name, menu titles and pill text 17 px cap height (±1); cards
  228 px wide, content scaled to fit; launcher, quick settings, calendar, switcher, snap flyout,
  lock screen (idle and prompt) without clipped text; 1366x768 at +3 pt checked too.
- plasmashell, 3 cycles each at 1920x1200 4/3: start-up CPU 233-266 vs 244-253 ticks, idle 16-27 vs
  39-42 ticks per 20 s, opening calendar/launcher/quick settings unchanged, RSS 387-390 MB both.
- qmllint: identical warning signatures to the old build in every package.
- Lock screen offscreen harness (`packages/lockscreen/test/harness.py`, which now stages
  FusionMetrics): idle, prompt, messages and no-password states load with no QML errors.
- The only warning seen, "Panel.qml: Binding loop detected for property minPanelHeight" (stock
  Plasma), appears in old-build runs as well.

Evidence: laptop `build/fm/` (runs `vsession-out/fm-{h,n,n2,p}-*`, contact sheets `sheet-*.png`).
