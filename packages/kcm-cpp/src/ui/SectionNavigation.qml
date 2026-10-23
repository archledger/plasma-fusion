/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC2

Item {
    id: root

    required property var labels
    required property string accessibleName
    property int currentIndex: 0
    property real minimumTabsWidth: 0
    readonly property bool compact: width < minimumTabsWidth
    signal selectionRequested(int index)

    implicitHeight: compact ? sectionCombo.implicitHeight : sectionTabs.implicitHeight

    // Use each tab's natural width; a long label must not reserve its width for every tab.
    function measureTabs() {
        let total = 0;
        for (let i = 0; i < tabItems.count; ++i) {
            const item = tabItems.itemAt(i);
            if (item) total += item.implicitWidth;
        }
        minimumTabsWidth = total
            + sectionTabs.spacing * Math.max(0, tabItems.count - 1)
            + sectionTabs.leftPadding + sectionTabs.rightPadding;
    }

    function requestSelection(index) {
        if (index >= 0 && index < labels.length && index !== currentIndex) {
            selectionRequested(index);
        }
    }

    function syncSelection() {
        if (sectionTabs && sectionTabs.currentIndex !== currentIndex) sectionTabs.setCurrentIndex(currentIndex);
        if (sectionCombo && sectionCombo.currentIndex !== currentIndex) sectionCombo.currentIndex = currentIndex;
    }

    function containsFocus(item) {
        let focus = root.Window.window ? root.Window.window.activeFocusItem : null;
        while (focus) {
            if (focus === item) return true;
            focus = focus.parent;
        }
        return false;
    }

    function focusCurrent() {
        if (compact) sectionCombo.forceActiveFocus();
        else {
            const tab = sectionTabs.itemAt(currentIndex);
            if (tab) tab.forceActiveFocus();
        }
    }

    function updateMode() {
        if (!sectionTabs || !sectionCombo) return;
        const moveFocus = containsFocus(root);
        sectionTabs.visible = !compact;
        sectionTabs.enabled = !compact;
        sectionCombo.visible = compact;
        sectionCombo.enabled = compact;
        if (moveFocus) focusCurrent();
    }

    onCurrentIndexChanged: syncSelection()
    onCompactChanged: updateMode()

    QQC2.TabBar {
        id: sectionTabs
        objectName: "sectionTabs"
        anchors.fill: parent
        visible: false
        enabled: false
        Accessible.name: root.accessibleName
        onCurrentIndexChanged: if (visible) root.requestSelection(currentIndex)

        Repeater {
            id: tabItems
            model: root.labels
            onItemAdded: {
                Qt.callLater(root.measureTabs);
                Qt.callLater(root.syncSelection);
            }
            onItemRemoved: Qt.callLater(root.measureTabs)
            delegate: QQC2.TabButton {
                required property string modelData
                required property int index
                objectName: "sectionTab" + index
                width: implicitWidth
                text: modelData
                Accessible.name: text
                Accessible.selected: index === root.currentIndex
                Accessible.onPressAction: if (enabled && visible) root.requestSelection(index)
                onClicked: root.requestSelection(index)
                onImplicitWidthChanged: Qt.callLater(root.measureTabs)
            }
        }
    }

    QQC2.ComboBox {
        id: sectionCombo
        objectName: "sectionCombo"
        anchors.fill: parent
        visible: false
        enabled: false
        model: root.labels
        Accessible.name: root.accessibleName
        onActivated: index => root.requestSelection(index)
        // Qt's ComboBox handles keys for its non-focusable delegates, not KDE's Menu popup.
        popup.focus: false
    }

    Component.onCompleted: {
        syncSelection();
        updateMode();
        Qt.callLater(measureTabs);
    }
}
