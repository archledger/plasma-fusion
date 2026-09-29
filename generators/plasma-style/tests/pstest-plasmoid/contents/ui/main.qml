// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Test-only widget for Plasma style screenshots (not part of the build output).
// mode=popup: a pop-up full of Plasma Components 3 controls; mode=tip / richtip: activation
// (its global shortcut) shows a plain or a rich Plasma tooltip instead.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    readonly property string mode: Plasmoid.configuration.mode
    toolTipMainText: ""
    toolTipSubText: ""
    activationTogglesExpanded: mode === "popup"
    Plasmoid.icon: mode === "richtip" ? "battery-080" : (mode === "tip" ? "internet-web-browser" : "preferences-system")

    // tooltip modes: activation (global shortcut) shows the tooltip instead of a popup
    onExpandedChanged: {
        if (root.expanded && root.mode !== "popup") {
            root.expanded = false;
            tipTimer.start();
        }
    }
    Timer { id: tipTimer; interval: 300; onTriggered: if (root.tipArea) root.tipArea.showToolTip() }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon { anchors.fill: parent; source: Plasmoid.icon }
        PlasmaCore.ToolTipArea {
            id: tta
            anchors.fill: parent
            mainText: root.mode === "richtip" ? "Battery 82%" : "Browser"
            subText: root.mode === "richtip" ? "About 4 h 10 min left · Balanced mode" : ""
            icon: root.mode === "richtip" ? "battery-080" : ""
            Component.onCompleted: root.tipArea = tta
        }
    }

    fullRepresentation: root.mode === "popup" ? fullComp : tinyComp
    Component { id: tinyComp; PC3.Label { text: "…" } }
    property Item tipArea: null
    Component {
        id: fullComp
        PlasmaExtras.Representation {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            Layout.preferredHeight: Kirigami.Units.gridUnit * 25
            collapseMarginsHint: true
            header: PlasmaExtras.PlasmoidHeading {
                contentItem: RowLayout {
                    PC3.ToolButton { icon.name: "go-previous" }
                    PlasmaExtras.Heading { text: "Wi-Fi"; level: 1; Layout.fillWidth: true }
                    PC3.Switch { checked: true }
                }
            }
            footer: PlasmaExtras.PlasmoidHeading {
                position: PC3.ToolBar.Footer
                contentItem: RowLayout {
                    PC3.Label { text: "Hidden network…"; Layout.fillWidth: true; color: Kirigami.Theme.linkColor }
                    PC3.Button { icon.name: "configure"; text: "Network settings" }
                }
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing * 2
                RowLayout {
                    PC3.Button { text: "Open"; highlighted: true }
                    PC3.Button { text: "Show in folder" }
                    PC3.Button { id: focused; text: "Focused" }
                    PC3.Button { text: "On"; checkable: true; checked: true
                        PC3.ToolTip { visible: true; text: "Pin to dock" } }
                }
                RowLayout {
                    PC3.ToolButton { icon.name: "view-refresh"; text: "Refresh" }
                    PC3.ToolButton { icon.name: "media-playback-pause"; checkable: true; checked: true }
                    PC3.ComboBox { model: ["Balanced", "Power save", "Performance"] }
                }
                PC3.TextField { Layout.fillWidth: true; placeholderText: "Search" }
                RowLayout {
                    PC3.CheckBox { text: "Checked"; checked: true }
                    PC3.CheckBox { text: "Off" }
                    PC3.RadioButton { text: "On"; checked: true }
                    PC3.RadioButton { text: "Off" }
                }
                RowLayout {
                    PC3.Switch { text: "On"; checked: true }
                    PC3.Switch { text: "Off" }
                    PC3.BusyIndicator { running: true; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                    PC3.SpinBox { value: 12 }
                }
                PC3.Slider { Layout.fillWidth: true; value: 0.6 }
                PC3.ProgressBar { Layout.fillWidth: true; value: 0.64 }
                PC3.TabBar { Layout.fillWidth: true
                    PC3.TabButton { text: "General" } PC3.TabButton { text: "Display" } PC3.TabButton { text: "Advanced" } }
                PC3.ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    ListView {
                        model: ["Office-Guest", "Café Libre", "Studio 5G", "Printer-Direct", "Lab", "Guest-2", "Garden"]
                        currentIndex: 0
                        highlight: PlasmaExtras.Highlight {}
                        delegate: PC3.ItemDelegate { width: ListView.view.width; text: modelData; icon.name: "network-wireless" }
                    }
                }
            }
            Component.onCompleted: focused.forceActiveFocus(Qt.TabFocusReason)
        }
    }
}
