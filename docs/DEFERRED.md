<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Deferred and blocked work

Keep blocked work visible while independent, verified changes continue. This queue is not a waiver
of tests, compatibility, security, preservation requirements or review.

## Workflow

1. **Classify the stop.** Use `blocked` when a required dependency, safe design or validation is
   missing. Use `deferred` for an intentional scope or priority decision. Neither means complete.
2. **Create or link an issue.** Record the affected behavior, reproducible evidence, tested versions,
   rejected approaches, remaining uncertainty and acceptance criteria. Keep sensitive evidence
   private; public issues should contain only material safe to share.
3. **Record a re-entry condition.** Name the dependency or result that must change, and the first
   verification to run when it does. “Revisit later” is insufficient. Add the entry below with its
   last verification date; never imply an old test result is current.
4. **Continue independent work only.** Leave dependent tasks blocked. Test tooling, documentation or
   unrelated approved work can proceed if they do not rely on the missing behavior. A stub, skipped
   test, reduced threshold or changed default is not a substitute for the blocked implementation.
5. **Revalidate before resuming.** Check the live issue, actual source/dependency versions and the
   original failure case. Reopen design review if the proposed solution changes a contract. Keep
   owner authorization boundaries; this workflow grants no new deployment or publication rights.
6. **Close from evidence.** Mark the issue complete only after the implementation and required
   verification pass. Record the resolving change and final evidence, then move the row to the
   completed section without erasing its history.

For each entry, keep one authoritative issue rather than duplicating a full task list here.
Feature specifications and implementation plans still define what must be built and tested.

## Active queue

| Item | State / owner | Blocker and evidence | Re-entry condition and first check | Last verified |
|---|---|---|---|---|
| [#115: native ownership for dynamic tiling](https://github.com/archledger/plasma-fusion/issues/115) | Blocked / maintainer | The route is decided: the compositor-side owner ships in the maintained fork [`archledger/kwin`](https://github.com/archledger/kwin) (branch `plasma-fusion`, KWin 6.8.2) and reaches users through the opt-in `plasma-fusion-full` profile ([ADR 0001](adr/0001-two-profile-distribution.md)); the issue records the current chain. What blocks is the remaining sequence, not the route: the native chain through NT06 is complete (fork PRs #8-#16), the provider port is merged (plasma-fusion #163 on fork PRs #17-#20), and NT08 — unload and restart preservation — is qualified at fork PR #21 (the writer keeps an accepted coalescing record across an orderly teardown; the restart rows pin P surviving, the automatic rectangle never entering the file, and no owner state crossing a restart), leaving the complete tiling policy (PR #164), the #115 re-entry tests and the full-profile packaging. Unsupported at NT08 and still unverified: the isolated-session reload/restart comparison and the facade-level script-teardown release on the fork's KWin — no session lane exists for it (the container seeds run stock KWin); the re-entry is the `v6.8.2-pf3` tag, the RPM build from `packaging/fork-rpm` and a seeded container, and the first check is the reload/restart comparison starting from persisted P != current A. Historical stock evidence (6.7.5/6.7.91, Qt 6.11.2): a temporary custom-tree replacement changes manual membership and survives compositor restart; a separately owned root is outside native ownership lookups and stock does not evacuate it on output/desktop removal or transfer; a restore-field observer alone misses native transitions; releasing before the client commits an acknowledged tile size lets placement memory record the tile rectangle, and a serial-aware settling mark in the owner fixes that in private tests but scripts cannot detect the state alone. | The reviewed production owner on the fork (separate-root release on output/desktop removal plus serial-aware settling), qualified on 6.8.2, then ADR 0001's full-profile packaging. First rerun the removal-release and placement-memory session matrices against it, then the saved-tree and native Restore/fullscreen cases, with no corrective geometry loop or persistent user-layout replacement. The placement script's settling lookup and the native module ship with that owner, not before it. | 2026-11-12 |

Dynamic tiling remains unavailable while this entry is blocked. Diagnostic tests and documentation
do not count as an implementation. Video wallpapers are a separate module; this blocker neither
approves their specification nor creates a dependency on tiling.

## Completed entries

| Item | Resolved by | Final evidence | Date |
|---|---|---|---|
| [#142: Fedora 44 Plasma 6.8.2 qualification](https://github.com/archledger/plasma-fusion/issues/142) | #150 (`1b48fa8`) and the owner-approved laptop update | The compiled parts pass their five ctest suites, and all six depth features pass their 174 checks on 6.8.2; `packaging/tested-versions.txt` is raised. The laptop runs Plasma 6.8.2 with stock KWin `6.8.2-3.fc44` and Plasma Fusion `0.6.0^266.git4fef0b5-1.fc44`; the login check recorded the versions as tested, the post-login run logged `versions=tested lock=tested; no change`, and the Fusion decoration, navigation effect, desktop and lock screen are active; no coredumps. See #142 for the final verification. | 2026-11-10 |
