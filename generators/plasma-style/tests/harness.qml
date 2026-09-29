// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test scene for the Plasma styles: top bar, dock with composed shadow tiles, a pop-up
// with Plasma Components 3 controls, tooltips and a desktop widget card (run-harness.sh).
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

Window {
    id: win
    property bool light: Qt.application.arguments.indexOf("light") >= 0
    property string pfx: "translucent/"
    width: 1440; height: 900; visible: true
    color: "#141a2e"
    // Dusk Ridge wallpaper (Main.dc.html), simplified
    Rectangle { anchors.fill: parent; color: win.light ? "#dfe6f5" : "#141a2e" }
    Rectangle { y: 180; width: parent.width; height: 160; color: win.light ? "#cdd8f0" : "#181f3a" }
    Rectangle { y: 340; width: parent.width; height: 220; color: win.light ? "#b9c8ec" : "#1c2446" }
    Rectangle { x: 860; y: 210; width: 300; height: 300; radius: 150; color: "#f2a65a" }
    Rectangle { y: 560; width: parent.width; height: 340; color: win.light ? "#8fa6dc" : "#253058" }
    Rectangle { y: 700; width: parent.width; height: 200; color: win.light ? "#6d8bd4" : "#3b56a0" }
    Rectangle { y: 820; width: parent.width; height: 80; color: "#5a7fd6" }

    component Tile: KSvg.SvgItem {
        property string file
        imagePath: win.pfx + file
        width: svg.elementRect(elementId).width; height: svg.elementRect(elementId).height
    }
    // composes KWindowShadow tiles like KWin does: outer rect = target rect + paddings
    component Shadow: Item {
        id: sh
        property Item target
        property string file
        property real extraTop: 0
        property real extraBottom: 0
        property bool bottomOnly: false
        KSvg.Svg { id: s; imagePath: win.pfx + sh.file }
        readonly property real pt: s.elementRect("shadow-hint-top-margin").height + extraTop
        readonly property real pb: s.elementRect("shadow-hint-bottom-margin").height + extraBottom
        readonly property real pl: s.elementRect("shadow-hint-left-margin").width
        readonly property real pr: s.elementRect("shadow-hint-right-margin").width
        x: target.x - pl; y: target.y - pt; width: target.width + pl + pr; height: target.height + pt + pb
        readonly property size tl: Qt.size(s.elementRect("shadow-topleft").width, s.elementRect("shadow-topleft").height)
        readonly property size tr: Qt.size(s.elementRect("shadow-topright").width, s.elementRect("shadow-topright").height)
        readonly property size bl: Qt.size(s.elementRect("shadow-bottomleft").width, s.elementRect("shadow-bottomleft").height)
        readonly property size br: Qt.size(s.elementRect("shadow-bottomright").width, s.elementRect("shadow-bottomright").height)
        readonly property real blw: Math.min(bl.width, width / 2)
        readonly property real brw: Math.min(br.width, width / 2)
        Item { visible: !sh.bottomOnly; anchors.fill: parent
        KSvg.SvgItem { svg: s; elementId: "shadow-topleft"; width: sh.tl.width; height: sh.tl.height }
        KSvg.SvgItem { svg: s; elementId: "shadow-topright"; x: sh.width - width; width: sh.tr.width; height: sh.tr.height }
        KSvg.SvgItem { svg: s; elementId: "shadow-top"; x: sh.tl.width; width: sh.width - sh.tl.width - sh.tr.width; height: s.elementRect("shadow-top").height }
        KSvg.SvgItem { svg: s; elementId: "shadow-left"; y: sh.tl.height; width: s.elementRect("shadow-left").width; height: sh.height - sh.tl.height - sh.bl.height }
        KSvg.SvgItem { svg: s; elementId: "shadow-right"; x: sh.width - width; y: sh.tr.height; width: s.elementRect("shadow-right").width; height: sh.height - sh.tr.height - sh.br.height }
        Item { clip: true; y: sh.height - sh.bl.height; width: sh.blw; height: sh.bl.height
            KSvg.SvgItem { svg: s; elementId: "shadow-bottomleft"; width: sh.bl.width; height: sh.bl.height } }
        Item { clip: true; x: sh.width - sh.brw; y: sh.height - sh.br.height; width: sh.brw; height: sh.br.height
            KSvg.SvgItem { svg: s; elementId: "shadow-bottomright"; x: sh.brw - width; width: sh.br.width; height: sh.br.height } }
        }
        KSvg.SvgItem { svg: s; elementId: "shadow-bottom"; x: sh.bottomOnly ? 0 : sh.blw; y: sh.height - height; width: sh.bottomOnly ? sh.width : sh.width - sh.blw - sh.brw; height: s.elementRect("shadow-bottom").height }
    }

    // ---- top bar (north, bottom border only) ----
    Shadow { target: topbar; file: "widgets/panel-background"; bottomOnly: true }
    KSvg.FrameSvgItem { id: topbar; imagePath: win.pfx + "widgets/panel-background"; prefix: ["north", ""]
        enabledBorders: KSvg.FrameSvg.BottomBorder; x: 0; y: 0; width: win.width; height: 34 }

    // ---- dock (south, 88 px thick incl. 16 px headroom, 16 px above the bottom edge) ----
    Shadow { target: dock; file: "widgets/panel-background" }
    KSvg.FrameSvgItem { id: dock; imagePath: win.pfx + "widgets/panel-background"; prefix: ["south", ""]
        x: 470; y: win.height - 16 - 88; width: 500; height: 88
        Row { x: parent.margins.left + 4; y: parent.margins.top; spacing: 8
            Repeater { model: 8; Rectangle { width: 48; height: 48; radius: 13; color: Qt.hsla(index / 8, 0.6, 0.55, 1) } } }
    }

    // ---- popup with controls ----
    Shadow { target: popup; file: "dialogs/background" }
    KSvg.FrameSvgItem { id: popup; imagePath: win.pfx + "dialogs/background"; x: 40; y: 60; width: 420; height: 520
        ColumnLayout {
            anchors.fill: parent; anchors.leftMargin: popup.margins.left; anchors.rightMargin: popup.margins.right
            anchors.topMargin: popup.margins.top; anchors.bottomMargin: popup.margins.bottom
            spacing: 8
            PlasmaExtras.PlasmoidHeading { Layout.fillWidth: true
                contentItem: RowLayout { PC3.ToolButton { icon.name: "go-previous" } PlasmaExtras.Heading { text: "Wi-Fi"; level: 3; Layout.fillWidth: true } PC3.Switch { checked: true } } }
            RowLayout { PC3.Button { text: "Open"; highlighted: true } PC3.Button { text: "Show in folder" } PC3.Button { text: "Focus"; focus: true; Component.onCompleted: forceActiveFocus(Qt.TabFocusReason) } PC3.Button { text: "Down"; checkable: true; checked: true } }
            RowLayout { PC3.ToolButton { icon.name: "configure"; text: "Tool" } PC3.ToolButton { icon.name: "view-refresh"; checkable: true; checked: true } }
            PC3.TextField { Layout.fillWidth: true; placeholderText: "Search" }
            RowLayout { PC3.CheckBox { text: "Checked"; checked: true } PC3.CheckBox { text: "Off" } PC3.RadioButton { text: "On"; checked: true } PC3.RadioButton { text: "Off" } }
            RowLayout { PC3.Switch { text: "On"; checked: true } PC3.Switch { text: "Off" } PC3.BusyIndicator { running: true; implicitWidth: 28; implicitHeight: 28 } }
            PC3.Slider { Layout.fillWidth: true; value: 0.6 }
            PC3.ProgressBar { Layout.fillWidth: true; value: 0.64 }
            PC3.TabBar { Layout.fillWidth: true; PC3.TabButton { text: "General" } PC3.TabButton { text: "Display" } PC3.TabButton { text: "Advanced" } }
            ListView { Layout.fillWidth: true; Layout.preferredHeight: 80; model: ["Office-Guest", "Café Libre"]; currentIndex: 0
                highlight: PlasmaExtras.Highlight {}
                delegate: PC3.ItemDelegate { width: ListView.view.width; text: modelData } }
            Item { Layout.fillHeight: true }
        }
    }

    // ---- tooltips ----
    Shadow { target: tip; file: "widgets/tooltip" }
    KSvg.FrameSvgItem { id: tip; imagePath: win.pfx + "widgets/tooltip"; x: 520; y: 90; width: 90; height: 32
        PC3.Label { anchors.centerIn: parent; text: "Browser"; font.bold: true } }
    Item { x: 640; y: 90; width: 110; height: 30
        KSvg.FrameSvgItem { id: ptipsh; imagePath: "solid/widgets/tooltip"; prefix: "shadow"; anchors.fill: parent
            anchors.leftMargin: -margins.left; anchors.topMargin: -margins.top; anchors.rightMargin: -margins.right; anchors.bottomMargin: -margins.bottom
            Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip; Kirigami.Theme.inherit: false }
        KSvg.FrameSvgItem { imagePath: "solid/widgets/tooltip"; anchors.fill: parent; Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip; Kirigami.Theme.inherit: false }
        PC3.Label { anchors.centerIn: parent; text: "Pin to dock"; Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip; Kirigami.Theme.inherit: false } }

    // ---- desktop widget card ----
    KSvg.FrameSvgItem { id: wid; imagePath: win.pfx + "widgets/background"; prefix: ["blurred", ""]; x: 1226; y: 56; width: 192; height: 120
        PC3.Label { x: 16; y: 14; text: "Local weather" } }

    // ---- menubar items in the top bar, task items in dock ----
    Row { x: 80; y: 4; spacing: 2
        KSvg.FrameSvgItem { imagePath: "widgets/menubaritem"; prefix: "normal"; width: 40; height: 26; PC3.Label { anchors.centerIn: parent; text: "File" } }
        KSvg.FrameSvgItem { imagePath: "widgets/menubaritem"; prefix: "hover"; width: 44; height: 26; PC3.Label { anchors.centerIn: parent; text: "View" } } }
    Row { x: 1000; y: 780; spacing: 4
        Repeater { model: ["normal", "hover", "focus", "attention", "minimized"]
            KSvg.FrameSvgItem { imagePath: "widgets/tasks"; prefix: modelData; width: 56; height: 56 } } }
    KSvg.FrameSvgItem { imagePath: "widgets/tabbar"; prefix: "north-active-tab"; x: 1300; y: 0; width: 60; height: 34 }

    Component.onCompleted: console.warn("DIAG", JSON.stringify({
        popupMargins: [popup.margins.top, popup.margins.left], popupFromCurrent: popup.fromCurrentImageSet,
        topPrefix: topbar.usedPrefix, dockPrefix: dock.usedPrefix, dockMinH: dock.minimumDrawingHeight, dockMargins: [dock.margins.top, dock.margins.bottom, dock.margins.left],
        topMinH: topbar.minimumDrawingHeight, widgetPrefix: wid.usedPrefix, tipMargins: tip.margins.top, pc3shadow: [ptipsh.usedPrefix, ptipsh.margins.top] }))
    Timer { interval: 3000; running: true; onTriggered: win.contentItem.grabToImage(function(r) {
        r.saveToFile(Qt.application.arguments[Qt.application.arguments.length - 1]); Qt.quit() }) }
}
