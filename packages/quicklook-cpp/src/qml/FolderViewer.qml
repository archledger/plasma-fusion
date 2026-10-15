// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A folder: its icon and name, and below (QuickLookItem::details) how many items it has and their
// size in all, which KIO counts while it is shown.
ColumnLayout {
    id: viewer
    objectName: "folderViewer"

    // QuickLookItem (quicklook.h).
    required property var item
    readonly property bool ready: true
    readonly property var report: ({details: item.details})
    readonly property string extra: ""

    Item {
        Layout.fillHeight: true
    }
    Kirigami.Icon {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Kirigami.Units.iconSizes.enormous * 1.5
        Layout.preferredHeight: Layout.preferredWidth
        source: viewer.item.iconName
    }
    Kirigami.Heading {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: viewer.width - Kirigami.Units.gridUnit * 2
        level: 2
        text: viewer.item.name
        elide: Text.ElideMiddle
    }
    Item {
        Layout.fillHeight: true
    }
}
