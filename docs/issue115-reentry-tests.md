# #115 Re-entry test scenarios

The tests the DEFERRED entry names as the gate for closing #115, designed against the landed
contracts. Executed once the tiler (PR #164) merges; each scenario runs on a real Plasma
session (the ThinkPad or a VM lane) with the fork's KWin, the placement script, and the tiler
active.

The tiler's native lifecycle itself - the admission order (the tree before any stack write),
the column geometry, the untoggle, the `treeChanged` teardown and a refused tree - is covered
automatically by `packages/kwin/tests/offscreen/tiling_lifecycle_test.py` (the real `main.qml`
under a mock facade, CI `build`); this matrix remains the real-Plasma verification of the same
paths and everything only a compositor can prove.

## 1. Removal-release matrices

### 1a. Output removal while tiling
- Toggle the tiler on with 2+ windows (a master and a stack)
- Remove the output the tiling session lives on (OutputConfiguration disable)
- **Expect**: the tree releases natively (treeChanged fires, no live tree); every window is
  on a live screen. A stack window whose float sat on the removed display keeps KWin's
  evacuation geometry (2h). The master returns to its floating frame, which its native
  record carried onto the remaining screen; its record is settled. No corrective geometry
  loop (each window moves at most twice: KWin's evacuation, then the return); no kwinrc tile
  tree is written; a later toggle on the master is admitted.
- Variant: remove the other output. The session ends too (KWin replays the placements it
  tracks for the new layout, which moves the master); the master is back on its floating
  frame A, its record is settled and a later toggle on it is admitted.

### 1b. Desktop removal while tiling
- Toggle the tiler on; remove the desktop the session lives on
- **Expect**: the tree releases natively; the tiler restores the stack windows' saved floats;
  the master returns to its floating frame A (the release is detach-only, so the tiler moves
  it with an ordinary request and the native layer settles its record); no window is left at
  an automatic rectangle; each window moves at most once; no kwinrc tile tree is written; a
  later toggle on the master is admitted.

### 1c. Master window closed while tiling
- Toggle on; close the master (its titlebar close button)
- **Expect**: treeChanged fires (the close releases the ownership); the tiler restores the
  stack floats; the session clears.

### 1d. A second window of the master's app
- Toggle on; open another window of the master's app (a key conflict); toggle on the master
  with both windows open; close the second window; toggle on the master again
- **Expect**: the session ends; the stack floats restore; the master returns to its floating
  frame A as in 1a; the new window is given no stack cell and stays where KWin placed it;
  the placement file is unchanged while both windows are open, and a toggle on the master
  then is refused (8: the native layer admits no window whose key another live window
  shares). Closing the second window records its place as the app's, by the memory's
  ordinary rule; the next toggle on the master records the master's own place first and is
  admitted.

### 1e. The master moved by hand
- Toggle on; move the master (Alt-drag or its title bar)
- **Expect**: the session ends; the stack floats restore; the master stays where it was put
  and, once the drag has ended, that place is recorded as its floating placement; a later
  toggle on it is admitted.

### 1f. The work area changes while tiling
- Toggle on; change the work area (add or resize a panel that reserves space)
- **Expect**: the session ends (KWin's re-check of the window positions asks the master for
  its tile's rectangle with a public request, which releases it); the stack floats restore;
  the master returns to its floating frame A, not the tile's new rectangle; no automatic
  rectangle enters the placement file; a later toggle on the master is admitted.

### 1g. The master sent to another output
- With two outputs, toggle on; send the master to the other output (Window to Next Screen)
- **Expect**: the session ends; the master stands on the other output at its floating size
  (its floating frame, carried over), not at the tile's size - on an output of another
  scale at that size on that output's pixels (560.25x521.25 becomes 560x521 from 133% to
  100%); that frame is recorded; a later toggle on it there is admitted.

## 2. Placement-memory matrices

### 2a. Managed windows' rectangles never enter the memory
- Toggle on; let the settle pass run (1s); toggle off; check the placement file
  (~/.config/plasmafusion-placementrc)
- **Expect**: the apps' entries hold their pre-tiling floating positions, NOT the tile/stack
  rectangles. The master's entry holds A (its true float, restored by the native layer). The
  stack windows' entries hold their saved floats (written back by the untoggle, then recorded
  by the provider as legitimate floating positions).

### 2b. New windows on the tiled desktop join the stack, not the memory
- Toggle on; open a new app window; let the settle pass run
- **Expect**: the new window joins the stack (placed by the tiler); the provider's record()
  skipped it (the tiler's manages() check); its app's placement entry is unchanged.

### 2c. The re-toggled position is the float, not the tile
- Toggle on, toggle off, toggle on again for the same app
- **Expect**: the second toggle uses the same floating A (the memory holds the true float from
  the first untoggle), not the tile rectangle from the first session.

### 2d. A window minimized before the toggle rejoins on restore
- Minimize a workspace window; toggle on; restore the minimized window from the taskbar
- **Expect**: the restored window joins the stack (a cell, placed by the tiler), it does not
  float over the managed layout, and its pre-session float is kept for the untoggle.

### 2e. A member moved to another workspace stops being managed
- Toggle on; move a stack window to another desktop (or another activity)
- **Expect**: the member leaves the session (the column refills without it), its moves on the
  other workspace are recorded as ordinary floating placements, and the untoggle does not
  drag it back to the first workspace's saved float.

### 2f. A manual move of a stack window floats it
- Toggle on; move (or resize) a stack window by hand to a new spot; toggle off
- **Expect**: the moved window does not snap back to its cell, the untoggle leaves it at the
  user's spot (not the saved float), and the move is recorded as the app's floating
  placement. The tiler's own placements are not mistaken for this (they land exactly on the
  assigned cell, including a client's late commit of one).

### 2g. A reflow that starves a placed member restores its float
- Toggle on with two stack windows; open windows until a placed member's minimum size no
  longer fits its shrunk cell
- **Expect**: the starved member returns to its saved float (not stuck at its last cell, which
  no untoggle could undo), it stops being managed, and its later moves are placement memory
  again.

### 2h. The stack is this screen's, and a removed output's floats stay on live screens
- With two outputs, put a same-desktop window on the other screen; toggle on
- **Expect**: only this screen's windows join the stack; the other screen's window is not
  placed. Then unplug the output the session tiles: the native teardown restores the stack's
  floats only where they still land on a live screen - a window whose float sat on the
  unplugged display keeps KWin's evacuation geometry instead of being dragged offscreen.

### 2i. A maximize of the master does not collapse the stack
- Toggle on; after the open quiet period, maximize (or full-screen) the master and return it
  to its tile
- **Expect**: the stack keeps its cells throughout - the master's full-area frame is a mode
  change, not a manual move, and no relayout reads it as the divider. The stack windows
  rejoin as placed when the master returns.

### 2j. A minimized window moved to another output loses its float
- With two outputs, minimize a workspace window; toggle on; move the minimized window to the
  other output (still connected); untoggle
- **Expect**: the window stays where it was moved - its dormant float belonged to the view it
  left and is not applied. Restoring it on the session's output does not rejoin it either.

### 2k. A window opened minimized during the session rejoins on restore
- Toggle on; start an app that opens already minimized (or restore one from the session
  manager minimized) on the tiled workspace; restore it from the taskbar
- **Expect**: the restored window joins the stack (a cell, placed by the tiler), it does not
  float over the managed column - for it, the restore emits no `windowAdded`, so the watch it
  needed went on at arrival. A full-screen or manually tiled window opened minimized stays a
  stranger; its state survives the restore.

### 2l. A toggle on another output tiles that output
- With two outputs, tile output A; move the focus to output B (same desktop, same activity -
  click a window on B); invoke Tile Workspace
- **Expect**: the first invocation lays out B in one go: A's session ends (its floats restore
  on A) and B tiles immediately - the toggle does not spend its first invocation silently
  untoggling A while B stays floating. (B's window has just lost and regained the focus, so
  its first admission can answer ineligible while the client has not answered that
  configure; the tiler tries again within the same press.)

### 2m. A second press of the shortcut within a few milliseconds
- Toggle on and off again at once (two invocations with nothing in between); repeat
- **Expect**: no tree is left; every stack window is back on its float - a float given back
  while the cell's configure was still in flight is asked for once more when the cell lands;
  the master is on its float; no cell and no tile enters the placement file (the first press
  records the master's own floating frame as its app's place where that was another
  rectangle).

### 2n. On, off and on again within a few milliseconds
- Three invocations with nothing in between, then a fourth after the session has settled;
  repeat
- **Expect**: the three leave a live session (the master's admission after its own restore
  is tried again within the press); the fourth ends it and every stack window is back on
  the float it had before the first press - the second session takes a window that still
  stands on the first one's cell with the float that session saved, not with the cell.

## 3. Saved-tree cases

### 3a. The user's manual tile layout is untouched
- Before toggling: set up a manual custom tile layout (KWin's tile editor, Meta+T)
- Toggle the tiler on and off
- **Expect**: the manual layout is unchanged (no automatic tree in kwinrc, the user's custom
  tiles still there). The tiler used the transient tile, never the user's tree.

### 3b. The shortcuts are intact
- Toggle on; verify Meta+Backspace still restores the master (the native Window Restore)
- **Expect**: the native shortcut works unchanged; the tiler's shortcuts (Tile Workspace,
  Focus Master, Focus Next/Previous) are separate and sequence-less.

## 4. Native Restore/fullscreen cases

### 4a. Meta+Backspace on the master
- Toggle on; press Meta+Backspace (the native Window Restore)
- **Expect**: the master restores to its exact floating frame A (the native explicit restore);
  the treeChanged fires; the tiler restores the stack floats; the session clears.

### 4b. Maximize toggle on the master while tiling
- Toggle on; maximize the master (the ordinary MaximizeOp, not the explicit restore)
- **Expect**: the master maximizes (the managed rectangle's maximize-area extents); the
  ownership is kept; the un-maximize returns to the managed rectangle (the ordinary-toggle
  contract, NT05).

### 4c. Fullscreen toggle on the master while tiling
- Toggle on; fullscreen the master; exit fullscreen
- **Expect**: the same as 4b (the fullscreen toggle returns to the managed rectangle while
  owned; the explicit restore releases to A).

## 5. Safe rejection

### 5a. An ineligible master (maximized)
- Maximize a window; try to toggle on with it active
- **Expect**: the toggle refuses (the eligibility check); nothing changes; the window stays
  maximized; no tree was created.

### 5b. A forced-position window (a window rule)
- A window with a forced-position rule; try to toggle on with it active
- **Expect**: the admission refuses (the native preflight); the tree releases; nothing changes.

## 6. Fractional scales

### 6a. A master column off the output's pixels
- On a fractional-scale output, set a `MasterFraction` (or a panel size) that makes the
  master tile's width or height a whole number that is not on the output's device pixels
  (at 133%, one that is not a multiple of 3); toggle on; toggle off
- **Expect**: the master is admitted; its frame has the tile's corner and is at most a pixel
  or two short of the tile; the untoggle returns it to its exact float.

### 6b. A scale whose pixel is not a binary fraction
- At 125%, 150% or 175%, with a master whose floating frame has a fractional size; toggle
  on; toggle off; toggle on again
- **Expect**: the master is admitted, restored to its exact float and admitted again.

## Execution notes

- Each scenario is a scripted session on the ThinkPad (or a VM): the setup, the action, the
  asserts. The `tools/tests/release-vm/` harness or a direct SSH session script works.
- A toggle records the master's own floating frame as its app's place before the native
  admission, where the memory had another rectangle for the app (a window that was never
  moved since it was adopted, an app whose last record was another window's). That entry is
  a floating placement and the one change of the placement file a scenario may show for the
  master; a tile's or a cell's rectangle never is.
- The placement file is read at every step of a scenario and all the snapshots are compared,
  oldest first. (Until 2026-11-13 the harness compared the alphabetically first snapshot
  with the newest one, which in a scenario with an "after" snapshot compared that file with
  itself; the runs before that date were evaluated again from their snapshots.)
- The kwinrc is read before and after to verify no tree was written.
- Evidence: screenshots or programmatic geometry reads for each assert; the full session log.
