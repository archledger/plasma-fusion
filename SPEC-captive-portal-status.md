<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Captive-portal status note

## Scope

Quick Settings shows one network-wide informational note when NetworkManager's last completed
connectivity check reports a possible captive portal. The note appears in the Wi-Fi drill-down,
including the Network variant shown when there is no Wi-Fi radio.

This is deliberately **status only**. It does not implement the browser-launch part of the
`captive-portal-sign-in` module. It supplies no URL, link, button, sign-in action, credentials,
CAPPORT query, new probe endpoint, connection-scoped result or change to NetworkManager, VPN or DNS
policy. The stock notification and browser behavior remain separate.

## Data contract

The reader uses the existing Workspace D-Bus QML module on the system bus. It does not create another
`PlasmaNM.NetworkStatus` (whose constructor can request a connectivity check) and never calls
`CheckConnectivity`.

The note requires all three cached manager properties:

| Property | Required value | Meaning |
|---|---|---|
| `ConnectivityCheckAvailable` | Boolean `true` | Connectivity checking is configured |
| `ConnectivityCheckEnabled` | Boolean `true` | Connectivity checking is enabled |
| `Connectivity` | D-Bus `uint32` value `2` (`NM_CONNECTIVITY_PORTAL`) | The last check reported a possible captive portal |

The manager result is aggregate and device-scoped, not attached to a Wi-Fi activation or access point.
It is never presented as a property of an individual network row.

A view is active only while its Wi-Fi page is visible. Opening the page subscribes to
`NameOwnerChanged` before resolving the manager's unique D-Bus owner with `GetNameOwner`.
Both `GetAll` and the `PropertiesChanged` subscription target that owner. An owner change
retires the old subscription and its state.
Relevant property invalidation also clears the state. There is no polling or automatic retry.

A request generation and an independent component-lifetime token fence every asynchronous reply. A
reply from a closed page, an earlier owner, an earlier generation or a destroyed component is ignored.
A live relevant update also retires any older `GetAll` that has not yet returned, so it cannot replace
newer state. If that update leaves required fields unknown, one fresh event-driven cached read follows.
Missing, malformed, incomplete, invalidated, unavailable, disabled or failed data leaves no note.
Reopening the page takes a fresh snapshot. There is no polling or automatic retry.

## Presentation

The separate plain-text item is outside every Wi-Fi row and has no pointer or keyboard action. Its
accessible name is its text and its role is static text. It wraps within the page and does not enter
the Tab chain.

> The last connectivity check reported a possible network sign-in. If your browser offers a network
> sign-in page, use that prompt or choose another network.

Its absence does not assert full connectivity, lack of a captive portal or that a particular Wi-Fi
connection is usable. Existing connection status, `Disconnect`, network selection, password entry,
hotspot, VPN, airplane mode and Network settings remain independent.

## Verification

`portal_status_test.py` drives the real component through Workspace D-Bus against a private python-dbus
mock. It tests each malformed gate independently with valid Portal connectivity, both on a snapshot and
on a live update. It also covers initial and reopened state, all connectivity values and wrong wire
types, incomplete and invalidated properties, a frozen late Portal reply after a newer Full snapshot,
hidden pages, watch-before-lookup order, unique snapshot destinations across handover, retired-owner
signals, read errors, callbacks after destruction, and zero `CheckConnectivity` calls or property
writes. Qt and GLib are pumped explicitly in one thread; no real radio, profile, browser or host
system bus is used.

`pages_test.py` checks the staged real Wi-Fi page: accessible non-interactive presentation, clearance,
keyboard activation on an open network, rejected password submission and the existing touch targets.

The native `network_ap_test.py` suite continues to check the complete backend facade and connection
dispatch. An isolated Plasma 6.8.3 session additionally verifies rendering and live clearance against a
synthetic manager. In that session the unmodified baseline and this feature both produced three
pre-existing `CheckConnectivity` calls from the existing network stack; the feature added one cached
`GetAll` for the note and zero new connectivity probes or writes. A separate fresh Fedora 44 VM ran
real NetworkManager 1.56.1 against a controlled IP-based HTTP fixture and verified `PORTAL`/`FULL`
presentation, disabled checks and service restart; Fedora's expected `OK` response body was used for Full.
The Plasma 6.7.5 Workspace headers confirm the same `SignalWatcher` and callback `asyncCall` APIs; no
Plasma 6.7 runtime result is claimed.

## Upstream comparison

- [KDE plasma-nm 6.8.3 `connectivitymonitor.cpp`](https://invent.kde.org/plasma/plasma-nm/-/blob/263fff4b/kded/connectivitymonitor.cpp)
  subscribes to connectivity changes, explicitly calls `CheckConnectivity()` during construction, and
  offers a notification login action using the configured connectivity URI. Fusion deliberately copies
  none of those active behaviors: its scope is only the cached, non-interactive note.
- [GNOME Shell `status/network.js`](https://gitlab.gnome.org/GNOME/gnome-shell/-/blob/main/js/ui/status/network.js)
  uses `NM.Client` connectivity and primary-connection bindings for its network indicators and portal
  flow, and explicitly replaces connection objects after NetworkManager restarts. That supports keeping
  state owner-scoped and avoiding row-level conclusions; GNOME's separate portal UI is not reproduced here.
- [NetworkManager's D-Bus API](https://networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager.html)
  defines `Connectivity` as the result of the last check and distinguishes it from `CheckConnectivity()`,
  which requests a new check. [Connectivity enum values](https://networkmanager.dev/docs/api/latest/nm-dbus-types.html#NMConnectivityState)
  assign portal the numeric value 2.

Upstream code was consulted as public reference, not copied into this feature. The retained project
readiness report (`2026-11-24-captive-portal-sign-in/feature-readiness`) explains why a per-Wi-Fi badge
and launch action remain out of scope.
