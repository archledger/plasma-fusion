// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtCore
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

import "../code/chips.js" as Chips

// The capsule's panel (LiveChips board, the Popups board's frame): "In use", a row for each app or
// login, with the action the source offers (Mute, Stop sharing, End), and Application permissions
// when that settings page is installed (flatpak-kcm). Rows 48 px, radius 12; a 30 px badge in the
// kind's tint with its glyph; the name in 800, the kind under it in 11.5 px; buttons 28 px high.
ColumnLayout {
    id: panel

    required property FusionMetrics metrics
    required property bool dark
    // [{ name, muted, setMuted() }]
    required property var microphoneApps
    // apps reading a camera, else the cameras' names
    required property var cameraApps
    required property var cameraNames
    required property bool cameraInUse
    // the portal's sessions, [{ key, kind, app, window, input }]
    required property var portalSessions
    // remote logins, [{ id, user, host, ssh, since }]
    required property var logins

    // Shown as the capsule's tooltip on hover (main.qml), not as its pop-up.
    property bool hover: false

    signal endSession(string key)
    signal closeRequested()

    // Test hook: the rows and their buttons on the screen, once the panel's window shows and has
    // settled (a pop-up learns its place after it is first shown).
    readonly property bool shown: Window.window !== null && Window.window.visible
    onShownChanged: if (shown) panelReport.restart()
    onRowsChanged: if (shown) panelReport.restart()
    onHeightChanged: if (shown) panelReport.restart()
    Connections {
        target: panel.Window.window
        function onXChanged() { if (panel.shown) panelReport.restart(); }
        function onYChanged() { if (panel.shown) panelReport.restart(); }
    }
    Timer {
        id: panelReport
        interval: 600
        onTriggered: {
            if (!panel.shown) {
                return;
            }
            const parts = [];
            for (let i = 0; i < rowRepeater.count; ++i) {
                const row = rowRepeater.itemAt(i);
                if (!row) {
                    continue;
                }
                const b = row.button;
                const g = b.mapToGlobal(b.width / 2, b.height / 2);
                parts.push(row.modelData.kind + " " + JSON.stringify(row.modelData.title) + (b.visible ? " " + JSON.stringify(row.modelData.action)
                           + " at " + Math.round(g.x) + "," + Math.round(g.y) : ""));
            }
            console.info("livechips: " + (panel.hover ? "hover panel " : "panel ") + parts.join("; "));
        }
    }

    readonly property color ink: Kirigami.Theme.textColor
    readonly property color dim: Kirigami.Theme.disabledTextColor
    readonly property bool permissionsInstalled: String(StandardPaths.locate(StandardPaths.ApplicationsLocation, "kcm_app-permissions.desktop")) !== ""

    // The rows in the board's order: what records or sees first, then who controls or signed in.
    readonly property var rows: {
        const out = [];
        for (const app of microphoneApps) {
            out.push({ kind: "microphone", title: app.name || i18nc("@info an unnamed app", "An app"),
                       subtitle: app.muted ? i18nc("@info the app's microphone stream", "Microphone, muted") : i18nc("@info", "Microphone"),
                       action: app.muted ? i18nc("@action:button", "Unmute") : i18nc("@action:button", "Mute"),
                       run: () => app.setMuted(!app.muted) });
        }
        if (cameraInUse) {
            const named = cameraApps.length > 0;
            const list = named ? cameraApps : (cameraNames.length > 0 ? cameraNames : [i18nc("@info", "A camera")]);
            for (const name of list) {
                out.push({ kind: "camera", title: name,
                           subtitle: named ? i18nc("@info", "Camera") : i18nc("@info a camera", "In use"), action: "", run: null });
            }
        }
        for (const s of portalSessions) {
            if (s.kind !== "screen") {
                continue;
            }
            out.push({ kind: "screen", title: s.app || i18nc("@info an unnamed app", "An app"),
                       subtitle: s.window ? i18nc("@info", "Sharing a window") : i18nc("@info", "Sharing the screen"),
                       action: i18nc("@action:button", "Stop sharing"), run: () => panel.endSession(s.key) });
        }
        for (const s of portalSessions) {
            if (s.kind !== "remote") {
                continue;
            }
            out.push({ kind: "remote", title: s.app || i18nc("@info an unnamed app", "An app"),
                       subtitle: s.input ? i18nc("@info", "Controls the pointer and keys") : i18nc("@info", "Sees the screen"),
                       action: i18nc("@action:button", "End"), run: () => panel.endSession(s.key) });
        }
        for (const l of logins) {
            const since = Qt.formatTime(new Date(l.since), Qt.locale().timeFormat(Locale.ShortFormat));
            out.push({ kind: "ssh",
                       title: l.host !== "" ? i18nc("@info %1 user, %2 host", "%1 from %2", l.user, l.host) : l.user,
                       subtitle: l.ssh ? i18nc("@info %1 a time of day", "Signed in over SSH since %1", since)
                                       : i18nc("@info %1 a time of day", "Signed in remotely since %1", since),
                       action: "", run: null });
        }
        return out;
    }

    function glyphColor(kind: string): color {
        switch (kind) {
        case "microphone": return Kirigami.Theme.neutralTextColor;
        case "camera": return Kirigami.Theme.positiveTextColor;
        case "screen": return Kirigami.Theme.visitedLinkColor;
        case "remote": return Kirigami.Theme.negativeTextColor;
        case "ssh": return Kirigami.Theme.linkColor;
        }
        return ink;
    }

    spacing: metrics.px(10)
    Layout.preferredWidth: metrics.px(328)
    Layout.minimumWidth: metrics.px(328)

    Text {
        Layout.fillWidth: true
        text: i18nc("@title the live chips' panel", "In use")
        color: panel.ink
        font.family: panel.metrics.family
        font.weight: Font.ExtraBold
        font.pixelSize: panel.metrics.font(16)
        Accessible.role: Accessible.Heading
    }

    Repeater {
        id: rowRepeater
        model: panel.rows
        delegate: Rectangle {
            id: rowItem
            required property var modelData
            readonly property Item button: actionButton
            Layout.fillWidth: true
            Layout.preferredHeight: panel.metrics.px(48)
            radius: 12
            color: Qt.rgba(panel.ink.r, panel.ink.g, panel.ink.b, 0.06)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: panel.metrics.px(10)
                anchors.rightMargin: panel.metrics.px(10)
                spacing: panel.metrics.px(12)

                Rectangle {
                    Layout.preferredWidth: panel.metrics.px(30)
                    Layout.preferredHeight: panel.metrics.px(30)
                    radius: width / 2
                    color: {
                        const t = Chips.tint(rowItem.modelData.kind, panel.dark);
                        return t ? Qt.rgba(t.r, t.g, t.b, t.a) : "transparent";
                    }
                    LineIcon {
                        anchors.centerIn: parent
                        path: Chips.GLYPHS[rowItem.modelData.kind]
                        color: panel.glyphColor(rowItem.modelData.kind)
                        size: panel.metrics.px(16)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: rowItem.modelData.title
                        elide: Text.ElideRight
                        color: panel.ink
                        font.family: panel.metrics.family
                        font.weight: Font.ExtraBold
                        font.pixelSize: panel.metrics.font(16)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: rowItem.modelData.subtitle
                        elide: Text.ElideRight
                        color: panel.dim
                        font.family: panel.metrics.family
                        font.pixelSize: panel.metrics.font(11.5)
                    }
                }
                Rectangle {
                    id: actionButton
                    visible: rowItem.modelData.action !== ""
                    Layout.preferredHeight: panel.metrics.px(28)
                    Layout.preferredWidth: actionLabel.implicitWidth + panel.metrics.px(24)
                    radius: height / 2
                    color: Qt.rgba(panel.ink.r, panel.ink.g, panel.ink.b, actionArea.containsPress ? 0.2 : actionArea.containsMouse ? 0.16 : 0.12)
                    activeFocusOnTab: visible
                    Accessible.role: Accessible.Button
                    Accessible.name: i18nc("@action:button %1 the action, %2 the app", "%1 %2", rowItem.modelData.action, rowItem.modelData.title)
                    Accessible.onPressAction: rowItem.modelData.run()
                    Keys.onSpacePressed: rowItem.modelData.run()
                    Keys.onReturnPressed: rowItem.modelData.run()
                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: rowItem.modelData.action
                        color: panel.ink
                        font.family: panel.metrics.family
                        font.weight: Font.Bold
                        font.pixelSize: panel.metrics.font(12)
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: height / 2
                        visible: actionButton.activeFocus
                        color: "transparent"
                        border.width: 2
                        border.color: Kirigami.Theme.focusColor
                    }
                    MouseArea {
                        id: actionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: rowItem.modelData.run()
                    }
                }
            }
        }
    }

    Text {
        id: permissions
        visible: panel.permissionsInstalled
        Layout.leftMargin: panel.metrics.px(4)
        text: i18nc("@action:button opens System Settings' Application Permissions", "Application permissions…")
        color: Kirigami.Theme.linkColor
        font.family: panel.metrics.family
        font.weight: Font.Bold
        font.pixelSize: panel.metrics.font(12)
        font.underline: permissionsArea.containsMouse
        activeFocusOnTab: visible
        Accessible.role: Accessible.Link
        Accessible.name: text
        Accessible.onPressAction: panel.openPermissions()
        Keys.onReturnPressed: panel.openPermissions()
        MouseArea {
            id: permissionsArea
            anchors.fill: parent
            anchors.margins: -2
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.openPermissions()
        }
    }
    function openPermissions(): void {
        console.info("livechips: open Application Permissions");
        KCMUtils.KCMLauncher.openSystemSettings("kcm_app-permissions");
        closeRequested();
    }
}
