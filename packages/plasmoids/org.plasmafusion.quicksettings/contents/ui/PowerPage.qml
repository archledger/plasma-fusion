// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "components"
import "../code/keepawake.js" as Timed

// Keep awake (the Keep awake tile's chevron): for a while (F7: 1 hour, 4 hours, until a time of day
// or until turned off, the tile's own click), then the sleep blockers: the applications' requests
// from PowerDevil, as the stock battery applet lists them (InhibitionControl leaves out
// plasmashell's own, so Keep awake is not one of them). PowerDevil reports a new request after 5 s.
ColumnLayout {
    id: page
    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    signal back()
    readonly property Item firstFocusItem: header.backButton
    spacing: metrics.px(12)

    // The "Until" time chooser is shown (its choice button).
    property bool untilOpen: false

    // "sleep and screen locking", "sleep" or "screen locking" from a request's behaviours.
    function behaviours(list: var): string {
        const sleep = list.indexOf("sleep") !== -1;
        const idle = list.indexOf("idle") !== -1;
        if (sleep && idle) {
            return i18nc("@info what an application blocks", "sleep and screen locking");
        }
        return sleep ? i18nc("@info what an application blocks", "sleep")
                     : i18nc("@info what an application blocks", "screen locking");
    }

    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        title: i18nc("@title", "Keep awake")
        hasSwitch: true
        switchText: i18nc("@action:button", "Keep awake")
        switchChecked: page.backend.keepAwake.active
        switchEnabled: page.backend.keepAwake.available
        onSwitchToggled: on => {
            if (on !== page.backend.keepAwake.active) {
                page.backend.keepAwake.toggle();
            }
        }
        onBack: page.back()
    }
    FText {
        objectName: "keepawake-state"
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        color: page.pal.secondary
        wrapMode: Text.Wrap
        text: {
            const k = page.backend.keepAwake;
            if (k.timed) {
                return i18nc("@info %1 a time of day, %2 remaining time", "On until %1 (%2 left)", k.untilText, k.leftText);
            }
            return k.active ? i18nc("@info", "On until turned off")
                            : i18nc("@info", "Blocks sleep, display power saving and automatic screen locking:");
        }
    }
    // For a while (as Do Not Disturb's choices).
    Flow {
        Layout.fillWidth: true
        spacing: page.metrics.px(8)
        Repeater {
            model: [
                { "id": "1h", "text": i18nc("@action:button keep awake", "For 1 hour") },
                { "id": "4h", "text": i18nc("@action:button keep awake", "For 4 hours") },
                { "id": "until", "text": i18nc("@action:button keep awake until a time of day", "Until…") },
                { "id": "off", "text": i18nc("@action:button keep awake", "Until turned off") }
            ]
            delegate: TextButton {
                required property var modelData
                objectName: "keepawake-" + modelData.id
                pal: page.pal
                metrics: page.metrics
                radius: height / 2
                implicitHeight: page.pal.touch ? 44 : page.metrics.px(30)
                fontSize: 12.5
                enabled: page.backend.keepAwake.available
                // The choice in force: timed (1 h and 4 h alike), or until turned off.
                primary: modelData.id === "until" ? page.untilOpen
                       : modelData.id === "off" && page.backend.keepAwake.active && !page.backend.keepAwake.timed
                text: modelData.text
                onClicked: {
                    switch (modelData.id) {
                    case "1h":
                        page.backend.keepAwake.forHours(1);
                        break;
                    case "4h":
                        page.backend.keepAwake.forHours(4);
                        break;
                    case "until":
                        page.untilOpen = !page.untilOpen;
                        return;
                    default:
                        if (page.backend.keepAwake.active) {
                            page.backend.keepAwake.untilTurnedOff();
                        } else {
                            page.backend.keepAwake.toggle();
                        }
                        break;
                    }
                    page.untilOpen = false;
                }
            }
        }
    }
    // Until a time of day: today, or tomorrow once it has passed; 15-minute steps, the locale's
    // time format.
    RowLayout {
        Layout.fillWidth: true
        visible: page.untilOpen
        spacing: page.metrics.px(8)
        FText {
            pal: page.pal
            metrics: page.metrics
            text: i18nc("@label:spinbox keep awake until a time of day", "Until")
        }
        QQC2.SpinBox {
            id: untilTime
            objectName: "keepawake-time"
            from: 0
            to: 24 * 60 - 15
            stepSize: 15
            wrap: true
            editable: false
            value: Timed.defaultUntil(new Date())
            textFromValue: (value, locale) => Qt.formatTime(new Date(2000, 0, 1, Math.floor(value / 60), value % 60),
                                                            Qt.locale().timeFormat(Locale.ShortFormat))
            Accessible.name: i18nc("@label:spinbox", "Keep awake until")
        }
        Item {
            Layout.fillWidth: true
        }
        TextButton {
            objectName: "keepawake-start"
            pal: page.pal
            metrics: page.metrics
            primary: true
            radius: height / 2
            implicitHeight: page.pal.touch ? 44 : page.metrics.px(30)
            fontSize: 12.5
            enabled: page.backend.keepAwake.available
            text: i18nc("@action:button keep awake until the chosen time", "Start")
            onClicked: {
                page.backend.keepAwake.untilMinuteOfDay(untilTime.value);
                page.untilOpen = false;
            }
        }
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: page.pal.overlay(0.08)
    }
    FText {
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        text: i18nc("@title:group", "Sleep blockers")
        px: 14
        font.weight: Font.ExtraBold
    }
    FText {
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        color: page.pal.secondary
        // The energy note follows the stock applet's (an EU requirement for a manual block).
        text: page.backend.keepAwake.active
            ? i18nc("@info", "Keep awake is on, which uses more energy. Applications' requests are separate:")
            : i18nc("@info", "Applications currently requesting to block sleep or screen locking:")
        wrapMode: Text.Wrap
    }
    FText {
        Layout.fillWidth: true
        visible: page.backend.keepAwake.inhibitors.length === 0
        pal: page.pal
        metrics: page.metrics
        text: i18nc("@info", "No application is blocking sleep")
    }
    Repeater {
        model: page.backend.keepAwake.inhibitors
        delegate: RowLayout {
            id: request
            required property var modelData
            Layout.fillWidth: true
            spacing: page.metrics.px(10)
            Kirigami.Icon {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: page.metrics.px(28)
                Layout.preferredHeight: page.metrics.px(28)
                source: request.modelData.icon || "application-x-executable"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: page.metrics.px(2)
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    metrics: page.metrics
                    text: request.modelData.prettyName || request.modelData.appName
                    font.weight: Font.Bold
                }
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    metrics: page.metrics
                    px: 11.5
                    color: page.pal.secondary
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    text: {
                        const what = page.behaviours(request.modelData.behaviors || []);
                        const status = request.modelData.allowed
                            ? i18nc("@info:status %1 is what the application blocks", "Blocking %1", what)
                            : i18nc("@info:status %1 is what the application wanted to block", "Prevented from blocking %1", what);
                        return request.modelData.reason ? status + " · " + request.modelData.reason : status;
                    }
                }
                QQC2.CheckBox {
                    text: i18nc("@option:check", "Allow this application's request")
                    checked: request.modelData.allowed
                    Accessible.name: text
                    onClicked: page.backend.keepAwake.setAllowed(request.modelData.appName, request.modelData.reason, checked)
                }
            }
        }
    }
    Item {
        Layout.fillHeight: true
    }
}
