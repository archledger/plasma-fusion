// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "components"
import "components/Icons.js" as Icons

// Main page of the pop-up (Quick Settings board): battery chip and header
// buttons, volume and brightness sliders, six tiles and the media card. In tablet posture
// (TABLET 4.6) the header is 44 px, a tablet row (rotation lock, keyboard, full-screen apps, pen)
// follows it, the sliders are 44 px bars and a Tablet mode tile joins the tiles; phone and
// clipboard get rows here when the top bar has no room for them.
// Text, the rows and chips that hold it and the gaps between them follow the user's text size
// (`metrics`); the round icon buttons, sliders and the album art keep their board sizes.
ColumnLayout {
    id: page

    required property var backend
    required property FusionPalette pal
    required property FusionMetrics metrics

    signal openPage(string name, Item opener)

    readonly property alias firstFocusItem: screenshotButton
    readonly property alias wifiDetails: wifiTile.detailsButton
    readonly property alias bluetoothDetails: bluetoothTile.detailsButton
    readonly property alias audioDetails: audioChevron

    readonly property bool tablet: pal.tablet
    readonly property var tabletPolicy: backend.tabletPolicy
    // The Do Not Disturb durations are shown (the tile's chevron).
    property bool dndChoicesOpen: false
    property bool chargeChoicesOpen: false

    spacing: metrics.px(14)

    // ---------------------------------------------------------------- header row
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: page.tablet ? Math.max(44, page.metrics.px(34)) : Math.max(34, page.metrics.px(34))
        spacing: page.tablet ? 12 : 6

        Rectangle {
            id: batteryChip
            visible: page.backend.battery.present
            Layout.preferredHeight: page.tablet ? Math.max(44, page.metrics.px(34)) : page.metrics.px(34)
            Layout.preferredWidth: chipRow.implicitWidth + page.metrics.px(24)
            radius: height / 2
            color: chipHover.hovered ? page.pal.overlay(0.1) : page.pal.overlay(0.07)
            Accessible.role: Accessible.Button
            Accessible.name: i18nc("@action:button %1 battery charge", "Battery %1%, power settings", page.backend.battery.percent)
            Accessible.onPressAction: page.backend.battery.openSettings()

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: page.metrics.px(6)
                BatteryGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    pal: page.pal
                    size: page.metrics.px(18)
                    percent: page.backend.battery.percent
                    charging: page.backend.battery.charging
                }
                FText {
                    anchors.verticalCenter: parent.verticalCenter
                    pal: page.pal
                    metrics: page.metrics
                    text: i18nc("@info battery charge", "%1%", page.backend.battery.percent)
                    font.weight: Font.ExtraBold
                    font.features: { "tnum": 1 }
                }
            }
            HoverHandler {
                id: chipHover
            }
            TapHandler {
                onTapped: page.backend.battery.openSettings()
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                location: PlasmaCore.Types.Floating
                mainText: i18nc("@info:tooltip", "Battery %1%", page.backend.battery.percent)
                subText: {
                    const b = page.backend.battery;
                    if (b.charging) {
                        return i18nc("@info:tooltip", "Charging");
                    }
                    if (b.full) {
                        return i18nc("@info:tooltip", "Fully charged");
                    }
                    if (b.pluggedIn) {
                        return i18nc("@info:tooltip", "Plugged in, not charging");
                    }
                    if (b.remainingMsec > 0) {
                        const minutes = Math.round(b.remainingMsec / 60000);
                        return i18nc("@info:tooltip %1 hours %2 minutes", "About %1 h %2 min left",
                                     Math.floor(minutes / 60), minutes % 60);
                    }
                    return "";
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        IconButton {
            id: screenshotButton
            pal: page.pal
            size: page.tablet ? 44 : 34
            iconPath: Icons.screenshot
            text: i18nc("@action:button", "Take a screenshot")
            onClicked: page.backend.session.screenshot()
        }
        IconButton {
            pal: page.pal
            size: page.tablet ? 44 : 34
            iconPath: Icons.settings
            text: i18nc("@action:button", "System Settings")
            onClicked: page.backend.session.openSystemSettings()
        }
        IconButton {
            pal: page.pal
            size: page.tablet ? 44 : 34
            iconPath: Icons.lock
            text: i18nc("@action:button", "Lock the screen")
            enabled: page.backend.session.canLock
            onClicked: page.backend.session.lock()
        }
        IconButton {
            pal: page.pal
            size: page.tablet ? 44 : 34
            iconPath: Icons.power
            text: i18nc("@action:button", "Shut down, restart or log out…")
            onClicked: page.backend.session.leave()
        }
    }

    // ---------------------------------------------------------------- tablet row
    // 44 px round toggles, 12 apart (TABLET 4.6; gesture lock TABLET2 G1); the label shows on a long press.
    Row {
        id: tabletRow
        Layout.fillWidth: true
        visible: page.tablet && page.tabletPolicy !== null
        spacing: 12

        IconButton {
            id: rotationToggle
            objectName: "tabletRow-rotation"
            pal: page.pal
            size: 44
            iconPath: Icons.rotate
            toggleOn: page.tabletPolicy ? page.tabletPolicy.rotationLocked : false
            text: toggleOn ? i18nc("@action:button", "Rotation locked") : i18nc("@action:button", "Rotation lock")
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: toggleOn
            onClicked: page.tabletPolicy.setRotationLocked(!toggleOn)

            // The lock badge while locked (owner decision T17).
            Rectangle {
                visible: rotationToggle.toggleOn
                x: parent.width - width - 2
                y: 2
                width: 16
                height: 16
                radius: 8
                color: page.pal.accentText
                LineIcon {
                    anchors.centerIn: parent
                    size: 11
                    path: Icons.lock
                    color: page.pal.accent
                }
            }
        }
        IconButton {
            objectName: "tabletRow-keyboard"
            visible: page.tabletPolicy ? page.tabletPolicy.oskAvailable : false
            pal: page.pal
            size: 44
            iconPath: Icons.keyboard
            toggleOn: page.tabletPolicy ? page.tabletPolicy.oskVisible : false
            text: toggleOn ? i18nc("@action:button", "Hide the keyboard") : i18nc("@action:button", "Show the keyboard")
            onClicked: page.tabletPolicy.toggleOsk()
        }
        IconButton {
            objectName: "tabletRow-fullscreen"
            pal: page.pal
            size: 44
            iconPath: Icons.fullscreen
            toggleOn: page.tabletPolicy ? page.tabletPolicy.windowMode === "fullscreen" : true
            text: i18nc("@action:button", "Full-screen apps")
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: toggleOn
            onClicked: page.tabletPolicy.setWindowMode(toggleOn ? "windowed" : "fullscreen")
        }
        IconButton {
            id: gestureToggle
            objectName: "tabletRow-gestures"
            pal: page.pal
            size: 44
            iconPath: Icons.swipeUp
            toggleOn: page.tabletPolicy ? page.tabletPolicy.gestureLocked : false
            text: toggleOn ? i18nc("@action:button", "Gestures locked: swipe twice") : i18nc("@action:button", "Gesture lock")
            Accessible.role: Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: toggleOn
            onClicked: page.tabletPolicy.setGestureLocked(!toggleOn)

            Rectangle {
                visible: gestureToggle.toggleOn
                x: parent.width - width - 2
                y: 2
                width: 16
                height: 16
                radius: 8
                color: page.pal.accentText
                LineIcon {
                    anchors.centerIn: parent
                    size: 11
                    path: Icons.lock
                    color: page.pal.accent
                }
            }
        }
        IconButton {
            objectName: "tabletRow-pen"
            visible: page.backend.penPresent
            pal: page.pal
            size: 44
            iconPath: Icons.pen
            text: i18nc("@action:button", "Pen menu")
            onClicked: page.backend.penRequested()
        }
    }

    // ---------------------------------------------------------------- sliders
    ColumnLayout {
        Layout.fillWidth: true
        spacing: page.tablet ? 12 : 10
        visible: page.backend.audio.available || page.backend.audio.inputAvailable || page.backend.display.brightnessAvailable

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: page.pal.touch ? 44 : 28
            spacing: 12
            visible: page.backend.audio.available

            IconButton {
                id: muteButton
                pal: page.pal
                size: 28
                fill: "transparent"
                hoverFill: "transparent"
                pressFill: "transparent"
                iconSize: 18
                iconPath: ""
                text: page.backend.audio.muted ? i18nc("@action:button", "Unmute") : i18nc("@action:button", "Mute")
                onClicked: page.backend.audio.toggleMute()
                Layout.preferredWidth: page.pal.touch ? 44 : 18
                Layout.preferredHeight: page.pal.touch ? 44 : 28

                VolumeGlyph {
                    anchors.centerIn: parent
                    pal: page.pal
                    size: 18
                    baseColor: page.pal.controlText
                    volume: page.backend.audio.volume
                    muted: page.backend.audio.muted
                }
            }
            FusionSlider {
                id: volumeSlider
                Layout.fillWidth: true
                pal: page.pal
                dimmed: page.backend.audio.muted
                Accessible.name: i18nc("@label:slider", "Volume")
                to: page.backend.audio.maximum
                value: Math.min(to, page.backend.audio.volume)
                onMoved: page.backend.audio.setVolume(value)
                onDraggingChanged: {
                    if (!dragging) {
                        value = Qt.binding(() => Math.min(to, page.backend.audio.volume));
                    }
                }
                PlasmaCore.ToolTipArea {
                    anchors.fill: parent
                    location: PlasmaCore.Types.Floating
                    mainText: page.backend.audio.deviceName
                    subText: page.backend.audio.muted ? i18nc("@info:tooltip", "Muted")
                                                      : i18nc("@info:tooltip", "%1%", Math.round(page.backend.audio.volume * 100))
                }
            }
            IconButton {
                id: audioChevron
                pal: page.pal
                size: page.pal.touch ? 32 : 28
                iconSize: 14
                iconPath: Icons.chevronRight
                text: i18nc("@action:button", "Choose audio output")
                onClicked: {
                    page.backend.audioPage = "output";
                    page.openPage("audio", audioChevron);
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: page.pal.touch ? 44 : 28
            spacing: 12
            visible: page.backend.audio.inputAvailable
            IconButton {
                pal: page.pal
                size: 28
                fill: "transparent"
                iconSize: 18
                iconPath: page.backend.audio.inputMuted ? Icons.microphone + Icons.slash : Icons.microphone
                text: page.backend.audio.inputMuted ? i18nc("@action:button", "Unmute microphone")
                                                    : i18nc("@action:button", "Mute microphone")
                Layout.preferredWidth: page.pal.touch ? 44 : 18
                Layout.preferredHeight: page.pal.touch ? 44 : 28
                onClicked: page.backend.audio.toggleInputMute()
            }
            FusionSlider {
                Layout.fillWidth: true
                pal: page.pal
                dimmed: page.backend.audio.inputMuted
                Accessible.name: i18nc("@label:slider", "Microphone volume")
                to: page.backend.audio.maximum
                value: page.backend.audio.inputVolume
                onMoved: page.backend.audio.setInputVolume(value)
                onDraggingChanged: if (!dragging) { value = Qt.binding(() => page.backend.audio.inputVolume); }
            }
            IconButton {
                id: inputChevron
                pal: page.pal
                size: page.pal.touch ? 32 : 28
                iconSize: 14
                iconPath: Icons.chevronRight
                text: i18nc("@action:button", "Choose microphone and application audio")
                onClicked: {
                    page.backend.audioPage = "input";
                    page.openPage("audio", inputChevron);
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: page.pal.touch ? 44 : 28
            spacing: 12
            visible: page.backend.display.brightnessAvailable

            Item {
                Layout.preferredWidth: page.pal.touch ? 44 : 18
                Layout.preferredHeight: 28
                LineIcon {
                    anchors.centerIn: parent
                    size: 18
                    path: Icons.brightness
                    color: page.pal.controlText
                }
            }
            FusionSlider {
                id: brightnessSlider
                Layout.fillWidth: true
                pal: page.pal
                from: 0.01
                Accessible.name: i18nc("@label:slider", "Screen brightness")
                value: page.backend.display.brightness
                onMoved: page.backend.display.setBrightness(value)
                onDraggingChanged: {
                    if (!dragging) {
                        value = Qt.binding(() => page.backend.display.brightness);
                    }
                }
            }
            Item {
                Layout.preferredWidth: audioChevron.implicitWidth
                Layout.preferredHeight: 28
            }
        }
    }

    // ---------------------------------------------------------------- tiles
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        rowSpacing: page.tablet ? 12 : page.metrics.px(10)
        columnSpacing: page.tablet ? 12 : page.metrics.px(10)
        uniformCellWidths: true

        Tile {
            id: wifiTile
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Wi‑Fi")
            subtitle: page.backend.net.subtitle
            iconPath: Icons.wifi
            checked: page.backend.net.checked
            available: page.backend.net.available && page.backend.net.wifiDevice
            hasDetails: page.backend.net.available && page.backend.net.wifiDevice
            detailsText: i18nc("@action:button", "Show Wi‑Fi networks")
            onToggled: {
                if (available) {
                    page.backend.net.toggle();
                } else {
                    page.backend.net.openSettings();
                }
            }
            onDetailsRequested: page.openPage("wifi", wifiTile.detailsButton)
        }
        Tile {
            id: bluetoothTile
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Bluetooth")
            subtitle: page.backend.bt.subtitle
            iconPath: Icons.bluetooth
            checked: page.backend.bt.checked
            available: page.backend.bt.available
            hasDetails: page.backend.bt.available
            detailsText: i18nc("@action:button", "Show Bluetooth devices")
            onToggled: {
                if (available) {
                    page.backend.bt.toggle();
                } else {
                    page.backend.bt.openSettings();
                }
            }
            onDetailsRequested: page.openPage("bluetooth", bluetoothTile.detailsButton)
        }
        Tile {
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Night light")
            subtitle: page.backend.night.subtitle
            iconPath: Icons.moon
            checked: page.backend.night.checked
            available: page.backend.night.available
            toolTip: page.backend.night.enabled ? i18nc("@info:tooltip", "Click to pause or resume Night Light")
                                                : i18nc("@info:tooltip", "Click to turn on Night Light")
            onToggled: page.backend.night.toggle()
        }
        Tile {
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Do not disturb")
            subtitle: page.backend.dnd.subtitle
            iconPath: Icons.bellOff
            checked: page.backend.dnd.active
            available: page.backend.dnd.available
            hasDetails: page.backend.dnd.available
            detailsText: i18nc("@action:button", "Do not disturb for a while")
            onToggled: page.backend.dnd.toggle()
            onDetailsRequested: page.dndChoicesOpen = !page.dndChoicesOpen
        }
        Tile {
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Power mode")
            subtitle: page.backend.profile.subtitle
            iconPath: Icons.gauge
            checked: page.backend.profile.checked
            available: page.backend.profile.available
            toolTip: i18nc("@info:tooltip", "Click to switch between Power saver, Balanced and Performance")
            onToggled: page.backend.profile.cycle()
        }
        Tile {
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Dark style")
            subtitle: page.backend.darkStyle.subtitle
            iconPath: Icons.contrast
            iconFillPath: Icons.contrastFill
            checked: page.backend.darkStyle.checked
            onToggled: page.backend.darkStyle.toggle()
        }
        Tile {
            objectName: "tile-keepawake"
            Layout.fillWidth: true
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Keep awake")
            subtitle: page.backend.keepAwake.subtitle
            iconPath: Icons.coffee
            checked: page.backend.keepAwake.active
            available: page.backend.keepAwake.available
            enabled: available
            hasDetails: page.backend.keepAwake.available
            detailsText: i18nc("@action:button", "Show applications blocking sleep")
            toolTip: checked ? i18nc("@info:tooltip", "Click to resume automatic sleep and screen locking")
                             : i18nc("@info:tooltip", "Manually block sleep and screen locking")
            onToggled: page.backend.keepAwake.toggle()
            onDetailsRequested: page.openPage("power", keepAwakeTile.detailsButton)
            id: keepAwakeTile
        }
        // Disks & Devices (stock tray item): shown while a removable device is connected; accent
        // while one of them is mounted. The body and the chevron open the device list.
        Tile {
            id: devicesTile
            objectName: "tile-devices"
            Layout.fillWidth: true
            visible: page.backend.devices.count > 0
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Disks & Devices")
            subtitle: page.backend.devices.subtitle
            iconPath: Icons.usbDrive
            checked: page.backend.devices.anyMounted
            hasDetails: true
            detailsText: i18nc("@action:button", "Show Disks & Devices")
            onToggled: page.openPage("devices", devicesTile.mainButton)
            onDetailsRequested: page.openPage("devices", devicesTile.detailsButton)
        }
        Tile {
            id: hotspotTile
            objectName: "tile-hotspot"
            Layout.fillWidth: true
            visible: page.backend.net.wifiDevice
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Wi‑Fi hotspot")
            subtitle: page.backend.net.hotspotSubtitle
            iconPath: Icons.wifi
            checked: page.backend.net.hotspotActive
            available: page.backend.net.hotspotReady
            hasDetails: true
            detailsText: i18nc("@action:button", "Hotspot and Wi‑Fi settings")
            toolTip: page.backend.net.hotspotHint
            // plasma-nm always has a password (it generates one); the Wi-Fi page shows it, and
            // the reason when the radio can't run a hotspot.
            onToggled: {
                if (available) {
                    page.backend.net.toggleHotspot();
                } else {
                    page.openPage("wifi", hotspotTile.mainButton);
                }
            }
            onDetailsRequested: page.openPage("wifi", hotspotTile.detailsButton)
        }
        // Battery charge limit (research D-desktop "Add"): a click turns the limit (80 % or the last
        // one picked) on or off; the chevron offers 80 %, 90 %, "Charge to 100 % once" (while
        // plugged in) and no limit. Shown where the system helper is installed and the battery has
        // a stop threshold (services/ChargeLimit.qml).
        Tile {
            objectName: "tile-chargelimit"
            Layout.fillWidth: true
            visible: page.backend.charge.present
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Charge limit")
            subtitle: page.backend.charge.subtitle
            iconPath: Icons.batteryOutline
            checked: page.backend.charge.limited || page.backend.charge.fullOnce
            available: !page.backend.charge.busy && !page.backend.charge.managed
            hasDetails: !page.backend.charge.managed
            detailsText: i18nc("@action:button", "Charge limit choices")
            toolTip: page.backend.charge.managed
                     ? i18nc("@info:tooltip", "TLP sets the charge limit on this computer (/etc/tlp.conf, /etc/tlp.d)")
                     : i18nc("@info:tooltip", "Click to limit charging to keep the battery healthy")
            onToggled: page.backend.charge.toggle()
            onDetailsRequested: page.chargeChoicesOpen = !page.chargeChoicesOpen
        }
        // Tablet mode Auto / On / Off (TABLET 3.2): shown where the posture can change by itself,
        // or when it is not automatic.
        Tile {
            objectName: "tile-tabletmode"
            Layout.fillWidth: true
            visible: page.tabletPolicy !== null && (page.backend.tabletAvailable || page.tabletPolicy.tabletModeSetting !== "auto")
            pal: page.pal
            metrics: page.metrics
            title: i18nc("@title tile", "Tablet mode")
            subtitle: {
                switch (page.tabletPolicy ? page.tabletPolicy.tabletModeSetting : "auto") {
                case "on":
                    return i18nc("@info:status tablet mode", "On");
                case "off":
                    return i18nc("@info:status tablet mode", "Off");
                default:
                    return i18nc("@info:status tablet mode follows the hinge", "Automatic");
                }
            }
            iconPath: Icons.tablet
            checked: page.tabletPolicy ? page.tabletPolicy.tabletModeSetting === "on" : false
            toolTip: i18nc("@info:tooltip", "Click to switch between Automatic, On and Off")
            onToggled: page.tabletPolicy.cycleTabletMode()
        }
    }

    // Do Not Disturb for a while (G18).
    Flow {
        Layout.fillWidth: true
        visible: page.dndChoicesOpen && page.backend.dnd.available
        spacing: page.metrics.px(8)

        Repeater {
            model: [
                { "id": "hour", "text": i18nc("@action:button do not disturb", "For 1 hour") },
                { "id": "tomorrow", "text": i18nc("@action:button do not disturb", "Until tomorrow") },
                { "id": "off", "text": page.backend.dnd.active ? i18nc("@action:button do not disturb", "Turn off")
                                                              : i18nc("@action:button do not disturb", "Until turned off") }
            ]
            delegate: TextButton {
                required property var modelData
                objectName: "dnd-" + modelData.id
                pal: page.pal
                metrics: page.metrics
                radius: height / 2
                implicitHeight: page.pal.touch ? 44 : page.metrics.px(30)
                fontSize: 12.5
                text: modelData.text
                onClicked: {
                    if (modelData.id === "hour") {
                        page.backend.dnd.forHour();
                    } else if (modelData.id === "tomorrow") {
                        page.backend.dnd.untilTomorrow();
                    } else {
                        page.backend.dnd.toggle();
                    }
                    page.dndChoicesOpen = false;
                }
            }
        }
    }

    // Charge limit choices.
    Flow {
        Layout.fillWidth: true
        visible: page.chargeChoicesOpen && page.backend.charge.present && !page.backend.charge.managed
        spacing: page.metrics.px(8)

        Repeater {
            model: {
                const items = [
                    { "id": "80", "text": i18nc("@action:button charge limit", "Stop at 80 %") },
                    { "id": "90", "text": i18nc("@action:button charge limit", "Stop at 90 %") }
                ];
                if (page.backend.charge.limited && page.backend.battery.pluggedIn) {
                    items.push({ "id": "once", "text": i18nc("@action:button charge limit", "Charge to 100 % once") });
                }
                items.push({ "id": "off", "text": i18nc("@action:button charge limit", "No limit") });
                items.push({ "id": "settings", "text": i18nc("@action:button", "Battery settings…") });
                return items;
            }
            delegate: TextButton {
                required property var modelData
                objectName: "charge-" + modelData.id
                pal: page.pal
                metrics: page.metrics
                radius: height / 2
                implicitHeight: page.pal.touch ? 44 : page.metrics.px(30)
                fontSize: 12.5
                text: modelData.text
                onClicked: {
                    switch (modelData.id) {
                    case "80":
                    case "90":
                        page.backend.charge.setLimit(Number(modelData.id));
                        break;
                    case "once":
                        page.backend.charge.fullChargeOnce();
                        break;
                    case "off":
                        page.backend.charge.setLimit(100);
                        break;
                    default:
                        page.backend.charge.openSettings();
                        break;
                    }
                    page.chargeChoicesOpen = false;
                }
            }
        }
    }

    // Phone and clipboard, when the top bar has no room for their buttons (52 px rows).
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.backend.barCompact && (page.backend.phone.shown || page.backend.showClipboard)
        spacing: page.metrics.px(4)

        ListRow {
            objectName: "sheet-clipboard"
            Layout.fillWidth: true
            implicitHeight: page.metrics.px(52)
            visible: page.backend.showClipboard
            pal: page.pal
            metrics: page.metrics
            iconPath: Icons.clipboard
            text: i18nc("@action:button", "Clipboard")
            trailingPath: Icons.chevronRight
            onClicked: page.backend.session.openClipboard()
        }
        ListRow {
            objectName: "sheet-phone"
            Layout.fillWidth: true
            implicitHeight: page.metrics.px(52)
            visible: page.backend.phone.shown
            pal: page.pal
            metrics: page.metrics
            iconPath: Icons.phone
            text: page.backend.phone.deviceName || i18nc("@action:button", "Phone")
            status: i18nc("@info:status", "Connected")
            trailingPath: Icons.chevronRight
            onClicked: page.backend.phone.open()
        }
    }

    // ---------------------------------------------------------------- media card
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(page.tablet ? 72 : 64, mediaText.implicitHeight + page.metrics.px(20))
        visible: page.backend.media.available
        radius: 16
        color: page.pal.overlay(0.06)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: page.metrics.px(12)

            Item {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44

                Kirigami.ShadowedImage {
                    id: albumArt
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: page.backend.media.artUrl
                    sourceSize.width: 88
                    sourceSize.height: 88
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    radius: 10
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: !albumArt.visible
                    source: page.backend.media.iconName || "emblem-music-symbolic"
                    fallback: "emblem-music-symbolic"
                }
                Accessible.role: Accessible.Button
                Accessible.name: i18nc("@action:button", "Show the player")
                Accessible.onPressAction: page.backend.media.raise()
                TapHandler {
                    enabled: page.backend.media.canRaise
                    onTapped: page.backend.media.raise()
                }
            }

            ColumnLayout {
                id: mediaText
                Layout.fillWidth: true
                spacing: page.metrics.px(2)
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    metrics: page.metrics
                    text: page.backend.media.title
                    font.weight: Font.ExtraBold
                }
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    metrics: page.metrics
                    text: page.backend.media.subtitle
                    visible: text.length > 0
                    color: page.pal.secondary
                    px: 11.5
                }
            }

            IconButton {
                pal: page.pal
                size: 32
                iconSize: 16
                fill: "transparent"
                iconPath: Icons.previous
                enabled: page.backend.media.canPrevious
                text: i18nc("@action:button", "Previous track")
                onClicked: page.backend.media.previous()
            }
            IconButton {
                pal: page.pal
                size: 36
                iconSize: 16
                fill: page.pal.playFill
                hoverFill: Qt.lighter(page.pal.playFill, page.pal.dark ? 1.08 : 1.6)
                pressFill: Qt.darker(page.pal.playFill, 1.1)
                iconColor: page.pal.playGlyph
                iconFillPath: page.backend.media.playing ? Icons.pauseFill : Icons.play
                enabled: page.backend.media.canPlayPause
                text: page.backend.media.playing ? i18nc("@action:button", "Pause") : i18nc("@action:button", "Play")
                onClicked: page.backend.media.playPause()
            }
            IconButton {
                pal: page.pal
                size: 32
                iconSize: 16
                fill: "transparent"
                iconPath: Icons.next
                enabled: page.backend.media.canNext
                text: i18nc("@action:button", "Next track")
                onClicked: page.backend.media.next()
            }
        }
    }
}
