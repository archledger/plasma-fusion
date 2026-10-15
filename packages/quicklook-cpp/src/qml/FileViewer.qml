// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Any other file: its thumbnail (what Dolphin shows for it, from KIO's thumbnailers: a document's
// first page, an archive, a font...) or its icon, and its name and type. A file that is gone says so.
ColumnLayout {
    id: viewer
    objectName: "fileViewer"

    // QuickLookItem (quicklook.h).
    required property var item
    readonly property bool hasThumbnail: viewer.item.thumbnail.toString().length > 0
    readonly property bool ready: viewer.item.kind === "missing" || viewer.item.thumbnailDone
    readonly property var report: ({thumbnail: hasThumbnail, icon: item.iconName})
    readonly property string extra: ""

    Item {
        Layout.fillHeight: true
    }
    Image {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: viewer.width - Kirigami.Units.gridUnit * 4
        Layout.maximumHeight: viewer.height - Kirigami.Units.gridUnit * 8
        visible: viewer.hasThumbnail
        source: viewer.item.thumbnail
        fillMode: Image.PreserveAspectFit
    }
    Kirigami.Icon {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Kirigami.Units.iconSizes.enormous * 1.5
        Layout.preferredHeight: Layout.preferredWidth
        visible: !viewer.hasThumbnail
        source: viewer.item.iconName
    }
    Kirigami.Heading {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: viewer.width - Kirigami.Units.gridUnit * 2
        level: 2
        text: viewer.item.name
        elide: Text.ElideMiddle
    }
    Kirigami.Heading {
        Layout.alignment: Qt.AlignHCenter
        level: 4
        opacity: 0.7
        text: viewer.item.kind === "missing" ? i18nc("@info", "This file is no longer there") : viewer.item.typeName
    }
    Item {
        Layout.fillHeight: true
    }
}
