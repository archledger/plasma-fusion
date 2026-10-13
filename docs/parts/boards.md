# Part: design boards and previews

The boards in `design/boards/` decide every colour, size and drawing of the theme
([`design/README.md`](../../design/README.md) shows them and routes each surface to its part page).
`design/previews/` holds one picture per board, rendered from the sources in this repository;
`design/boards/canvas.json` is the canvas index (`w`/`h` per board, `order` for rendering).

## Rendering

| Path | Purpose |
|---|---|
| `design/render/render.py` | renders the boards to `design/previews/` (headless Chrome at 2x, WebP out); `--check` renders to a scratch directory and diffs against the committed previews |
| `design/render/runtime.js` | the board template language in a plain browser (`x-dc`, `helmet`, `sc-for`, `sc-if`, `{{...}}`, `dc-import`, `DCLogic`) — the authoring canvas's runtime is not in this repository |
| `design/render/tests/render_test.py` | check mode's comparison contract (identical, close, stale, size-mismatched and missing previews) |
| `design/render/tests/runtime_test.py` | the board runtime in a browser: loops, conditions, imports, SVG namespaces and the failure propagation (needs Chrome, like rendering) |

    design/render/render.py                   # every board, in canvas order
    design/render/render.py NAME.dc.html ...  # only the named boards
    design/render/render.py --check           # diff fresh renders against the committed previews

Requires `google-chrome` (or `CHROME=...`) and Pillow, and no network: each board is served with
the fonts this repository bundles (`fonts/`) in place of its Google Fonts stylesheet. One browser
process owns the whole render over Chrome's remote-debugging pipe: it navigates, waits for the
runtime's `data-board-rendered` marker through `Runtime.evaluate` (a board that does not finish, or
one whose template expressions fail, or one whose picture does not match canvas.json's dimensions,
fails the run) and captures that same page, so the picture
cannot come from a page that was not validated. `--check` exits nonzero for a missing committed
preview, a size mismatch, a mean per-channel difference over 12, or a worst window mean over
20 (32 x 32 pixel windows, sliding in 16 px steps, so a small change cannot straddle every
window) - the window test catches a stale preview whose change is confined to a small area, down
to a 14 px icon. A board
change re-renders the affected previews with this tool; `--check` over all 27 boards is the
fidelity gate ([`docs/parts/icons.md`](icons.md) lists what the drawings mean).

## Per-app tiles

`generators/icons/emit_board_tiles.py` writes the AppIcon component's table
(`design/boards/AppIcon.dc.html`) from `generators/icons/apptiles` (the 2026-10-02 per-app redesign,
[`docs/parts/icons.md`](icons.md), "Per-app tiles") and refreshes the two tablet boards, which are
plain HTML with the tile drawings embedded (they render without the component runtime):

    generators/icons/emit_board_tiles.py           # print the table, for review
    generators/icons/emit_board_tiles.py --write   # update the component and the tablet boards

The seam rule is `apptiles/kit.py`'s: a layer drawn in the tile's own base colour keeps that colour
and gains a second pass with the sheen gradient, so the sheen band continues over it without a
seam. The component draws that pass from each entry's `seams` list; the tablet boards embed the
drawings as `tile_svg()` produces them (through `art_tiles` for the board tiles, so the
calendar's month and date labels come along, and through the kit for the app tiles). `generators/icons/tests/emit_board_tiles_test.py` fails
when either falls out of sync or the seam rule regresses.

## Tests and CI

The suites run in the `build` workflow's Fedora 44 job (it installs Pillow and chromium):

    python3 design/render/tests/render_test.py             # Pillow only, no browser
    python3 generators/icons/tests/emit_board_tiles_test.py
    python3 design/render/tests/runtime_test.py            # browser-backed, CHROME=chromium

Rendering itself needs Chrome, so it runs on a developer machine rather than in CI; the two suites
above are what CI checks, and they fail when the component table or the tablet boards no longer
match the drawings they come from. A change to a board, to `design/render/` or to the emitter
arrives with re-rendered previews and a note in the pull request that
`design/render/render.py --check` passed for every board.
