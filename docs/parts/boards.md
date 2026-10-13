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

    design/render/render.py                   # every board, in canvas order
    design/render/render.py NAME.dc.html ...  # only the named boards
    design/render/render.py --check           # diff fresh renders against the committed previews

Requires `google-chrome` (or `CHROME=...`) and Pillow, and no network: each board is served with
the fonts this repository bundles (`fonts/`) in place of its Google Fonts stylesheet, and the run
waits for the runtime's `data-board-rendered` marker on `<html>` before the screenshot, so a board
that does not finish rendering fails instead of producing a partial picture. `--check` exits
nonzero for a missing committed preview, a size mismatch, or a mean per-channel difference over 12.
A board change re-renders the affected previews with this tool; `--check` over all 27 boards is the
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
drawings as `tile_svg()` produces them. `generators/icons/tests/emit_board_tiles_test.py` fails
when either falls out of sync or the seam rule regresses.

## Tests and CI

Both suites run offline (the `build` workflow's Fedora 44 job installs Pillow for the first):

    python3 design/render/tests/render_test.py
    python3 generators/icons/tests/emit_board_tiles_test.py

Rendering itself needs Chrome, so it runs on a developer machine rather than in CI; the two suites
above are what CI checks, and they fail when the component table or the tablet boards no longer
match the drawings they come from. A change to a board, to `design/render/` or to the emitter
arrives with re-rendered previews and a note in the pull request that
`design/render/render.py --check` passed for every board.
