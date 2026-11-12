# #115 Re-entry test scenarios

The tests the DEFERRED entry names as the gate for closing #115, designed against the landed
contracts. Executed once the tiler (PR #164) merges; each scenario runs on a real Plasma
session (the ThinkPad or a VM lane) with the fork's KWin, the placement script, and the tiler
active.

## 1. Removal-release matrices

### 1a. Output removal while tiling
- Toggle the tiler on with 2+ windows (a master and a stack)
- Remove the output the tiling session lives on (OutputConfiguration disable)
- **Expect**: the tree releases natively (treeChanged fires, no live tree); the tiler restores
  the stack windows' saved floats; the master restores to its floating frame A through the
  native explicit restore; no window is left at an automatic rectangle; no corrective geometry
  loop (each window moves at most once); no kwinrc tile tree is written.

### 1b. Desktop removal while tiling
- Toggle the tiler on; remove the desktop the session lives on
- **Expect**: identical to 1a (the native desktop-removal release path).

### 1c. Master window closed while tiling
- Toggle on; close the master (its titlebar close button)
- **Expect**: treeChanged fires (the close releases the ownership); the tiler restores the
  stack floats; the session clears.

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

## Execution notes

- Each scenario is a scripted session on the ThinkPad (or a VM): the setup, the action, the
  asserts. The `tools/tests/release-vm/` harness or a direct SSH session script works.
- The placement file is read before and after each scenario to verify the memory state.
- The kwinrc is read before and after to verify no tree was written.
- Evidence: screenshots or programmatic geometry reads for each assert; the full session log.
