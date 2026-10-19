/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    A saved app pair's icon (board TabletPairs.dc.html, "two tiles on a plate", owner decision
    2026-10-19): both apps' tiles, small, side by side on a frosted plate the size of an app tile,
    as Android's app pairs; the first app on the left. An app that is gone (uninstalled) shows its
    tile faded and grey. Shared block (tools/build-lib/shared-qml.sh); docs/parts/apppairs.md.
*/
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Item {
    id: pair

    // The plate's size in logical px (the home screen's 72, the dock's tile size).
    property real size: 72
    // Each app: what Kirigami.Icon shows (an icon name or the app's QIcon) and its desktop id
    // without the suffix (FusionIconTile's iconName: the app's designed tile).
    property var leftSource: "application-x-executable"
    property string leftIconName: ""
    property bool leftMissing: false
    property var rightSource: "application-x-executable"
    property string rightIconName: ""
    property bool rightMissing: false
    // The board's plate: white 16 % on the dark scheme, ink 10 % on the light one.
    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }

    width: size
    height: size

    Rectangle {
        anchors.fill: parent
        radius: Math.round(pair.size * 19 / 72)
        color: pair.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.10)
        border.width: 1
        border.color: pair.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.12)
    }
    Row {
        anchors.centerIn: parent
        spacing: Math.max(2, Math.round(pair.size * 0.05))
        PairApp {
            source: pair.leftSource
            iconName: pair.leftIconName
            missing: pair.leftMissing
        }
        PairApp {
            source: pair.rightSource
            iconName: pair.rightIconName
            missing: pair.rightMissing
        }
    }

    component PairApp: FusionIconTile {
        property bool missing: false
        size: Math.round(pair.size * 0.40)
        opacity: missing ? 0.35 : 1
        layer.enabled: missing
        layer.effect: MultiEffect {
            saturation: -1
        }
    }
}
