// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

import "components"
import "components/Icons.js" as Icons
import "../code/clipboard.js" as Clip

// One entry of the clipboard sheet (ClipboardPage.qml): text in up to two lines, an image as a
// thumbnail, copied files with the first one's preview and their names. A tap or click chooses it;
// the star and the "⋯" button (shown on the current row, on hover and always in touch mode) star
// it and open its actions: Star, Edit, QR code, Klipper's actions and Remove, as the stock
// Clipboard widget's row buttons.
ColumnLayout {
    id: entry

    required property var model
    required property int index
    required property FusionPalette pal
    required property FusionMetrics metrics
    // The list's current row, and whether the list has the keyboard focus (the ring shows then).
    property bool current: false
    property bool keyboardFocus: false
    property bool expanded: false
    // The action button the arrow keys are on while the actions are open.
    property int actionIndex: 0

    signal chosen()
    signal hovered()
    signal starToggled()
    signal expandToggled()
    signal editRequested()
    signal qrRequested()
    signal actionsRequested()
    signal removeRequested()

    readonly property int type: Number(model.type)
    readonly property bool starred: !!model.starred
    readonly property string display: String(model.display || "")
    readonly property var fileNames: type === Clip.URL ? Clip.fileNames(display) : []
    readonly property size imageSize: model.imageSize || Qt.size(0, 0)
    // What the row says, also its accessible name.
    readonly property string label: {
        if (type === Clip.IMAGE) {
            return imageSize.width > 0
                ? i18nc("@item clipboard entry, %1 × %2 pixels", "Image, %1 × %2", imageSize.width, imageSize.height)
                : i18nc("@item clipboard entry", "Image");
        }
        if (type === Clip.URL && fileNames.length > 0) {
            return fileNames.length === 1 ? fileNames[0]
                : i18ncp("@item clipboard entry: copied files, %2 the first file's name",
                         "%2 and %1 more", "%2 and %1 more", fileNames.length - 1, fileNames[0]);
        }
        return Clip.preview(display, 240);
    }
    readonly property bool showButtons: current || row.hovered || pal.touch || expanded

    width: ListView.view ? ListView.view.width : implicitWidth
    spacing: metrics.px(4)
    // The actions open under the row: the list scrolls them into view once the row has grown.
    onHeightChanged: {
        if (expanded && ListView.view) {
            const view = ListView.view;
            const row = index;
            // After the list has laid out the taller row.
            Qt.callLater(() => view.positionViewAtIndex(row, ListView.Contain));
        }
    }

    T.AbstractButton {
        id: row
        objectName: "clipboardEntry"
        Layout.fillWidth: true
        implicitHeight: Math.max(entry.metrics.px(entry.pal.touch ? 56 : 48), rowContent.implicitHeight + entry.metrics.px(12))
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        text: entry.label
        Accessible.role: Accessible.ListItem
        Accessible.name: entry.label
        Accessible.description: entry.starred ? i18nc("@info:status clipboard entry", "Starred") : ""
        Accessible.selected: entry.current
        Accessible.onPressAction: entry.chosen()
        onClicked: entry.chosen()
        onHoveredChanged: if (hovered) entry.hovered()
        onPressAndHold: entry.expandToggled()

        background: Rectangle {
            radius: 10
            color: row.down ? entry.pal.overlay(0.1)
                 : (entry.current || row.hovered ? entry.pal.overlay(0.06) : "transparent")
            FocusRing {
                anchors.margins: -2
                baseRadius: 10
                ringColor: entry.pal.focus
                shown: entry.current && entry.keyboardFocus && !entry.expanded
            }
        }

        contentItem: RowLayout {
            id: rowContent
            spacing: entry.metrics.px(10)

            // Image thumbnail, or the first copied file's preview (Klipper's own preview provider).
            Rectangle {
                id: thumbnail
                readonly property bool isImage: entry.type === Clip.IMAGE
                readonly property bool isFiles: entry.type === Clip.URL
                visible: isImage || isFiles
                Layout.leftMargin: entry.metrics.px(8)
                Layout.preferredHeight: entry.metrics.px(isImage ? 56 : 40)
                Layout.preferredWidth: isImage && entry.imageSize.height > 0
                    ? Math.min(entry.metrics.px(96), Math.max(entry.metrics.px(28), Layout.preferredHeight * entry.imageSize.width / entry.imageSize.height))
                    : Layout.preferredHeight
                radius: 6
                color: entry.pal.overlay(0.06)
                clip: true
                Image {
                    anchors.fill: parent
                    visible: thumbnail.visible
                    asynchronous: true
                    // Klipper rewrites an entry's files when it changes (the stock widget does
                    // the same).
                    cache: false
                    fillMode: thumbnail.isImage ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    sourceSize.height: Math.ceil(thumbnail.height * entry.metrics.dpr)
                    source: thumbnail.isImage ? (entry.model.decoration || "")
                          : thumbnail.isFiles ? "image://klipperpreview/" + Clip.firstUrl(entry.display) : ""
                }
            }
            FText {
                Layout.fillWidth: true
                Layout.leftMargin: thumbnail.visible ? 0 : entry.metrics.px(12)
                pal: entry.pal
                metrics: entry.metrics
                text: entry.label
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: entry.type === Clip.TEXT ? entry.pal.text : entry.pal.body
            }
            IconButton {
                id: starButton
                objectName: "clipboardStar"
                pal: entry.pal
                size: entry.metrics.px(30)
                iconSize: entry.metrics.px(16)
                focusPolicy: Qt.NoFocus
                fill: "transparent"
                opacity: entry.starred || entry.showButtons ? 1 : 0
                enabled: opacity > 0
                iconPath: Icons.star
                iconFillPath: entry.starred ? Icons.star : ""
                iconColor: entry.starred ? entry.pal.charging : entry.pal.controlText
                text: entry.starred ? i18nc("@action:button clipboard entry", "Remove star") : i18nc("@action:button clipboard entry", "Star")
                // No tooltip in touch mode: a tap leaves it over the actions that open below.
                toolTip: entry.pal.touch ? "" : text
                onClicked: entry.starToggled()
            }
            IconButton {
                objectName: "clipboardMore"
                Layout.rightMargin: entry.metrics.px(4)
                pal: entry.pal
                size: entry.metrics.px(30)
                iconSize: entry.metrics.px(16)
                focusPolicy: Qt.NoFocus
                fill: entry.expanded ? entry.pal.overlay(0.1) : "transparent"
                opacity: entry.showButtons ? 1 : 0
                enabled: opacity > 0
                iconPath: Icons.more
                text: i18nc("@action:button clipboard entry", "More actions")
                toolTip: entry.pal.touch ? "" : text
                onClicked: entry.expandToggled()
            }
        }
    }

    // The entry's actions (the stock widget's row buttons), under the row while open. The list
    // keeps the keyboard focus: Left and Right move `actionIndex` over the shown buttons and Enter
    // presses one (ClipboardPage.qml), so no hidden button keeps a focus the list would give back.
    readonly property var actionButtons: [starAction, editAction, qrAction, invokeAction, removeAction].filter(b => b.visible)
    function pressAction(i: int): void {
        if (i >= 0 && i < actionButtons.length) {
            actionButtons[i].clicked();
        }
    }
    Flow {
        id: actions
        Layout.fillWidth: true
        Layout.leftMargin: entry.metrics.px(8)
        Layout.bottomMargin: entry.metrics.px(4)
        visible: entry.expanded
        spacing: entry.metrics.px(6)
        readonly property real buttonHeight: entry.pal.touch ? 44 : entry.metrics.px(30)

        TextButton {
            id: starAction
            pal: entry.pal
            metrics: entry.metrics
            implicitHeight: actions.buttonHeight
            focusPolicy: Qt.NoFocus
            highlighted: entry.keyboardFocus && entry.actionButtons[entry.actionIndex] === starAction
            iconPath: Icons.star
            text: entry.starred ? i18nc("@action:button clipboard entry", "Remove star") : i18nc("@action:button clipboard entry", "Star")
            onClicked: entry.starToggled()
        }
        TextButton {
            id: editAction
            visible: entry.type === Clip.TEXT
            pal: entry.pal
            metrics: entry.metrics
            implicitHeight: actions.buttonHeight
            focusPolicy: Qt.NoFocus
            highlighted: entry.keyboardFocus && entry.actionButtons[entry.actionIndex] === editAction
            iconPath: Icons.pen
            text: i18nc("@action:button clipboard entry", "Edit")
            onClicked: entry.editRequested()
        }
        TextButton {
            id: qrAction
            visible: entry.type === Clip.TEXT
            pal: entry.pal
            metrics: entry.metrics
            implicitHeight: actions.buttonHeight
            focusPolicy: Qt.NoFocus
            highlighted: entry.keyboardFocus && entry.actionButtons[entry.actionIndex] === qrAction
            iconPath: Icons.qrCode
            text: i18nc("@action:button clipboard entry", "QR code")
            onClicked: entry.qrRequested()
        }
        TextButton {
            id: invokeAction
            pal: entry.pal
            metrics: entry.metrics
            implicitHeight: actions.buttonHeight
            focusPolicy: Qt.NoFocus
            highlighted: entry.keyboardFocus && entry.actionButtons[entry.actionIndex] === invokeAction
            iconPath: Icons.bolt
            text: i18nc("@action:button clipboard entry: Klipper's actions for it", "Actions")
            Accessible.description: i18nc("@info:tooltip", "Klipper's actions for this entry")
            onClicked: entry.actionsRequested()
        }
        TextButton {
            id: removeAction
            pal: entry.pal
            metrics: entry.metrics
            implicitHeight: actions.buttonHeight
            focusPolicy: Qt.NoFocus
            highlighted: entry.keyboardFocus && entry.actionButtons[entry.actionIndex] === removeAction
            iconPath: Icons.trash
            textColor: entry.pal.danger
            text: i18nc("@action:button clipboard entry", "Remove")
            onClicked: entry.removeRequested()
        }
    }
}
