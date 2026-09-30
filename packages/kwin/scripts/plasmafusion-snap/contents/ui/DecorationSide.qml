/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Which side the maximize button is on. The settings that decide it are read with kreadconfig6,
// so they are the values on disk with KDE's defaults applied (plasmashell's own view of kwinrc
// is not read again after System Settings changes it):
//   plasmafusionrc [Decoration] ButtonStyle   the Fusion decoration: LeftCircles
//   kwinrc [org.kde.kdecoration2] library     whether the Fusion decoration is in use
//   kwinrc [org.kde.kdecoration2] theme       an Aurorae "-Left" theme
//   kwinrc [org.kde.kdecoration2] ButtonsOnLeft  KWin's button order with maximize ("A")
// Read when the script starts and whenever the flyout opens; until the first answer the buttons
// count as on the right.
Item {
    id: side

    property bool onLeft: false

    readonly property string command: "for k in 'plasmafusionrc Decoration ButtonStyle' 'kwinrc org.kde.kdecoration2 library'"
        + " 'kwinrc org.kde.kdecoration2 theme' 'kwinrc org.kde.kdecoration2 ButtonsOnLeft'; do set -- $k;"
        + " kreadconfig6 --file \"$1\" --group \"$2\" --key \"$3\" || echo; done"

    function refresh() {
        reader.connectSource(command);
    }

    function parse(text) {
        const parts = String(text).split("\n");
        const fusion = String(parts[1] || "").indexOf("plasmafusion") >= 0;
        const found = (fusion && String(parts[0] || "").trim().toLowerCase() === "leftcircles")
            || (!fusion && /-Left$/.test(String(parts[2] || "").trim()))
            || (!fusion && String(parts[3] || "").indexOf("A") >= 0);
        if (found !== onLeft) {
            onLeft = found;
            console.info("plasmafusion-snap: maximize button on the " + (found ? "left" : "right"));
        }
    }

    P5Support.DataSource {
        id: reader
        engine: "executable"
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (Number(data["exit code"]) === 0) {
                side.parse(data["stdout"] || "");
            }
        }
    }

    Component.onCompleted: refresh()
}
