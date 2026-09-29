// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Offscreen harness for org.plasmafusion.switcher (test use only). Draws the AltTab board's
// backdrop, fills the stand-in Workspace with the board's five windows (plus extra ones for
// count > 5, some on another workspace) and opens the switcher. Context properties from
// render.py: dark, count, allDesktops, current, otherDesktop.

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
    readonly property int windowCount: typeof count === "undefined" ? 5 : count
    readonly property bool showAllDesktops: typeof allDesktops === "undefined" ? true : allDesktops
    readonly property int startIndex: typeof current === "undefined" ? 1 : current
    readonly property int onOther: typeof otherDesktop === "undefined" ? 0 : otherDesktop
    property bool ready: false
    property var captureOrder: ["background", "backdrop", "Window switcher"]

    QtObject { id: work; property string name: "Work" }
    QtObject { id: design; property string name: "Design" }

    readonly property var boardWindows: isDark ? [
        { app: "settings", icon: "systemsettings", caption: "Appearance — Settings", look: { bar: "#222840", body: "#1b2031", c1: Qt.rgba(1,1,1,0.35), c2: Qt.rgba(1,1,1,0.12), c3: Qt.rgba(91/255,157/255,1,0.3), l: [50, 90, 70, 60] } },
        { app: "browser", icon: "internet-web-browser", caption: "Fusion theme notes — Browser", look: { bar: "#262b3d", body: "#f4f1ea", c1: "#1b2031", c2: "#b9b3a6", c3: "#e8743b", l: [70, 95, 80, 45] } },
        { app: "files", icon: "system-file-manager", caption: "Wallpapers — Files", look: { bar: "#1f2536", body: "#1a1f2e", c1: Qt.rgba(1,1,1,0.3), c2: Qt.rgba(1,1,1,0.12), c3: "#2e3d73", l: [40, 80, 65, 100] } },
        { app: "terminal", icon: "utilities-terminal", caption: "~ : zsh — Terminal", look: { bar: "#171c2c", body: "#0f1320", c1: "#3cc4b0", c2: Qt.rgba(1,1,1,0.2), c3: Qt.rgba(1,1,1,0.06), l: [55, 80, 40, 30] } },
        { app: "code", icon: "accessories-text-editor", caption: "fusion-theme.qml — Code", look: { bar: "#1e2233", body: "#161a26", c1: "#9b7bf0", c2: "#8ab8ff", c3: Qt.rgba(242/255,166/255,90/255,0.35), l: [60, 85, 70, 50] } }
    ] : [
        { app: "settings", icon: "systemsettings", caption: "Appearance — Settings", look: { bar: "#eceff6", body: "#ffffff", c1: Qt.rgba(20/255,24/255,39/255,0.35), c2: Qt.rgba(20/255,24/255,39/255,0.12), c3: Qt.rgba(91/255,157/255,1,0.3), l: [50, 90, 70, 60] } },
        { app: "browser", icon: "internet-web-browser", caption: "Fusion theme notes — Browser", look: { bar: "#e4e7ef", body: "#f4f1ea", c1: "#1b2031", c2: "#b9b3a6", c3: "#e8743b", l: [70, 95, 80, 45] } },
        { app: "files", icon: "system-file-manager", caption: "Wallpapers — Files", look: { bar: "#f1f3f8", body: "#ffffff", c1: Qt.rgba(20/255,24/255,39/255,0.3), c2: Qt.rgba(20/255,24/255,39/255,0.12), c3: "#9bb2e0", l: [40, 80, 65, 100] } },
        { app: "terminal", icon: "utilities-terminal", caption: "~ : zsh — Terminal", look: { bar: "#171c2c", body: "#0f1320", c1: "#3cc4b0", c2: Qt.rgba(1,1,1,0.2), c3: Qt.rgba(1,1,1,0.06), l: [55, 80, 40, 30] } },
        { app: "code", icon: "accessories-text-editor", caption: "fusion-theme.qml — Code", look: { bar: "#1e2233", body: "#161a26", c1: "#9b7bf0", c2: "#2f6fdf", c3: Qt.rgba(242/255,166/255,90/255,0.35), l: [60, 85, 70, 50] } }
    ]

    ListModel {
        id: fakeModel
        function activate(i) { console.log("activate", i); }
        function close(i) { console.log("close", i); }
    }

    property var switcher: null

    Component.onCompleted: {
        const wins = [];
        for (let i = 0; i < windowCount; ++i) {
            const b = boardWindows[i % boardWindows.length];
            const id = "{00000000-0000-0000-0000-00000000000" + i.toString(16) + "}";
            const other = i >= windowCount - onOther;
            const w = {
                internalId: id, captionNormal: b.caption, desktopFileName: "org.fusion." + b.app,
                resourceClass: b.app, resourceName: b.app, onAllDesktops: false,
                desktops: [other ? design : work], width: 1200, height: 760 + (i % 3) * 40, look: b.look
            };
            wins.push(w);
            fakeModel.append({ windowId: id, caption: b.caption, desktopName: other ? "Design" : "Work",
                               closeable: true, minimized: false, icon: b.icon });
        }
        KWin.Workspace.windows = wins;
        KWin.Workspace.desktops = [work, design];
        KWin.Workspace.currentDesktop = work;
        const url = packagesRoot + "/switcher/org.plasmafusion.switcher/contents/ui/main.qml";
        const component = Qt.createComponent("file://" + url);
        if (component.status !== Component.Ready) {
            console.log("switcher failed:", component.errorString());
            return;
        }
        switcher = component.createObject(bg);
        switcher.model = fakeModel;
        switcher.allDesktops = showAllDesktops;
        switcher.screenGeometry = Qt.rect(0, 0, 1440, 900);
        switcher.currentIndex = startIndex;
        switcher.aboutToShow();
        switcher.visible = true;
        readyTimer.start();
    }

    Timer { id: readyTimer; interval: 700; onTriggered: bg.ready = true }

    // The board's backdrop: wallpaper, two background windows, the top bar.
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
        ShapePath { fillColor: "#5a7fd6"; strokeWidth: -1
            PathSvg { path: "M0 846 L300 786 L600 834 L900 774 L1200 824 L1440 792 L1440 900 L0 900 Z" } }
    }
    Rectangle { x: 64; y: 62; width: 760; height: 500; radius: 14; color: bg.isDark ? "#1a1f2e" : "#ffffff"; border.width: 1; border.color: bg.isDark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(20/255,24/255,39/255,0.08) }
    Rectangle { x: 548; y: 262; width: 652; height: 506; radius: 14; color: bg.isDark ? "#1b2031" : "#ffffff"; border.width: 1; border.color: bg.isDark ? Qt.rgba(1,1,1,0.1) : Qt.rgba(20/255,24/255,39/255,0.1) }
    Rectangle { width: 1440; height: 34; color: bg.isDark ? Qt.rgba(9/255,12/255,24/255,0.58) : Qt.rgba(250/255,251/255,1,0.74) }
}
