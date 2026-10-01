// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.plasmoid

import "services"

// The pen settings page inside the pen menu (PEN.md 3.4). Each row writes exactly the keys System
// Settings' Drawing Tablet page writes: kcminputrc through kwriteconfig6 --notify (KWin reloads
// button rebinds and [Tablet] on the notify) and the device's pressureCurve, outputName and
// mapToWorkspace through KWin's D-Bus properties (KWin stores those itself). Values are read when
// the page opens. "Touch while the pen is near" is not offered until hand check V4.
Column {
    id: page

    required property FusionMetrics metrics
    required property FusionAccent tint
    required property color ink
    required property PenDevice device
    required property Exec exec
    // The widget's global shortcut as portable text ("Meta+Shift+W"), empty when it has none.
    property string shortcutText: ""

    signal back()
    signal closeRequested()
    // A row opened or closed its choices (the menu logs the new positions).
    signal rowsChanged()

    // Global positions of the rows, choices and pressure buttons (for the open log line).
    function describe(): string {
        const out = [];
        const walk = item => {
            for (let i = 0; i < item.children.length; ++i) {
                const c = item.children[i];
                if (c.objectName && /^(row|choice|seg)-/.test(c.objectName) && c.visible) {
                    const p = c.mapToGlobal(0, 0);
                    out.push(c.objectName + "@" + Math.round(p.x) + "," + Math.round(p.y) + ":" + Math.round(c.width) + "x" + Math.round(c.height));
                }
                walk(c);
            }
        };
        walk(page);
        return out.join(" ");
    }

    // The ThinkPad's pen when there is no device to ask (test sessions).
    readonly property string penName: device.name.length > 0 ? device.name : "Wacom HID 534D Pen"
    property string clickValue: ""
    property string syncValue: ""
    // plasmafusionrc [Pen] TabletPen: finger (default) or pen (TABLET2 PEN-2)
    property string tabletPenValue: "finger"

    readonly property var curves: ({ "soft": "0,0.4;0.6,1;", "linear": "0,0;1,1;", "firm": "0.4,0;1,0.6;" })
    readonly property string curveId: {
        const c = device.pressureCurve;
        for (const k in curves) {
            if (curves[k] === c) {
                return k;
            }
        }
        return c.length === 0 ? "linear" : "";
    }
    readonly property string screenId: device.mapToWorkspace ? "all" : device.outputName.length === 0 ? "follow" : "builtin"
    readonly property string clickId: {
        if (clickValue === "") {
            return "apps";
        }
        if (clickValue === "MouseButton,273") {
            return "right";
        }
        if (clickValue === "MouseButton,274") {
            return "middle";
        }
        if (clickValue.startsWith("Key,")) {
            return "menu";
        }
        return "";
    }

    function q(text: string): string {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }
    readonly property string rebindGroup: "--group ButtonRebinds --group TabletTool --group " + q(penName)
    readonly property string readClick: "kreadconfig6 --file kcminputrc " + rebindGroup + " --key 331"
    readonly property string readSync: "kreadconfig6 --file kcminputrc --group Tablet --key SyncWithMouse"
    readonly property string readTabletPen: "kreadconfig6 --file plasmafusionrc --group Pen --key TabletPen --default finger"

    function reload(): void {
        exec.run(readClick);
        exec.run(readSync);
        exec.run(readTabletPen);
        device.refresh();
    }
    Connections {
        target: page.exec
        function onFinished(command, exitCode, stdout) {
            if (command.endsWith(page.readClick)) {
                page.clickValue = stdout.trim();
            } else if (command.endsWith(page.readSync)) {
                page.syncValue = stdout.trim();
            } else if (command.endsWith(page.readTabletPen)) {
                page.tabletPenValue = stdout.trim() === "pen" ? "pen" : "finger";
            }
        }
    }

    function setClick(id: string): void {
        let cmd = "kwriteconfig6 --notify --file kcminputrc " + rebindGroup + " --key 331 ";
        if (id === "right") {
            cmd += q("MouseButton,273");
        } else if (id === "middle") {
            cmd += q("MouseButton,274");
        } else if (id === "menu" && shortcutText.length > 0) {
            cmd += q("Key," + shortcutText);
        } else if (id === "apps") {
            cmd += "--delete";
        } else {
            return;
        }
        exec.run(cmd + "; " + readClick);
    }
    // The navigation effect follows it live (KConfigWatcher).
    function setTabletPen(id: string): void {
        exec.run("kwriteconfig6 --notify --file plasmafusionrc --group Pen --key TabletPen " + (id === "pen" ? "pen" : "finger") + "; " + readTabletPen);
    }
    function setSync(on: bool): void {
        exec.run("kwriteconfig6 --notify --file kcminputrc --group Tablet --key SyncWithMouse " + (on ? "true" : "false") + "; " + readSync);
    }
    // The built-in panel's output: the first screen named eDP, LVDS or DSI (KWin names DRM
    // outputs by connector).
    function internalOutput(): string {
        const screens = Qt.application.screens;
        for (let i = 0; i < screens.length; ++i) {
            if (/^(eDP|LVDS|DSI)/.test(screens[i].name)) {
                return screens[i].name;
            }
        }
        return "";
    }
    function setScreen(id: string): void {
        if (id === "all") {
            device.write("mapToWorkspace", true);
            return;
        }
        device.write("mapToWorkspace", false);
        if (id === "builtin") {
            const out = internalOutput();
            if (out.length > 0) {
                device.write("outputName", out);
            }
        } else {
            device.write("outputName", "");
            // KWin keeps the stored OutputUuid otherwise, and the pen returns to that screen at
            // the next login (PEN.md 3.4).
            if (device.vendor > 0) {
                exec.run("kwriteconfig6 --notify --file kcminputrc --group Libinput --group " + device.vendor + " --group "
                         + device.product + " --group " + q(penName) + " --key OutputUuid --delete");
            }
        }
    }

    spacing: metrics.px(4)

    // Header: back button and title.
    Item {
        width: page.width
        height: page.metrics.px(44)

        T.AbstractButton {
            id: backButton
            width: page.metrics.px(44)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            text: i18nc("@action:button back to the pen menu", "Back")
            Accessible.name: text
            onClicked: page.back()
            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            background: Rectangle {
                anchors.centerIn: parent
                width: page.metrics.px(34)
                height: width
                radius: width / 2
                color: Qt.rgba(page.ink.r, page.ink.g, page.ink.b, backButton.down ? 0.16 : backButton.hovered ? 0.12 : 0.08)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: page.tint.focusRing
                    visible: backButton.visualFocus
                }
            }
            contentItem: Item {
                LineIcon {
                    anchors.centerIn: parent
                    size: page.metrics.px(16)
                    path: "M15 6l-6 6 6 6"
                    color: page.ink
                }
            }
        }
        Text {
            anchors.left: backButton.right
            anchors.leftMargin: page.metrics.px(8)
            anchors.verticalCenter: parent.verticalCenter
            text: i18nc("@title", "Pen settings")
            color: page.ink
            font.pixelSize: page.metrics.font(17)
            font.weight: Font.ExtraBold
            textFormat: Text.PlainText
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
    }

    component SectionTitle: Text {
        width: page.width
        topPadding: page.metrics.px(10)
        bottomPadding: page.metrics.px(2)
        leftPadding: page.metrics.px(8)
        color: page.ink
        opacity: 0.6
        font.pixelSize: page.metrics.font(11.5)
        font.weight: Font.ExtraBold
        font.capitalization: Font.AllUppercase
        textFormat: Text.PlainText
    }

    SectionTitle { text: i18nc("@title:group", "Buttons") }
    SettingRow {
        metrics: page.metrics
        tint: page.tint
        ink: page.ink
        label: i18nc("@label pen button", "Click button")
        key: "click"
        onExpandedChanged: Qt.callLater(page.rowsChanged)
        hint: i18nc("@info", "The button on the side of the pen")
        current: page.clickId
        choices: {
            const list = [{ "id": "right", "text": i18nc("@item pen button", "Right click") }];
            if (page.shortcutText.length > 0) {
                list.push({ "id": "menu", "text": i18nc("@item pen button", "Open pen menu") });
            }
            list.push({ "id": "middle", "text": i18nc("@item pen button", "Middle click") });
            list.push({ "id": "apps", "text": i18nc("@item pen button", "Let apps decide") });
            return list;
        }
        value: {
            for (const c of choices) {
                if (c.id === current) {
                    return c.text;
                }
            }
            return page.clickValue;
        }
        onPicked: id => page.setClick(id)
    }
    SettingRow {
        metrics: page.metrics
        tint: page.tint
        ink: page.ink
        label: i18nc("@label", "Eraser")
        key: "eraser"
        onExpandedChanged: Qt.callLater(page.rowsChanged)
        hint: i18nc("@info", "Erases in drawing apps")
        enabled: false
    }

    // TABLET2 PEN-2: in tablet posture the pen scrolls and taps like a finger (iPadOS, Android,
    // Windows); drawing apps keep the pen; "like a mouse" keeps drags selecting, as on the laptop.
    SettingRow {
        metrics: page.metrics
        tint: page.tint
        ink: page.ink
        label: i18nc("@label how the pen acts in tablet posture", "In tablet posture")
        key: "tabletpen"
        onExpandedChanged: Qt.callLater(page.rowsChanged)
        hint: i18nc("@info", "Drawing apps always get the pen")
        current: page.tabletPenValue
        choices: [
            { "id": "finger", "text": i18nc("@item the pen in tablet posture", "Like a finger: drags scroll") },
            { "id": "pen", "text": i18nc("@item the pen in tablet posture", "Like a mouse: drags select") }
        ]
        value: page.tabletPenValue === "pen" ? choices[1].text : choices[0].text
        onPicked: id => page.setTabletPen(id)
    }

    SectionTitle { text: i18nc("@title:group", "Pressure") }
    Row {
        id: pressure
        width: page.width
        spacing: page.metrics.px(6)
        Repeater {
            model: [
                { "id": "soft", "text": i18nc("@option pressure curve", "Soft") },
                { "id": "linear", "text": i18nc("@option pressure curve", "Linear") },
                { "id": "firm", "text": i18nc("@option pressure curve", "Firm") }
            ]
            T.AbstractButton {
                id: seg
                required property var modelData
                objectName: "seg-" + modelData.id
                readonly property bool selected: page.curveId === modelData.id
                width: (pressure.width - 2 * pressure.spacing) / 3
                height: page.metrics.px(44)
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                checkable: false
                text: modelData.text
                Accessible.name: text
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                onClicked: page.device.write("pressureCurve", page.curves[modelData.id])
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                background: Rectangle {
                    radius: page.metrics.px(12)
                    color: seg.selected ? page.tint.fill : Qt.rgba(page.ink.r, page.ink.g, page.ink.b, seg.down ? 0.16 : seg.hovered ? 0.12 : 0.08)
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: parent.radius + 3
                        color: "transparent"
                        border.width: 2
                        border.color: page.tint.focusRing
                        visible: seg.visualFocus
                    }
                }
                contentItem: Text {
                    text: seg.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: seg.selected ? page.tint.fillText : page.ink
                    font.pixelSize: page.metrics.font(13)
                    font.weight: Font.Bold
                    textFormat: Text.PlainText
                }
            }
        }
    }

    SectionTitle { text: i18nc("@title:group", "Screen") }
    SettingRow {
        metrics: page.metrics
        tint: page.tint
        ink: page.ink
        label: i18nc("@label", "Pen works on")
        key: "screen"
        onExpandedChanged: Qt.callLater(page.rowsChanged)
        current: page.screenId
        choices: [
            { "id": "builtin", "text": i18nc("@item pen output", "Built-in screen") },
            { "id": "follow", "text": i18nc("@item pen output", "Follow the active screen") },
            { "id": "all", "text": i18nc("@item pen output", "All screens") }
        ]
        value: {
            for (const c of choices) {
                if (c.id === current) {
                    return c.text;
                }
            }
            return "";
        }
        onPicked: id => page.setScreen(id)
    }
    SettingRow {
        metrics: page.metrics
        tint: page.tint
        ink: page.ink
        label: i18nc("@label", "One pointer for pen and mouse")
        key: "sync"
        onExpandedChanged: Qt.callLater(page.rowsChanged)
        hint: i18nc("@info", "The mouse continues where the pen was")
        current: page.syncValue === "true" ? "on" : page.syncValue === "false" ? "off" : ""
        choices: [
            { "id": "on", "text": i18nc("@item", "On") },
            { "id": "off", "text": i18nc("@item", "Off") }
        ]
        value: current === "on" ? i18nc("@item", "On") : current === "off" ? i18nc("@item", "Off") : i18nc("@item", "System default")
        onPicked: id => page.setSync(id === "on")
    }

    SectionTitle { text: i18nc("@title:group", "Pen menu") }
    SettingRow {
        metrics: page.metrics
        tint: page.tint
        ink: page.ink
        label: i18nc("@label", "Show pen button")
        key: "show"
        onExpandedChanged: Qt.callLater(page.rowsChanged)
        current: String(Plasmoid.configuration.showButton)
        choices: [
            { "id": "tablet", "text": i18nc("@item", "In tablet mode") },
            { "id": "always", "text": i18nc("@item", "Always") },
            { "id": "never", "text": i18nc("@item", "Never") }
        ]
        value: {
            for (const c of choices) {
                if (c.id === current) {
                    return c.text;
                }
            }
            return "";
        }
        onPicked: id => {
            Plasmoid.configuration.showButton = id;
        }
    }
    SettingRow {
        metrics: page.metrics
        tint: page.tint
        ink: page.ink
        label: i18nc("@action", "Test your pen")
        key: "test"
        onExpandedChanged: Qt.callLater(page.rowsChanged)
        hint: i18nc("@info", "Pressure, tilt and buttons")
        onActivated: {
            KCMUtils.KCMLauncher.openSystemSettings("kcm_tablet");
            page.closeRequested();
        }
    }
    SettingRow {
        metrics: page.metrics
        tint: page.tint
        ink: page.ink
        label: i18nc("@action", "Advanced (Drawing Tablet)")
        key: "advanced"
        onExpandedChanged: Qt.callLater(page.rowsChanged)
        onActivated: {
            KCMUtils.KCMLauncher.openSystemSettings("kcm_tablet");
            page.closeRequested();
        }
    }
}
