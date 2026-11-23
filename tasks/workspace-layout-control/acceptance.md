<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Acceptance matrix (P7)

The plan's required acceptance matrix (`plan.md`, "Required acceptance matrix"), mapped to the
automated cases and the named isolated-session runs that show each row. "Automated" names the
suite and the case; "native" names the run and its evidence. A row that is not shown says why.

| Case | Evidence | Status |
|---|---|---|
| Cold start or shell restart with old saved fields | `calendar_backend_test.py`'s lifetime and restart cases; `tools/tests/layout-control/lifecycle.py` (P0's `lc-restart1`, `lc-restart3`, `restart-proof`); the backend suite's `unconfirmed` and late-answer cases. The bar starts unknown and asks afresh; a saved request is withdrawn or replaced, never replayed. | Automated and native (P0) |
| Stock/absent/disabled/refused backend | `calendar_backend_test.py`'s refused, absent and disabled cases; P0's `refused-backend` run; P7's `p7-reload-1` run showed the real clock go unknown, hide the control and remove the actions when the placement script was unloaded. With the same staged packages in `pf213-stock-stock-24e24cc` and `pf213-stock-fork-24e24cc`, the loaded placement script answered on both builds. The control and actions stayed hidden on stock and were available on the fork. | Automated and native (P0, P7) |
| Existing shortcut on/off | The provider's shortcut (`Plasma Fusion: Refresh Layout Controls`) and the tiling shortcut; P5's native runs with the shortcut on and off; the backend suite's `cancelled` case. | Automated and native (P5) |
| Floating requested on B while A is tiled | `calendar_backend_test.py`'s action cases (a Floating set on one view leaves another view's mode); P5's native runs (a set on one view, the other unchanged). | Automated and native (P5) |
| Tiled transfer A→B with B refused | `calendar_backend_test.py`'s transfer and refusal cases; P5's native runs (a transfer decided at once, a refused set with its reason); #212's old-stack-size finding is recorded, not fixed here. | Automated and native (P5) |
| Keyboard entry after panel focus | `calendar_view_test.py`'s interactive-control and menu cases (Tab stop, Return/Enter/Space/Select, the ring, the focus reason); the P6 native session (Meta+Alt+P, Return opens the menu, the confirmed row's ring, a second opening); P0's `keyboard-entry` run (the app, never the panel). | Automated and native (P0, P6) |
| App focus change/close/departure while menu open | `calendar_backend_test.py`'s target cases (`focus-changed`, `target-departed`, `stale-context`); P0's `target-preparation` and `view-loss` runs. | Automated and native (P0) |
| Two controls for one view; two bars for different views | `calendar_backend_test.py`'s `busy` and serialization cases; P0's `two-bar` and `consumer-retirement` runs. In P7's `p7-arb-2` run (18 checks), both bars prepared in turn on one output. Focus changes ended the previous preparation before the other bar's request was read. No set was sent. | Automated and native (P0, P7) |
| Same provider/view, out-of-order replies | `calendar_backend_test.py`'s revision and completion cases; P0's `reply-ordering` and `completion` runs. | Automated and native (P0) |
| Timeout followed by late confirmation | `calendar_backend_test.py`'s deadline, unconfirmed and late-answer cases; P0's `query-timeout-late` run. | Automated and native (P0) |
| Provider reload/disable, KWin owner replacement | `calendar_backend_test.py`'s lifetime cases; P0's `mixed-lifetimes` run; P7's `p7-reload-1` run (11 checks) showed the real clock answer again when the placement script was reloaded. A live `org.kde.KWin` owner change is G0 item 4's documented limit (no live consumer sees it). | Automated and native (P0, P7); KWin owner replacement is a documented limit |
| Output removal or activity/desktop switch | `calendar_backend_test.py`'s view cases; P0's `view-loss` run; #211's native two-output runs (an output's removal, re-add and rescale end the session). | Automated and native (P0, #211) |
| Manual snap/maximize/fullscreen, placement memory | The placement suite (`scenario-placement.sh`); P5's native runs (a set's start and teardown, the old master's restore); the snap geometry suite. | Automated and native (P5) |
| UI input and constrained layout | `calendar_view_test.py` (dots, calendar, wheel, RTL, touch, large text, the width budget); the P6 native session (the wheel over the control, the menu over the calendar, the status line's side); the width-budget cases. | Automated and native (P6) |

## Not shown, and why

- **Live KWin owner replacement:** G0 item 4 records that no live consumer sees an
  `org.kde.KWin` owner change. The shell restart and provider reload are covered separately above.
- **A screen reader:** the approved image has none (no `orca`), so the announcement's naming was
  not checked there.
- **An Escape between a choice and its read (T25):** not produced; the provider answers within a
  frame.
- **A set from the menu:** not produced in the P6 session, which had no app window to tile; P5's
  native runs show the set path.
