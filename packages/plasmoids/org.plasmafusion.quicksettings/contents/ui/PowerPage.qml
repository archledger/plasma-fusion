// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "components"

// Sleep blockers (Keep awake's chevron): the applications' requests from PowerDevil, as the stock
// battery applet lists them (InhibitionControl leaves out plasmashell's own, so Keep awake is not
// one of them). PowerDevil reports a new request after 5 s.
ColumnLayout {
    id: page
    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics
    signal back()
    readonly property Item firstFocusItem: header.backButton
    spacing: metrics.px(12)

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
        title: i18nc("@title", "Sleep blockers")
        onBack: page.back()
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
