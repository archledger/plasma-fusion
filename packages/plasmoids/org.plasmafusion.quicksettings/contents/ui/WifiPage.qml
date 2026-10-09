// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
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
    required property FusionMetrics metrics
    // 4.5 rows, so a cut row shows that the list scrolls (rows follow the text size)
    property real listMaxHeight: 4.5 * rowHeight + 4 * 2
    // Height of a network row: 44 px on the board, scaled with the text.
    readonly property real rowHeight: metrics.px(44)

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

    spacing: metrics.px(12)

    // ---------------------------------------------------------------- header
    PageHeader {
        id: header
        Layout.fillWidth: true
        pal: page.pal
        metrics: page.metrics
        // Without a Wi-Fi radio the page has the VPN connections and the airplane mode switch.
        title: page.backend.net.wifiDevice ? i18nc("@title", "Wi‑Fi") : i18nc("@title", "Network")
        hasSwitch: page.backend.net.wifiDevice
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
            implicitHeight: cardColumn.implicitHeight + 2 * cardColumn.anchors.margins
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
                    margins: page.metrics.px(12)
                }
                spacing: page.metrics.px(8)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: page.metrics.px(10)

                    NetworkGlyph {
                        id: activeGlyph
                        pal: page.pal
                        size: page.metrics.px(20)
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
                            metrics: page.metrics
                            text: activeCard.model.ItemUniqueName || activeCard.model.Ssid || ""
                            color: page.pal.activeCardTitle
                            font.weight: Font.ExtraBold
                        }
                        FText {
                            Layout.fillWidth: true
                            pal: page.pal
                            metrics: page.metrics
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
                        metrics: page.metrics
                        implicitHeight: page.metrics.px(28)
                        fill: page.pal.overlay(0.12)
                        textColor: page.pal.activeCardTitle
                        text: i18nc("@action:button", "Disconnect")
                        onClicked: page.backend.net.deactivate(activeCard.model.ConnectionPath, activeCard.model.DevicePath)
                    }
                }
                Row {
                    Layout.fillWidth: true
                    leftPadding: activeGlyph.width + page.metrics.px(10)
                    spacing: page.metrics.px(18)
                    visible: activeCard.connected
                    FText {
                        pal: page.pal
                        metrics: page.metrics
                        text: page.signalText(activeCard.model.Signal || 0)
                        color: page.pal.activeCardStats
                        px: 11.5
                    }
                    FText {
                        pal: page.pal
                        metrics: page.metrics
                        visible: activeCard.measured
                        text: "↓ " + page.formatRate(activeCard.rxSpeed)
                        color: page.pal.activeCardStats
                        px: 11.5
                    }
                    FText {
                        pal: page.pal
                        metrics: page.metrics
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
        metrics: page.metrics
        leftPadding: page.metrics.px(4)
        visible: page.backend.net.wifiEnabled
        text: i18nc("@title:group", "Other networks").toUpperCase()
        color: page.pal.tertiary
        px: 11
        font.weight: Font.ExtraBold
        font.letterSpacing: page.metrics.font(0.88)
    }

    ListView {
        id: list
        Accessible.name: i18nc("@title:group", "Other networks")
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
            height: expanded ? page.rowHeight + passwordRow.implicitHeight + page.metrics.px(8) : page.rowHeight

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
                // The row's own name and actions are its accessible face (the list's keys).
                Accessible.ignored: true
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: page.rowHeight
                hoverEnabled: true
                onClicked: row.connect()
            }

            RowLayout {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: page.metrics.px(10)
                    rightMargin: page.metrics.px(10)
                }
                height: page.rowHeight
                spacing: page.metrics.px(12)

                NetworkGlyph {
                    pal: page.pal
                    size: page.metrics.px(20)
                    kind: "wifi"
                    level: page.levelFor(row.model.Signal || 0)
                    color: page.pal.text
                    opacity: row.busy ? 0.5 : 1
                }
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    metrics: page.metrics
                    text: row.model.ItemUniqueName || row.model.Ssid || ""
                    font.weight: Font.Bold
                }
                FText {
                    pal: page.pal
                    metrics: page.metrics
                    visible: row.busy
                    text: i18nc("@info:status", "Connecting…")
                    color: page.pal.secondary
                    px: 11.5
                }
                LineIcon {
                    visible: page.isSecured(row.model.SecurityType)
                    size: page.metrics.px(14)
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
                    topMargin: page.rowHeight
                    leftMargin: page.metrics.px(10)
                    rightMargin: page.metrics.px(10)
                }
                spacing: page.metrics.px(8)

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
                    metrics: page.metrics
                    primary: true
                    implicitHeight: page.metrics.px(30)
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
        Layout.minimumHeight: page.metrics.px(44)
        pal: page.pal
        metrics: page.metrics
        visible: !list.visible && page.backend.net.wifiDevice
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
            if (page.backend.net.hotspotActive) {
                return i18nc("@info", "The hotspot is using the Wi‑Fi radio");
            }
            return i18nc("@info", "Looking for networks…");
        }
    }

    Item {
        Layout.fillHeight: true
        visible: list.visible
    }

    // ---------------------------------------------------------------- VPN
    // The VPN connections (plugin VPNs and WireGuard), as the stock Networks widget lists them:
    // a click connects, or disconnects the active one.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        visible: vpnBox.visible
        color: page.pal.overlay(0.08)
    }
    ColumnLayout {
        id: vpnBox
        Layout.fillWidth: true
        visible: page.backend.net.vpnCount > 0
        spacing: page.metrics.px(2)
        FText {
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            text: i18nc("@title", "VPN")
            font.weight: Font.Bold
        }
        Repeater {
            model: page.backend.net.vpnModel
            delegate: ListRow {
                id: vpnRow
                required property var model
                readonly property bool connected: model.ConnectionState === page.stateActivated
                readonly property bool connecting: model.ConnectionState === page.stateActivating
                Layout.fillWidth: true
                pal: page.pal
                metrics: page.metrics
                text: model.Name || ""
                iconPath: Icons.lock
                selected: connected
                busy: connecting
                status: connected ? i18nc("@info:status VPN", "Connected")
                      : connecting ? i18nc("@info:status VPN", "Connecting…") : ""
                trailingPath: connected ? Icons.check : ""
                Accessible.description: connected || connecting ? i18nc("@info:tooltip", "Click to disconnect") : i18nc("@info:tooltip", "Click to connect")
                onClicked: {
                    if (connected || connecting) {
                        page.backend.net.deactivate(model.ConnectionPath, model.DevicePath);
                    } else {
                        page.backend.net.activate(model.ConnectionPath, model.DevicePath, model.SpecificPath);
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- airplane mode
    // The stock Networks widget's switch: Wi-Fi, mobile data and Bluetooth off, and back on.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        visible: airplaneRow.visible
        color: page.pal.overlay(0.08)
    }
    RowLayout {
        id: airplaneRow
        Layout.fillWidth: true
        visible: page.backend.net.airplaneAvailable
        spacing: page.metrics.px(8)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            FText {
                Layout.fillWidth: true
                pal: page.pal
                metrics: page.metrics
                text: i18nc("@title", "Airplane mode")
                font.weight: Font.Bold
            }
            FText {
                Layout.fillWidth: true
                pal: page.pal
                metrics: page.metrics
                px: 11.5
                color: page.pal.secondary
                wrapMode: Text.Wrap
                text: page.backend.net.airplane ? i18nc("@info", "Wi‑Fi and Bluetooth are off")
                                                : i18nc("@info", "Turns off Wi‑Fi and Bluetooth")
            }
        }
        FusionSwitch {
            pal: page.pal
            text: i18nc("@action:button", "Airplane mode")
            checked: page.backend.net.airplane
            onToggled: {
                page.backend.net.setAirplaneMode(checked);
                checked = Qt.binding(() => page.backend.net.airplane);
            }
        }
    }

    // ---------------------------------------------------------------- hotspot
    // plasma-nm's own hotspot (the stock Networks applet's settings): start and stop, the
    // reason when the radio can't run one, and the network name and password to share.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        visible: hotspotBox.visible
        color: page.pal.overlay(0.08)
    }
    ColumnLayout {
        id: hotspotBox
        Layout.fillWidth: true
        visible: page.backend.net.wifiDevice
        spacing: page.metrics.px(6)
        // The password shows on request only and hides again when the hotspot starts or stops.
        // It is read once on Show: plasma-nm's setting has no change signal to bind to.
        property string shownPassword: ""
        readonly property bool revealed: shownPassword !== ""
        property bool editing: false
        readonly property bool entriesValid: hotspotName.text.trim() !== ""
            && (hotspotPassword.text === "" || hotspotPassword.text.length >= 8)

        Connections {
            target: page.backend.net
            function onHotspotActiveChanged() {
                hotspotBox.shownPassword = "";
                hotspotBox.editing = false;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: page.metrics.px(8)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    metrics: page.metrics
                    text: i18nc("@title", "Wi‑Fi hotspot")
                    font.weight: Font.Bold
                }
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    metrics: page.metrics
                    px: 11.5
                    color: page.pal.secondary
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    text: page.backend.net.hotspotError || page.backend.net.hotspotHint
                }
            }
            TextButton {
                pal: page.pal
                metrics: page.metrics
                primary: !page.backend.net.hotspotActive
                implicitHeight: page.metrics.px(30)
                radius: 10
                text: page.backend.net.hotspotActive ? i18nc("@action:button", "Stop hotspot")
                                                     : i18nc("@action:button", "Start hotspot")
                // Stop stays available while a start is still being watched for failure.
                enabled: page.backend.net.hotspotActive || (page.backend.net.hotspotReady && !page.backend.net.hotspotStarting
                    && (!hotspotBox.editing || hotspotBox.entriesValid))
                onClicked: {
                    if (!page.backend.net.hotspotActive && hotspotBox.editing
                            && !page.backend.net.configureHotspot(hotspotName.text, hotspotPassword.text)) {
                        return;
                    }
                    hotspotPassword.text = "";
                    page.backend.net.toggleHotspot();
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: page.backend.net.hotspotActive
            spacing: page.metrics.px(8)
            FText {
                Layout.fillWidth: true
                pal: page.pal
                metrics: page.metrics
                textFormat: Text.PlainText
                text: i18nc("@info %1 is the hotspot password", "Password: %1",
                            hotspotBox.revealed ? hotspotBox.shownPassword : "••••••••")
            }
            TextButton {
                pal: page.pal
                metrics: page.metrics
                implicitHeight: page.metrics.px(30)
                fill: "transparent"
                textColor: page.pal.link
                fontSize: 12.5
                text: hotspotBox.revealed ? i18nc("@action:button", "Hide password")
                                          : i18nc("@action:button", "Show password")
                onClicked: hotspotBox.shownPassword = hotspotBox.revealed ? "" : page.backend.net.hotspotPassword()
            }
        }
        TextButton {
            visible: !page.backend.net.hotspotActive && !hotspotBox.editing
            pal: page.pal
            metrics: page.metrics
            implicitHeight: page.metrics.px(30)
            sidePadding: 0
            fill: "transparent"
            textColor: page.pal.link
            fontSize: 12.5
            text: i18nc("@action:button", "Change name and password…")
            onClicked: {
                hotspotName.text = page.backend.net.hotspotName;
                hotspotBox.editing = true;
                hotspotName.forceActiveFocus();
            }
        }
        QQC2.TextField {
            id: hotspotName
            Layout.fillWidth: true
            visible: hotspotBox.editing && !page.backend.net.hotspotActive
            placeholderText: i18nc("@info:placeholder", "Hotspot network name")
            Accessible.name: i18nc("@label:textbox", "Hotspot network name")
            maximumLength: 32
        }
        PlasmaExtras.PasswordField {
            id: hotspotPassword
            Layout.fillWidth: true
            visible: hotspotBox.editing && !page.backend.net.hotspotActive
            placeholderText: i18nc("@info:placeholder", "New password, 8–63 characters (empty keeps the current one)")
            Accessible.name: i18nc("@label:textbox", "Hotspot password")
            maximumLength: 63
        }
    }

    // ---------------------------------------------------------------- footer
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: page.pal.overlay(0.08)
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: page.metrics.px(8)

        TextButton {
            visible: page.backend.net.wifiDevice
            pal: page.pal
            metrics: page.metrics
            implicitHeight: page.metrics.px(32)
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
            metrics: page.metrics
            implicitHeight: page.metrics.px(32)
            radius: height / 2
            sidePadding: page.metrics.px(14)
            fill: page.pal.overlay(0.08)
            fontSize: 12.5
            iconPath: Icons.settingsSmall
            text: i18nc("@action:button", "Network settings")
            onClicked: page.backend.net.openSettings()
        }
    }
}
