// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The memory figures of the system meters' pop-up and the desktop system card, "6.1 / 15.3 GiB".
// Both figures are in the binary unit of the total with one decimal, as Plasma formats sizes
// (KFormat::formatByteSize with its default precision and IEC units) and as System Monitor shows
// the same sensors, so the three agree: the total is what the kernel reports, not the installed
// size, and a full memory reads "15.3 / 15.3 GiB" next to "100% in use". The used figure takes
// the total's unit so the two read as one value ("0.4 / 1.5 GiB"). This file is kept identical in
// org.plasmafusion.meters and org.plasmafusion.systemcard (tools/build.d/77-meters.sh compares
// them); tests: org.plasmafusion.meters/tests/memory.test.js. No Qt here, so node can test it.

.pragma library

var BINARY_UNITS = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];

// used, total: bytes. Returns { used, total, decimals, unit } (unit one of BINARY_UNITS), or null
// without both values.
function memory(used, total) {
    if (typeof used !== "number" || !isFinite(used) || typeof total !== "number" || !isFinite(total) || total <= 0) {
        return null;
    }
    var power = 0;
    while (power < BINARY_UNITS.length - 1 && total >= Math.pow(1024, power + 1)) {
        ++power;
    }
    var scale = Math.pow(1024, power);
    var decimals = power > 0 ? 1 : 0;
    var factor = Math.pow(10, decimals);
    return {
        used: Math.round(Math.max(0, Math.min(used, total)) / scale * factor) / factor,
        total: Math.round(total / scale * factor) / factor,
        decimals: decimals,
        unit: BINARY_UNITS[power]
    };
}
