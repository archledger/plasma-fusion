// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    property alias cfg_showKeyboardLayout: keyboardBox.checked
    property alias cfg_keyboardLayoutAlways: keyboardAlwaysBox.checked
    property alias cfg_showKdeConnect: phoneBox.checked
    property alias cfg_showClipboard: clipboardBox.checked
    property alias cfg_showBatteryPercent: batteryBox.checked
    property alias cfg_showNotifications: notificationsBox.checked
    property alias cfg_popupOnNewDevice: newDeviceBox.checked
    property alias cfg_popupGap: gapSpin.value
    property alias cfg_popupScreenMargin: marginSpin.value
    property alias cfg_lightLookAndFeel: lightField.text
    property alias cfg_darkLookAndFeel: darkField.text
    // Every key of main.xml needs a cfg_ property here, and its default a cfg_<key>Default, or the
    // settings dialog warns ("Setting initial properties failed").
    property string cfg_startPage: "main"
    property string cfg_keyboardPolicy: "tablet"
    property string cfg_tabletNotifications: "apart"
    // Keys this page does not edit. The dialog writes every declared key back on Apply, so they are
    // refreshed from the live configuration just before saving (nothing written meanwhile is lost).
    property string cfg_openRequest: ""
    property string cfg_debugAction: ""
    property string cfg_airplaneRestore: ""
    property string cfg_glass: "full"
    property var cfg_tileOrder: []
    property var cfg_hiddenTiles: []
    property real cfg_sharedRevision: 0

    property bool cfg_showKeyboardLayoutDefault
    property bool cfg_keyboardLayoutAlwaysDefault
    property bool cfg_showKdeConnectDefault
    property bool cfg_showClipboardDefault
    property bool cfg_showBatteryPercentDefault
    property bool cfg_popupOnNewDeviceDefault
    property bool cfg_showNotificationsDefault
    property int cfg_popupGapDefault
    property int cfg_popupScreenMarginDefault
    property string cfg_startPageDefault
    property string cfg_keyboardPolicyDefault
    property string cfg_openRequestDefault
    property string cfg_tabletNotificationsDefault
    property string cfg_airplaneRestoreDefault
    property string cfg_debugActionDefault
    property string cfg_lightLookAndFeelDefault
    property string cfg_darkLookAndFeelDefault
    property string cfg_glassDefault
    property var cfg_tileOrderDefault
    property var cfg_hiddenTilesDefault
    property real cfg_sharedRevisionDefault

    function saveConfig() {
        const config = Plasmoid.configuration;
        // requests other shell parts write through desktop scripting
        cfg_openRequest = config.openRequest;
        cfg_debugAction = config.debugAction;
        // the radios to turn back on after airplane mode
        cfg_airplaneRestore = config.airplaneRestore;
        // written by the settings module and the power service
        cfg_glass = config.glass;
        // the tiles' order and the hidden tiles (the sheet's edit mode)
        cfg_tileOrder = config.tileOrder;
        cfg_hiddenTiles = config.hiddenTiles;
        stampSharedRevision();
    }
    // The shared settings' revision is set by the page, not refreshed: Apply writes the shared
    // settings, so they count as changed now. The dialog writes it after them (main.xml order), and
    // the old revision written back over the widget's own stamp would make the settings just
    // applied lose to an older set at the next start (main.qml, code/shared.js).
    function stampSharedRevision() {
        cfg_sharedRevision = Date.now();
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: keyboardBox
            Kirigami.FormData.label: i18nc("@title:group", "Top bar:")
            text: i18nc("@option:check", "Keyboard layout badge")
        }
        QQC2.CheckBox {
            id: keyboardAlwaysBox
            enabled: keyboardBox.checked
            text: i18nc("@option:check", "Also when only one layout is configured")
        }
        QQC2.CheckBox {
            id: phoneBox
            text: i18nc("@option:check", "Phone button while a KDE Connect device is connected")
        }
        QQC2.CheckBox {
            id: clipboardBox
            text: i18nc("@option:check", "Clipboard button")
        }
        QQC2.CheckBox {
            id: batteryBox
            text: i18nc("@option:check", "Battery percentage in the status pill")
        }
        QQC2.CheckBox {
            id: notificationsBox
            text: i18nc("@option:check", "Notification bell and notification list")
        }
        QQC2.CheckBox {
            id: newDeviceBox
            text: i18nc("@option:check", "Open Disks & Devices when a device is connected")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: gapSpin
            Kirigami.FormData.label: i18nc("@label:spinbox", "Gap below the top bar:")
            from: 0
            to: 48
        }
        QQC2.SpinBox {
            id: marginSpin
            Kirigami.FormData.label: i18nc("@label:spinbox", "Distance from the screen edge:")
            from: 0
            to: 96
        }
        QQC2.ComboBox {
            id: startPageBox
            Kirigami.FormData.label: i18nc("@label:listbox", "Page shown when opened:")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "main", text: i18nc("@item:inlistbox", "Quick settings") },
                { value: "wifi", text: i18nc("@item:inlistbox", "Wi‑Fi networks") },
                { value: "bluetooth", text: i18nc("@item:inlistbox", "Bluetooth devices") },
                { value: "audio", text: i18nc("@item:inlistbox", "Sound output") }
            ]
            // The index from the model itself: indexOfValue() is -1 until the model is read.
            Component.onCompleted: currentIndex = Math.max(0, model.findIndex(entry => entry.value === page.cfg_startPage))
            onActivated: page.cfg_startPage = currentValue
        }
        QQC2.ComboBox {
            id: keyboardPolicyBox
            Kirigami.FormData.label: i18nc("@label:listbox", "On-screen keyboard:")
            Accessible.name: i18nc("@label:listbox", "On-screen keyboard")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "tablet", text: i18nc("@item:inlistbox on-screen keyboard", "In tablet mode") },
                { value: "touch", text: i18nc("@item:inlistbox on-screen keyboard", "On every touch") },
                { value: "never", text: i18nc("@item:inlistbox on-screen keyboard", "Never") }
            ]
            Component.onCompleted: currentIndex = Math.max(0, model.findIndex(entry => entry.value === page.cfg_keyboardPolicy))
            onActivated: page.cfg_keyboardPolicy = currentValue
        }
        QQC2.ComboBox {
            id: tabletNotificationsBox
            Kirigami.FormData.label: i18nc("@label:listbox", "Notifications in tablet mode:")
            Accessible.name: i18nc("@label:listbox", "Notifications in tablet mode")
            textRole: "text"
            valueRole: "value"
            model: [
                { value: "apart", text: i18nc("@item:inlistbox tablet notifications", "Own sheet (bell and clock pull-down)") },
                { value: "together", text: i18nc("@item:inlistbox tablet notifications", "With the quick settings") }
            ]
            Component.onCompleted: currentIndex = Math.max(0, model.findIndex(entry => entry.value === page.cfg_tabletNotifications))
            onActivated: page.cfg_tabletNotifications = currentValue
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.TextField {
            id: lightField
            Kirigami.FormData.label: i18nc("@label:textbox", "Global Theme for light style:")
            placeholderText: "org.plasmafusion.light.desktop"
        }
        QQC2.TextField {
            id: darkField
            Kirigami.FormData.label: i18nc("@label:textbox", "Global Theme for dark style:")
            placeholderText: "org.plasmafusion.dark.desktop"
        }
    }
}
