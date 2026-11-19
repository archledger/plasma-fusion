// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import org.kde.kwin

// Test-only. Holds the fork's single native provider slot so that the layout probe's own
// registration is refused, as when another provider such as the placement script holds it.
// The writer releases the slot when this object is destroyed, i.e. when the script unloads.
// It never creates or admits a tile, moves a window or writes configuration.
Item {
    id: occupier
    property bool authorized: false
    property bool accepted: false

    function occupy(): void {
        authorized = KWin.readConfig("OccupierAuthorized", false) === true;
        if (!authorized) {
            console.warn("layout-occupier: authorization marker absent; occupier stays inert");
            return;
        }
        const api = typeof Workspace.transientTiling === "function"
            ? Workspace.transientTiling() : null;
        const token = api ? String(api.registerProvider(occupier)) : "";
        // Qt's UUID text has braces; a refused registration returns the null UUID.
        const text = token.startsWith("{") && token.endsWith("}") ? token.slice(1, -1) : token;
        accepted = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
            && text !== "00000000-0000-0000-0000-000000000000";
        // Only the verdict is logged; the ownership token is never kept or printed.
        console.info("layout-occupier: registered", accepted);
    }

    Component.onCompleted: {
        occupy();
    }
    Component.onDestruction: {
        if (authorized) {
            console.info("layout-occupier: released", accepted);
        }
    }
}
