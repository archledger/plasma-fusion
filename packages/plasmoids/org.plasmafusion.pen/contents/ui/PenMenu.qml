// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "services"
import "Icons.js" as Icons

// The pen menu card (PEN.md 3.3): header (pen glyph, "Pen", the pen's name, gear), a grid of three
// columns of action tiles and, as a drill-down in the same card, the pen settings page. Tiles
// whose app is missing are left out (whiteboard, draw on screen) or turn into an install tile
// (new note without Xournal++); apps are looked up each time the menu opens.
FocusScope {
    id: menu

    required property FusionMetrics metrics
    required property PenDevice device
    required property Exec exec
    property string shortcutText: ""
    // The card's outer width and the pop-up frame's own padding: the content keeps 16 px from the
    // card's edge in total (404 - 2 x 16 = 372 px for the tiles).
    property real outerWidth: metrics.px(404)
    property real frameLeft: 0
    property real frameRight: 0
    property real frameTop: 0
    property real frameBottom: 0
    readonly property real contentWidth: outerWidth - frameLeft - frameRight
    property real maxHeight: 800
    property string page: "main"

    signal closeRequested()
    signal actionRequested(string id)
    // One line with the card's controls and their global positions, after the page changes or a
    // settings row opens (logged by main.qml, for the tests and bug reports).
    signal report(string text)
    // Reported once the card has settled (the pop-up placed, the rows laid out).
    function requestReport(): void {
        reportTimer.restart();
    }
    Timer {
        id: reportTimer
        interval: 200
        onTriggered: menu.report(menu.describe())
    }
    onPageChanged: requestReport()

    readonly property color ink: Kirigami.Theme.textColor
    // The accent of the pop-up window's own colour set.
    readonly property alias tint: accent
    FusionAccent {
        id: accent
    }
    readonly property real pad: metrics.px(16)
    readonly property real padLeft: Math.max(0, pad - frameLeft)
    readonly property real padTop: Math.max(0, pad - frameTop)
    readonly property real padBottom: Math.max(0, pad - frameBottom)
    readonly property real innerWidth: outerWidth - 2 * pad

    property bool hasXournal: false
    property bool hasWayscriber: false
    function refresh(): void {
        hasXournal = String(StandardPaths.findExecutable("xournalpp")).length > 0;
        hasWayscriber = String(StandardPaths.findExecutable("wayscriber")).length > 0;
    }

    // The integrated pen's own name (KWin reports the digitizer's HID name).
    readonly property string penTitle: {
        const n = device.name;
        if (n.length === 0 || /534D/i.test(n)) {
            return i18nc("@info the pen's name", "Lenovo Integrated Pen");
        }
        return n;
    }

    readonly property var tiles: {
        const out = [];
        const ids = Plasmoid.configuration.actions || [];
        for (let i = 0; i < ids.length; ++i) {
            const id = String(ids[i]);
            if (id === "newnote") {
                out.push(hasXournal
                         ? { "id": id, "text": i18nc("@action pen menu", "New note"), "sub": "Xournal++", "icon": Icons.note, "primary": true }
                         : { "id": "installxournal", "text": i18nc("@action pen menu", "Install Xournal++"), "sub": i18nc("@info", "For notes"), "icon": Icons.download, "primary": true });
            } else if (id === "snip") {
                out.push({ "id": id, "text": i18nc("@action pen menu", "Snip"), "sub": i18nc("@info", "Drag to copy"), "icon": Icons.snip, "primary": false });
            } else if (id === "markup") {
                out.push({ "id": id, "text": i18nc("@action pen menu", "Mark up"), "sub": i18nc("@info", "Screenshot"), "icon": Icons.markup, "primary": false });
            } else if (id === "whiteboard" && hasXournal) {
                out.push({ "id": id, "text": i18nc("@action pen menu", "Whiteboard"), "sub": i18nc("@info", "Blank page"), "icon": Icons.whiteboard, "primary": false });
            } else if (id === "drawonscreen" && hasWayscriber) {
                out.push({ "id": id, "text": i18nc("@action pen menu", "Draw on screen"), "sub": i18nc("@info", "Live ink"), "icon": Icons.ink, "primary": false });
            } else if (id === "settings") {
                out.push({ "id": id, "text": i18nc("@action pen menu", "Pen settings"), "sub": i18nc("@info", "Buttons, pressure"), "icon": Icons.gear, "primary": false });
            }
        }
        return out;
    }

    function focusFirst(): void {
        if (page === "main") {
            const first = grid.children.length > 0 ? grid.children[0] : null;
            if (first) {
                first.forceActiveFocus(Qt.TabFocusReason);
            }
        } else {
            if (settingsLoader.item) {
                settingsLoader.item.forceActiveFocus(Qt.TabFocusReason);
            }
        }
    }
    // Geometry of the visible tiles, for the open log line (tests).
    function describe(): string {
        const out = [];
        for (let i = 0; i < grid.children.length; ++i) {
            const t = grid.children[i];
            if (t.objectName && t.objectName.startsWith("tile-")) {
                const g = t.mapToGlobal(0, 0);
                out.push(t.objectName.slice(5) + "@" + Math.round(g.x) + "," + Math.round(g.y) + ":" + t.width.toFixed(2) + "x" + t.height.toFixed(2));
            }
        }
        if (page === "settings") {
            return "page settings: " + (settingsLoader.item ? settingsLoader.item.describe() : "");
        }
        return "page main: tiles " + out.join(" ");
    }
    function openSettings(): void {
        page = "settings";
        if (settingsLoader.item) {
            settingsLoader.item.reload();
        }
        flick.contentY = 0;
    }

    implicitWidth: contentWidth
    implicitHeight: Math.min(maxHeight, flick.contentHeight)

    Keys.onEscapePressed: {
        if (page === "settings") {
            page = "main";
        } else {
            closeRequested();
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: (menu.page === "main" ? mainPage.implicitHeight : (settingsLoader.item ? settingsLoader.item.implicitHeight : 0)) + menu.padTop + menu.padBottom
        clip: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: mainPage
            x: menu.padLeft
            y: menu.padTop
            width: menu.innerWidth
            spacing: menu.metrics.px(14)
            visible: menu.page === "main"

            // Header: 44 px icon well, "Pen" and the pen's name, gear button.
            Item {
                width: parent.width
                height: menu.metrics.px(44)

                Rectangle {
                    id: well
                    width: menu.metrics.px(44)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(menu.ink.r, menu.ink.g, menu.ink.b, 0.08)
                    LineIcon {
                        anchors.centerIn: parent
                        size: menu.metrics.px(20)
                        path: Icons.pen
                        color: menu.ink
                    }
                }
                Column {
                    anchors.left: well.right
                    anchors.leftMargin: menu.metrics.px(10)
                    anchors.right: gear.left
                    anchors.rightMargin: menu.metrics.px(8)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        text: i18nc("@title", "Pen")
                        color: menu.ink
                        font.pixelSize: menu.metrics.font(17)
                        font.weight: Font.ExtraBold
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }
                    Text {
                        width: parent.width
                        text: menu.penTitle
                        color: menu.ink
                        opacity: 0.75
                        font.pixelSize: menu.metrics.font(12.5)
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
                T.AbstractButton {
                    id: gear
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: menu.metrics.px(44)
                    height: width
                    hoverEnabled: true
                    focusPolicy: Qt.StrongFocus
                    text: i18nc("@action:button", "Pen settings")
                    Accessible.name: text
                    onClicked: menu.openSettings()
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                    background: Rectangle {
                        anchors.centerIn: parent
                        width: menu.metrics.px(34)
                        height: width
                        radius: width / 2
                        color: Qt.rgba(menu.ink.r, menu.ink.g, menu.ink.b, gear.down ? 0.16 : gear.hovered ? 0.12 : 0.08)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: menu.tint.focusRing
                            visible: gear.visualFocus
                        }
                    }
                    contentItem: Item {
                        LineIcon {
                            anchors.centerIn: parent
                            size: menu.metrics.px(16)
                            path: Icons.gear
                            color: menu.ink
                        }
                    }
                }
            }

            // Action tiles: three columns, 10 px apart ((content - 20) / 3 = 117.33 at 372).
            Grid {
                id: grid
                width: parent.width
                columns: 3
                spacing: menu.metrics.px(10)

                Repeater {
                    model: menu.tiles
                    PenTile {
                        required property var modelData
                        objectName: "tile-" + modelData.id
                        width: (grid.width - 2 * grid.spacing) / 3
                        metrics: menu.metrics
                        tint: menu.tint
                        ink: menu.ink
                        text: modelData.text
                        subtitle: modelData.sub
                        iconPath: modelData.icon
                        primary: modelData.primary
                        onClicked: {
                            if (modelData.id === "settings") {
                                menu.openSettings();
                            } else {
                                menu.actionRequested(modelData.id);
                            }
                        }
                    }
                }
            }
        }

        // Built only while it is shown (PEN.md PT8: the card's cost after the first open).
        Loader {
            id: settingsLoader
            x: menu.padLeft
            y: menu.padTop
            width: menu.innerWidth
            active: menu.page === "settings"
            visible: active
            sourceComponent: PenSettings {
                objectName: "penSettings"
                width: settingsLoader.width
                metrics: menu.metrics
                tint: menu.tint
                ink: menu.ink
                device: menu.device
                exec: menu.exec
                shortcutText: menu.shortcutText
                onBack: {
                    menu.page = "main";
                    menu.focusFirst();
                }
                onCloseRequested: menu.closeRequested()
                onRowsChanged: menu.requestReport()
            }
        }
    }
}
