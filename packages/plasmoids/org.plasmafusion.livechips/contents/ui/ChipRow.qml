// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../code/chips.js" as Chips

// The chips in the bar (LiveChips board): Keep awake's time left, a recording's time with its
// stop button, and the privacy capsule (a glyph for each kind in use; one kind tints the capsule).
// Chips 22 px high, radius 11, 6 px apart, 14 px glyphs, figures in Space Grotesk 600 12 px.
RowLayout {
    id: row

    required property FusionMetrics metrics
    required property bool dark
    // Chips.capsule()
    required property var capsule
    // { time } of Spectacle's recording, or null
    required property var recording
    // Keep awake: its time left (Chips.timeLeft) while a timed Keep awake runs
    required property bool keepAwakeOn
    required property var keepAwakeLeft
    required property bool panelOpen

    signal capsuleClicked()
    signal stopRecording()
    signal keepAwakeClicked()

    // Test hook: where the chips are on the screen, once the panel has laid them out.
    function report(): string {
        const parts = [];
        for (const [name, item] of [["keepawake", keepAwakeChip], ["stop", stopButton], ["capsule", capsuleChip]]) {
            if (item.visible && item.width > 0) {
                const g = item.mapToGlobal(0, 0);
                parts.push(name + " " + Math.round(g.x) + "," + Math.round(g.y) + " " + Math.round(item.width) + "x" + Math.round(item.height));
            }
        }
        return parts.join("; ");
    }

    // The capsule, for the hover panel's place (main.qml); the chips, for the keyboard test.
    readonly property Item capsuleItem: capsuleChip
    readonly property Item keepAwakeItem: keepAwakeChip
    readonly property Item stopItem: stopButton
    readonly property color ink: Kirigami.Theme.textColor
    readonly property real chipHeight: metrics.px(22)

    spacing: metrics.px(6)

    function glyphColor(kind: string): color {
        switch (kind) {
        case "microphone": return Kirigami.Theme.neutralTextColor;
        case "camera": return Kirigami.Theme.positiveTextColor;
        case "screen": return Kirigami.Theme.visitedLinkColor;
        case "remote":
        case "recording": return Kirigami.Theme.negativeTextColor;
        case "ssh": return Kirigami.Theme.linkColor;
        }
        return ink;
    }
    function tintColor(kind: string): color {
        const t = Chips.tint(kind, dark);
        return t ? Qt.rgba(t.r, t.g, t.b, t.a) : Qt.rgba(ink.r, ink.g, ink.b, 0.08);
    }
    // A chip's keyboard focus ring (the panel's buttons draw the same).
    component FocusRing: Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: Kirigami.Theme.focusColor
    }

    function leftText(left: var): string {
        if (left.hours > 0) {
            return left.minutes > 0 ? i18nc("@info time left of Keep awake, in the bar", "%1 h %2 min", left.hours, left.minutes)
                                    : i18nc("@info time left of Keep awake, in the bar", "%1 h", left.hours);
        }
        return i18nc("@info time left of Keep awake, in the bar", "%1 min", left.minutes);
    }

    // ---- Keep awake for a set time: a click opens it in quick settings
    Rectangle {
        id: keepAwakeChip
        visible: row.keepAwakeOn
        Layout.preferredHeight: row.chipHeight
        Layout.preferredWidth: awakeContent.implicitWidth + row.metrics.px(18)
        radius: height / 2
        color: Qt.rgba(row.ink.r, row.ink.g, row.ink.b, awakeArea.containsPress ? 0.16 : awakeArea.containsMouse ? 0.12 : 0.08)
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: i18nc("@action:button %1 time left", "Keep awake, %1 left", awakeText.text)
        Accessible.onPressAction: row.keepAwakeClicked()
        Keys.onSpacePressed: row.keepAwakeClicked()
        Keys.onReturnPressed: row.keepAwakeClicked()
        Keys.onEnterPressed: row.keepAwakeClicked()
        FocusRing {
            visible: keepAwakeChip.activeFocus
        }

        RowLayout {
            id: awakeContent
            anchors.centerIn: parent
            spacing: row.metrics.px(6)
            LineIcon {
                path: Chips.GLYPHS.keepawake
                color: row.ink
                size: row.metrics.px(14)
            }
            Text {
                id: awakeText
                text: row.leftText(row.keepAwakeLeft)
                color: row.ink
                font.family: row.metrics.displayFamily
                font.weight: Font.DemiBold
                font.pixelSize: row.metrics.font(12)
            }
        }
        MouseArea {
            id: awakeArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: row.keepAwakeClicked()
        }
    }

    // ---- a screen recording: the time runs; the round button stops it
    Rectangle {
        id: recordingChip
        visible: row.recording !== null
        Layout.preferredHeight: row.chipHeight
        Layout.preferredWidth: recordingContent.implicitWidth + row.metrics.px(13)
        radius: height / 2
        color: row.tintColor("recording")

        RowLayout {
            id: recordingContent
            anchors.verticalCenter: parent.verticalCenter
            x: row.metrics.px(9)
            spacing: row.metrics.px(7)
            Rectangle {
                Layout.preferredWidth: row.metrics.px(7)
                Layout.preferredHeight: row.metrics.px(7)
                radius: width / 2
                color: row.glyphColor("recording")
            }
            Text {
                visible: text !== ""
                text: row.recording ? row.recording.time : ""
                color: row.glyphColor("recording")
                font.family: row.metrics.displayFamily
                font.weight: Font.DemiBold
                font.pixelSize: row.metrics.font(12)
            }
            Rectangle {
                id: stopButton
                Layout.preferredWidth: row.metrics.px(16)
                Layout.preferredHeight: row.metrics.px(16)
                radius: width / 2
                color: row.glyphColor("recording")
                opacity: stopArea.containsPress ? 0.75 : 1
                activeFocusOnTab: recordingChip.visible
                Accessible.role: Accessible.Button
                Accessible.name: i18nc("@action:button", "Stop recording")
                Accessible.onPressAction: row.stopRecording()
                Keys.onSpacePressed: row.stopRecording()
                Keys.onReturnPressed: row.stopRecording()
                Keys.onEnterPressed: row.stopRecording()
                FocusRing {
                    visible: stopButton.activeFocus
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: row.metrics.px(6)
                    height: row.metrics.px(6)
                    radius: 1
                    color: Kirigami.Theme.backgroundColor
                }
                MouseArea {
                    id: stopArea
                    // The 16 px button with a finger-sized target around it (the bar is on a screen edge).
                    anchors.centerIn: parent
                    width: row.metrics.hit(parent.width, true)
                    height: row.chipHeight
                    hoverEnabled: true
                    onClicked: row.stopRecording()
                }
            }
        }
    }

    // ---- the privacy capsule: a click opens the panel under it
    Rectangle {
        id: capsuleChip
        visible: row.capsule.kinds.length > 0
        Layout.preferredHeight: row.chipHeight
        Layout.preferredWidth: glyphs.implicitWidth + row.metrics.px(16)
        radius: height / 2
        color: {
            const base = row.capsule.tintKind !== "" ? row.tintColor(row.capsule.tintKind) : Qt.rgba(row.ink.r, row.ink.g, row.ink.b, 0.08);
            const lift = row.panelOpen || capsuleArea.containsPress ? 0.08 : capsuleArea.containsMouse ? 0.04 : 0;
            return Qt.rgba(base.r, base.g, base.b, Math.min(1, base.a + lift));
        }
        activeFocusOnTab: visible
        Accessible.role: Accessible.Button
        Accessible.name: i18nc("@action:button the live chips' panel", "In use")
        Accessible.onPressAction: row.capsuleClicked()
        Keys.onSpacePressed: row.capsuleClicked()
        Keys.onReturnPressed: row.capsuleClicked()
        Keys.onEnterPressed: row.capsuleClicked()
        FocusRing {
            visible: capsuleChip.activeFocus
        }

        RowLayout {
            id: glyphs
            anchors.centerIn: parent
            spacing: row.metrics.px(6)
            Repeater {
                model: row.capsule.kinds
                delegate: LineIcon {
                    required property string modelData
                    path: Chips.GLYPHS[modelData]
                    color: row.glyphColor(modelData)
                    size: row.metrics.px(14)
                }
            }
        }
        MouseArea {
            id: capsuleArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: row.capsuleClicked()
        }
    }
}
