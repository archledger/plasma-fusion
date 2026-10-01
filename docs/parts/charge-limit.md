# Battery charge limit (2026-10-01)

Owner request after research D-desktop ("Add": a charge limit and a one-tap full charge in the quick
settings; want 14, ThinkPads keep the limit across reboots, PowerDevil has no temporary override).

## Parts

| Part | Where |
|---|---|
| Helper | `packages/power/charge-limit/plasma-fusion-charge-limit` -> `/usr/libexec/plasma-fusion/` (build part `87-charge-limit`, noarch package) |
| polkit action | `org.plasmafusion.charge-limit` -> `/usr/share/polkit-1/actions/`; `allow_active=yes`, `allow_inactive=no`, `allow_any=no`, `exec.path` = the helper |
| Quick settings | `services/ChargeLimit.qml`, the `charge` facade in `Backend.qml`, the "Charge limit" tile and its choices in `QuickSettingsMain.qml` |

The value is the battery's own stop threshold (`/sys/class/power_supply/BAT*/charge_control_end_threshold`,
and `charge_control_start_threshold` where present), the same one PowerDevil's Energy Saving page
writes through its helper; that page shows what the tile sets. Not a Plasma Fusion setting file.

## Helper

`plasma-fusion-charge-limit get` prints `END START` of the first built-in battery (type Battery,
scope not Device) with a stop threshold, `START` -1 without a start threshold; exit 2 when no battery
has one; no privileges needed. `plasma-fusion-charge-limit set END` (50..100, whole percent, else exit
64; not root: exit 77) writes every such battery: start = END - 5 below 100, 0 at 100 (charge whenever
below); lowering writes the start first and raising the stop first, so start stays below stop.

The tile runs it with `pkexec`. PowerDevil's own setter needs an administrator password
(`auth_admin_keep`); the Plasma Fusion action allows the user at the computer (active local session)
without one, like a phone's or a laptop vendor's battery setting, and only for this helper and these
two values. A remote or inactive session is refused.

## Quick settings

Tile "Charge limit" (shown where the helper and the action are installed system-wide and a battery
has a stop threshold): subtitle "Stops at N %", "Off" or "Charging to 100 % once"; a click turns the
limit on (`plasmafusionrc [Battery] ChargeLimit`, the last limit picked, 80 by default) or off; the
chevron offers Stop at 80 %, Stop at 90 %, Charge to 100 % once (while plugged in and limited), No limit,
Battery settings (Energy Saving). "Charge to 100 % once" stores `[Battery] RestoreChargeLimit` and
sets 100; the limit comes back when the battery is full, at 100 %, or when the charger is unplugged
(also when that happened while the shell was not running). The value is read again whenever the
sheet opens. Each change logs `quicksettings: charge limit N %` / `off`.

## Tests

Laptop (UX5406S, ASUS): `get` prints `85 -1` (an existing limit, no start threshold); `set` without
root exits 77, `set 30` exits 64. ThinkPad hardware: see `artifacts/plasma-fusion/2026-10-01-tablet2/DEPLOY-2/`.
