// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.extras as PlasmaExtras

import "components"
import "components/Icons.js" as Icons

// Wi-Fi drill-down (Popups board, "Tray panel"): switch, the connected network
// with its speed, the other networks and the footer links.
ColumnLayout {
    id: page

    required property var backend
    required property FusionPalette pal
    // 4.5 rows, so a cut row shows that the list scrolls
    property real listMaxHeight: 206

    signal back()

    readonly property Item firstFocusItem: header.backButton

    // plasma-nm enums (org.kde.plasma.networkmanagement Enums)
    readonly property int stateActivating: 1
    readonly property int stateActivated: 2
    readonly property int stateDeactivated: 4

    function securityLabel(type) {
        switch (type) {
        case 0: return i18nc("@info Wi-Fi security", "Open");
        case 1: case 2: return "WEP";
        case 3: return "LEAP";
        case 4: return "WPA";
        case 5: return "WPA‑EAP";
        case 6: return "WPA2";
        case 7: return "WPA2‑EAP";
        case 8: return "WPA3";
        case 9: return "WPA3‑EAP";
        case 10: return "OWE";
        default: return "";
        }
    }
    function isSecured(type) {
        return type > 0;
    }
    function hasStaticPassword(type) {
        return type === 1 || type === 4 || type === 6 || type === 8;
    }
    function levelFor(signal) {
        if (signal >= 80) return 4;
        if (signal >= 55) return 3;
        if (signal >= 30) return 2;
        return 1;
    }
    function signalText(signal) {
        if (signal >= 80) return i18nc("@info Wi-Fi signal", "Signal excellent");
        if (signal >= 55) return i18nc("@info Wi-Fi signal", "Signal good");
        if (signal >= 30) return i18nc("@info Wi-Fi signal", "Signal fair");
        return i18nc("@info Wi-Fi signal", "Signal weak");
    }
    function formatRate(bytesPerSecond) {
        const bits = bytesPerSecond * 8;
        if (bits >= 1e9) return i18nc("@info network speed", "%1 Gb/s", (bits / 1e9).toFixed(1));
        if (bits >= 1e6) return i18nc("@info network speed", "%1 Mb/s", Math.round(bits / 1e6));
        if (bits >= 1e3) return i18nc("@info network speed", "%1 kb/s", Math.round(bits / 1e3));
        return i18nc("@info network speed", "%1 b/s", Math.round(bits));
    }
    function bandFromDetails(detailsModel) {
        if (!detailsModel || typeof detailsModel.rowCount !== "function") {
            return "";
        }
        const valueRole = detailsModel.KItemModels.KRoleNames.role("detailValue");
        if (valueRole < 0) {
            return "";
        }
        for (let i = 0; i < detailsModel.rowCount(); ++i) {
            const value = String(detailsModel.data(detailsModel.index(i, 0), valueRole) || "");
            const m = /(\d+(?:[.,]\d+)?)\s*GHz/.exec(value);
            if (m) {
                const ghz = Number(m[1].replace(",", "."));
                return ghz >= 5.9 ? "6 GHz" : (ghz >= 4.9 ? "5 GHz" : "2.4 GHz");
            }
        }
        return "";
    }

    spacing: 12

    // ---------------------------------------------------------------- header
    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        title: i18nc("@title", "Wi‑Fi")
        hasSwitch: true
        switchText: i18nc("@action:button", "Wi‑Fi")
        switchChecked: page.backend.net.wifiEnabled
        switchEnabled: page.backend.net.wifiHwEnabled && !page.backend.net.airplane
        onBack: page.back()
        onSwitchToggled: on => page.backend.net.setWifiEnabled(on)
    }

    // ---------------------------------------------------------------- connected network
    Repeater {
        model: page.backend.net.wifiEnabled ? page.backend.net.activeModel : null

        delegate: Rectangle {
            id: activeCard
            required property var model
            required property int index

            readonly property bool connected: model.ConnectionState === page.stateActivated
            property real rxSpeed: 0
            property real txSpeed: 0
            property double prevRx: 0
            property double prevTx: 0
            property bool measured: false

            Layout.fillWidth: true
            visible: index === 0
            implicitHeight: cardColumn.implicitHeight + 24
            radius: 14
            color: page.pal.activeCard

            Component.onCompleted: page.backend.net.setStatistics(model.DevicePath, true)
            Component.onDestruction: page.backend.net.setStatistics(model.DevicePath, false)

            Timer {
                interval: 2000
                repeat: true
                triggeredOnStart: true
                running: activeCard.connected && activeCard.visible
                onTriggered: {
                    const rx = Number(activeCard.model.RxBytes || 0);
                    const tx = Number(activeCard.model.TxBytes || 0);
                    activeCard.rxSpeed = activeCard.prevRx > 0 && rx >= activeCard.prevRx ? (rx - activeCard.prevRx) / (interval / 1000) : 0;
                    activeCard.txSpeed = activeCard.prevTx > 0 && tx >= activeCard.prevTx ? (tx - activeCard.prevTx) / (interval / 1000) : 0;
                    activeCard.measured = activeCard.prevRx > 0 && rx > activeCard.prevRx;
                    activeCard.prevRx = rx;
                    activeCard.prevTx = tx;
                }
            }

            ColumnLayout {
                id: cardColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 12
                }
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    NetworkGlyph {
                        pal: page.pal
                        size: 20
                        kind: "wifi"
                        level: page.levelFor(activeCard.model.Signal || 0)
                        baseColor: page.pal.activeCardText
                        color: page.pal.activeCardText
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        FText {
                            Layout.fillWidth: true
                            pal: page.pal
                            text: activeCard.model.ItemUniqueName || activeCard.model.Ssid || ""
                            color: page.pal.activeCardTitle
                            font.weight: Font.ExtraBold
                        }
                        FText {
                            Layout.fillWidth: true
                            pal: page.pal
                            color: page.pal.activeCardText
                            px: 11.5
                            text: {
                                if (!activeCard.connected) {
                                    return i18nc("@info:status", "Connecting…");
                                }
                                const parts = [i18nc("@info:status", "Connected")];
                                const band = page.bandFromDetails(activeCard.model.ConnectionDetailsModel);
                                if (band) {
                                    parts.push(band);
                                }
                                const security = page.securityLabel(activeCard.model.SecurityType);
                                if (security) {
                                    parts.push(security);
                                }
                                return parts.join(" · ");
                            }
                        }
                    }
                    TextButton {
                        pal: page.pal
                        implicitHeight: 28
                        radius: 14
                        fill: page.pal.overlay(0.12)
                        textColor: page.pal.activeCardTitle
                        text: i18nc("@action:button", "Disconnect")
                        onClicked: page.backend.net.deactivate(activeCard.model.ConnectionPath, activeCard.model.DevicePath)
                    }
                }
                Row {
                    Layout.fillWidth: true
                    leftPadding: 30
                    spacing: 18
                    visible: activeCard.connected
                    FText {
                        pal: page.pal
                        text: page.signalText(activeCard.model.Signal || 0)
                        color: page.pal.activeCardStats
                        px: 11.5
                    }
                    FText {
                        pal: page.pal
                        visible: activeCard.measured
                        text: "↓ " + page.formatRate(activeCard.rxSpeed)
                        color: page.pal.activeCardStats
                        px: 11.5
                    }
                    FText {
                        pal: page.pal
                        visible: activeCard.measured
                        text: "↑ " + page.formatRate(activeCard.txSpeed)
                        color: page.pal.activeCardStats
                        px: 11.5
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- other networks
    FText {
        Layout.fillWidth: true
        pal: page.pal
        leftPadding: 4
        visible: page.backend.net.wifiEnabled
        text: i18nc("@title:group", "Other networks").toUpperCase()
        color: page.pal.tertiary
        px: 11
        font.weight: Font.ExtraBold
        font.letterSpacing: 0.88
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(contentHeight, page.listMaxHeight)
        Layout.maximumHeight: contentHeight
        visible: page.backend.net.wifiEnabled && count > 0
        clip: true
        spacing: 2
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        activeFocusOnTab: true
        currentIndex: -1
        model: page.backend.net.wifiEnabled ? page.backend.net.otherModel : null

        delegate: Item {
            id: row
            required property var model
            required property int index

            readonly property bool busy: model.ConnectionState === page.stateActivating
            readonly property bool needsPassword: !model.Uuid && page.hasStaticPassword(model.SecurityType)
            property bool expanded: false

            width: ListView.view.width
            height: expanded ? 44 + passwordRow.implicitHeight + 8 : 44

            function connect() {
                if (row.model.Uuid) {
                    page.backend.net.activate(row.model.ConnectionPath, row.model.DevicePath, row.model.SpecificPath);
                } else if (row.needsPassword) {
                    row.expanded = !row.expanded;
                    if (row.expanded) {
                        passwordField.forceActiveFocus();
                    }
                } else {
                    page.backend.net.addAndActivate(row.model.DevicePath, row.model.SpecificPath, "");
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: rowMouse.containsMouse || row.ListView.isCurrentItem || row.expanded ? page.pal.overlay(0.06) : "transparent"
                FocusRing {
                    baseRadius: 10
                    anchors.margins: -2
                    ringColor: page.pal.focus
                    shown: row.ListView.isCurrentItem && list.activeFocus
                }
            }

            MouseArea {
                id: rowMouse
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: 44
                hoverEnabled: true
                onClicked: row.connect()
            }

            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: 10
                    rightMargin: 10
                }
                height: 44
                spacing: 12

                NetworkGlyph {
                    pal: page.pal
                    size: 20
                    kind: "wifi"
                    level: page.levelFor(row.model.Signal || 0)
                    color: page.pal.text
                    opacity: row.busy ? 0.5 : 1
                }
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    text: row.model.ItemUniqueName || row.model.Ssid || ""
                    font.weight: Font.Bold
                }
                FText {
                    pal: page.pal
                    visible: row.busy
                    text: i18nc("@info:status", "Connecting…")
                    color: page.pal.secondary
                    px: 11.5
                }
                LineIcon {
                    visible: page.isSecured(row.model.SecurityType)
                    size: 14
                    path: Icons.lock
                    color: page.pal.secondary
                }
            }

            RowLayout {
                id: passwordRow
                visible: row.expanded
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: 44
                    leftMargin: 10
                    rightMargin: 10
                }
                spacing: 8

                PlasmaExtras.PasswordField {
                    id: passwordField
                    Layout.fillWidth: true
                    placeholderText: i18nc("@info:placeholder", "Password")
                    onAccepted: connectButton.clicked()
                    Keys.onEscapePressed: event => {
                        row.expanded = false;
                        event.accepted = true;
                    }
                }
                TextButton {
                    id: connectButton
                    pal: page.pal
                    primary: true
                    implicitHeight: 30
                    radius: 10
                    text: i18nc("@action:button", "Connect")
                    enabled: passwordField.text.length >= (row.model.SecurityType === 1 ? 5 : 8)
                    onClicked: {
                        page.backend.net.addAndActivate(row.model.DevicePath, row.model.SpecificPath, passwordField.text);
                        passwordField.text = "";
                        row.expanded = false;
                    }
                }
            }
        }

        Keys.onReturnPressed: {
            if (currentItem) {
                currentItem.connect();
            }
        }
        Keys.onSpacePressed: {
            if (currentItem) {
                currentItem.connect();
            }
        }
    }

    FText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 44
        pal: page.pal
        visible: !list.visible
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: page.pal.secondary
        text: {
            if (page.backend.net.airplane) {
                return i18nc("@info", "Airplane mode is on");
            }
            if (!page.backend.net.wifiEnabled) {
                return i18nc("@info", "Wi‑Fi is off");
            }
            return i18nc("@info", "Looking for networks…");
        }
    }

    Item {
        Layout.fillHeight: true
        visible: list.visible
    }

    // ---------------------------------------------------------------- footer
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: page.pal.overlay(0.08)
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        TextButton {
            pal: page.pal
            implicitHeight: 32
            sidePadding: 0
            fill: "transparent"
            textColor: page.pal.link
            fontSize: 12.5
            text: i18nc("@action:button", "Hidden network…")
            onClicked: page.backend.net.openSettings()
        }
        Item {
            Layout.fillWidth: true
        }
        TextButton {
            pal: page.pal
            implicitHeight: 32
            radius: 16
            sidePadding: 14
            fill: page.pal.overlay(0.08)
            fontSize: 12.5
            iconPath: Icons.settingsSmall
            text: i18nc("@action:button", "Network settings")
            onClicked: page.backend.net.openSettings()
        }
    }
}
