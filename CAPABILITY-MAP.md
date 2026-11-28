<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Desktop workflow additions

Scope and build order accepted on 2026-11-17. Each module's specification is reviewed separately
before implementation. This map does not declare an implementation complete.

| Module id | Responsibility | Existing dependency | Specification |
|---|---|---|---|
| workspace-layout-control | Show and explicitly change the current view's Fusion tiling mode. | Placement script and the full profile's native tiler. | [Accepted](SPEC-workspace-layout-control.md) |
| captive-portal-sign-in | Show cached possible network sign-in as a passive network-wide note. Browser launch remains unimplemented. | Fusion network service and the platform's cached connectivity state. | [Status-note contract](SPEC-captive-portal-status.md) |
| notification-triage | A configurable shortcut that focuses the newest eligible notification banner; on that banner, Escape dismisses it into the history and Enter acts as a click. | Plasma's notification applet at the exact Workspace version, and the existing shortcut infrastructure. | [Accepted](SPEC-notification-triage.md); [startup gate](SPEC-notification-gate.md) and optional Fedora package |

Build order: `workspace-layout-control` → `captive-portal-sign-in` → `notification-triage`.
The modules do not depend on one another and should arrive as separate changes.

## Initial boundaries

- Preserve the tiler's one-active-session contract. No simultaneous independent layouts,
  scrolling layout, persistent layout preference, or automatic tiling in the first module.
- Portal sign-in requires a user gesture. Do not submit credentials, accept terms, introduce a
  new probe endpoint, or change VPN/DNS policy.
- Notification dismissal and activation are distinct actions. Preserve shortcut assignments
  and the lock-screen boundary. Exact-repeat collapse is a later notification slice. The
  notification triage ships as a version-bound compiled part with a packaging
  change, which the owner approved on 2026-11-26.
- Reuse the design system and existing platform backends. Keep stock-profile fallback and
  prove changes in isolated tests before any installation.
- Keep native KWin contracts, packaging, candidate refs, release tooling and CI outside these
  changes. A necessary change at one of those boundaries requires coordination first.

## Live backgrounds

Retained as a separate opt-in follow-up, not rejected and not included in this batch. Candidate
constraints are silent playback, a still lock-screen image, pausing on battery or when hidden,
and respecting reduced motion. The backend, supported formats and exact power behavior still
need research and a separate specification.
