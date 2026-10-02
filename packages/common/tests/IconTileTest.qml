/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    FusionIconTile's lookups by desktop id (icontile.sh): a designed id wins over the icon its desktop
    entry names, an app with a familiar tile shows it, others keep the neutral tile.
*/
import QtQuick
import QtQuick.Window

Window {
    id: root
    visible: true
    width: 400
    height: 100
    // [Icon= of the desktop entry, desktop id]
    property var cases: [["debug-run", "org.kde.kdebugsettings"], ["firefox", "org.mozilla.firefox"],
                         ["/opt/example/icon.png", "org.example.Familiar-App"], ["some-icon", "org.example.Nothing"]]
    Repeater {
        id: rep
        model: root.cases
        FusionIconTile {
            required property var modelData
            size: 48
            source: modelData[0]
            iconName: modelData[1]
        }
    }
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            for (let i = 0; i < rep.count; i++) {
                const t = rep.itemAt(i);
                console.warn("CASE " + t.iconName + " ownTile=" + t.ownTile + " familiar=" + t.familiar
                             + " foreign=" + t.foreign + " glyph=" + t.iconItem.source);
            }
            Qt.quit();
        }
    }
}
