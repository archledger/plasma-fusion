// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Offscreen harness for plasmafusion-snap's flyout and picker (test use only).
// Context properties from render.py: dark, mode ("flyout" or "picker"), hover ("layout,zone").

import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import org.kde.kwin as KWin

Window {
    id: bg
    objectName: "background"
    title: "background"
    width: 1440
    height: 900
    x: 0
    y: 0
    visible: true
    flags: Qt.FramelessWindowHint

    readonly property bool isDark: typeof dark === "undefined" ? true : dark
    readonly property string harnessMode: typeof mode === "undefined" ? "flyout" : mode
    property bool ready: false
    property var captureOrder: ["background", "Pick", "Snap"]
    property var popup: null

    readonly property var target: ({
        internalId: "{t}", frameGeometry: Qt.rect(48, 60, 920, 722), clientGeometry: Qt.rect(48, 112, 920, 670),
        captionNormal: "Software", desktopFileName: "org.kde.discover", resourceClass: "discover"
    })

    readonly property var looks: [
        { app: "files", icon: "system-file-manager", caption: "Wallpapers — Files", look: { bar: "#1f2536", body: "#1a1f2e", c1: Qt.rgba(1,1,1,0.3), c2: Qt.rgba(1,1,1,0.12), c3: "#2e3d73", l: [40, 80, 65, 100] } },
        { app: "code", icon: "accessories-text-editor", caption: "fusion-theme.qml — Code", look: { bar: "#1e2233", body: "#161a26", c1: "#9b7bf0", c2: "#8ab8ff", c3: Qt.rgba(242/255,166/255,90/255,0.35), l: [60, 85, 70, 50] } },
        { app: "mail", icon: "mail-client", caption: "Inbox — Mail", look: { bar: "#222840", body: "#1b2031", c1: Qt.rgba(1,1,1,0.35), c2: Qt.rgba(1,1,1,0.12), c3: Qt.rgba(91/255,157/255,1,0.3), l: [50, 90, 70, 60] } },
        { app: "terminal", icon: "utilities-terminal", caption: "~ : zsh — Terminal", look: { bar: "#171c2c", body: "#0f1320", c1: "#3cc4b0", c2: Qt.rgba(1,1,1,0.2), c3: Qt.rgba(1,1,1,0.06), l: [55, 80, 40, 30] } }
    ]

    Component.onCompleted: {
        const wins = [];
        for (let i = 0; i < looks.length; ++i) {
            const b = looks[i];
            wins.push({ internalId: "{w" + i + "}", captionNormal: b.caption, desktopFileName: "org.fusion." + b.app,
                        resourceClass: b.app, icon: b.icon, width: 1200, height: 800, look: b.look });
        }
        KWin.Workspace.windows = wins;
        const base = "file://" + packagesRoot + "/scripts/plasmafusion-snap/contents/ui/";
        const palComponent = Qt.createComponent(base + "FusionPalette.qml");
        const pal = palComponent.createObject(bg.contentItem);
        if (harnessMode === "flyout") {
            const c = Qt.createComponent(base + "SnapFlyout.qml");
            if (c.status !== Component.Ready) {
                console.warn(c.errorString());
                return;
            }
            popup = c.createObject(bg, { target: target, layouts: layoutsData });
            if (typeof hover !== "undefined") {
                const parts = String(hover).split(",");
                popup.hoverLayout = Number(parts[0]);
                popup.hoverZone = Number(parts[1]);
            }
        } else {
            const c = Qt.createComponent(base + "FillPicker.qml");
            if (c.status !== Component.Ready) {
                console.warn(c.errorString());
                return;
            }
            popup = c.createObject(null, { area: Qt.rect(723, 40, 711, 854), candidates: wins });
        }
        readyTimer.start();
    }

    readonly property var layoutsData: [
        { name: "halves", zones: [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]], quick: [0, 1], h: 0.5, v: 0 },
        { name: "twoThirds", zones: [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 1]], quick: [0, 1], h: 2 / 3, v: 0 },
        { name: "quarters", zones: [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]], quick: [4, 5, 6, 7], h: 0.5, v: 0.5 },
        { name: "thirds", zones: [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1]], quick: [], h: 0, v: 0 }
    ]

    Timer { id: readyTimer; interval: 700; onTriggered: bg.ready = true }

    // Backdrop: wallpaper and, for the flyout, the Software window of the QuickSettings board;
    // for the picker, a window snapped to the left half.
    Rectangle { anchors.fill: parent; color: bg.isDark ? "#141a2e" : "#dde6f4" }
    Rectangle { y: 180; width: 1440; height: 160; color: bg.isDark ? "#181f3a" : "#e6ecf7" }
    Rectangle { y: 340; width: 1440; height: 220; color: bg.isDark ? "#1c2446" : "#eef2fa" }
    Rectangle { x: 860; y: 210; width: 300; height: 300; radius: 150; color: "#f2a65a" }
    Shape {
        anchors.fill: parent
        ShapePath { fillColor: bg.isDark ? "#253058" : "#b9c9e8"; strokeWidth: -1
            PathSvg { path: "M0 560 L180 430 L330 505 L520 350 L700 485 L860 405 L1060 520 L1240 385 L1440 470 L1440 900 L0 900 Z" } }
        ShapePath { fillColor: bg.isDark ? "#2e3d73" : "#9bb2e0"; strokeWidth: -1
            PathSvg { path: "M0 650 L220 545 L420 620 L640 505 L880 612 L1100 540 L1300 622 L1440 580 L1440 900 L0 900 Z" } }
        ShapePath { fillColor: bg.isDark ? "#3b56a0" : "#7896d4"; strokeWidth: -1
            PathSvg { path: "M0 760 L260 662 L520 732 L780 642 L1040 722 L1280 662 L1440 702 L1440 900 L0 900 Z" } }
    }
    Rectangle {
        visible: bg.harnessMode === "flyout"
        x: 48; y: 60; width: 920; height: 722; radius: 14
        color: bg.isDark ? "#1b2031" : "#ffffff"
        Rectangle { width: parent.width; height: 52; radius: 14; color: bg.isDark ? "#222840" : "#eceff6" }
        Rectangle { x: 842; y: 12; width: 28; height: 28; radius: 14; color: "#2f6fdf" }
        Rectangle { x: 876; y: 12; width: 28; height: 28; radius: 14; color: "#d9434b" }
        Rectangle { x: 808; y: 12; width: 28; height: 28; radius: 14; color: Qt.rgba(1, 1, 1, 0.1) }
    }
    Rectangle {
        visible: bg.harnessMode === "picker"
        x: 6; y: 40; width: 711; height: 854; radius: 14
        color: "#f4f1ea"
        Rectangle { width: parent.width; height: 40; radius: 14; color: "#262b3d" }
    }
    Rectangle { width: 1440; height: 34; color: bg.isDark ? Qt.rgba(9/255,12/255,24/255,0.58) : Qt.rgba(250/255,251/255,1,0.74) }
}
