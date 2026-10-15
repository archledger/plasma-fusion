// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami

// The preview window: the files' names and "Open" above, the viewer for the shown file (by its
// kind, QuickLookItem in quicklook.h), its details below. Space or Esc closes, the arrow keys go
// through the files, Enter opens the shown one.
QQC2.ApplicationWindow {
    id: root

    // QuickLookSession (quicklook.h).
    required property var session
    // Tests: where to write what each viewer showed (main.cpp, --test-report).
    property string testReport: ""
    readonly property var item: session.current

    width: Math.min(Kirigami.Units.gridUnit * 60, Screen.desktopAvailableWidth * 0.7)
    height: Math.min(Kirigami.Units.gridUnit * 44, Screen.desktopAvailableHeight * 0.75)
    minimumWidth: Kirigami.Units.gridUnit * 20
    minimumHeight: Kirigami.Units.gridUnit * 14
    visible: true
    title: {
        if (!item) {
            return i18nc("@title:window", "Quick Look");
        }
        if (session.count > 1) {
            return i18nc("@title:window %1 file name, %2 its place, %3 how many files", "%1 (%2 of %3) — Quick Look",
                         item.name, session.index + 1, session.count);
        }
        return i18nc("@title:window %1 file name", "%1 — Quick Look", item.name);
    }

    function viewerFor(kind) {
        switch (kind) {
        case "image":
        case "animation":
            return "ImageViewer.qml";
        case "pdf":
            return "PdfViewer.qml";
        case "text":
            return "TextViewer.qml";
        case "audio":
        case "video":
            return "MediaViewer.qml";
        case "folder":
            return "FolderViewer.qml";
        default:
            return "FileViewer.qml";
        }
    }

    function openCurrent() {
        if (item && item.kind !== "missing") {
            root.visible = false;
            session.openCurrent();
        }
    }

    header: QQC2.ToolBar {
        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            QQC2.ToolButton {
                visible: root.session.count > 1
                icon.name: "go-previous"
                text: i18nc("@action:button the previous file", "Previous")
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                onClicked: root.session.previous()
            }
            QQC2.ToolButton {
                visible: root.session.count > 1
                icon.name: "go-next"
                text: i18nc("@action:button the next file", "Next")
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                onClicked: root.session.next()
            }
            QQC2.Label {
                visible: root.session.count > 1
                text: i18nc("@info %1 the shown file, %2 how many", "%1 of %2", root.session.index + 1, root.session.count)
                opacity: 0.7
            }
            Kirigami.Heading {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                level: 4
                text: root.item ? root.item.name : ""
                elide: Text.ElideMiddle
            }
            QQC2.Button {
                visible: root.item !== null && root.item.kind !== "missing"
                icon.name: "document-open"
                text: root.item && root.item.openWithName.length > 0
                      ? i18nc("@action:button %1 application", "Open with %1", root.item.openWithName)
                      : i18nc("@action:button", "Open")
                onClicked: root.openCurrent()
            }
            QQC2.ToolButton {
                icon.name: "window-close"
                text: i18nc("@action:button", "Close")
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: text
                QQC2.ToolTip.visible: hovered
                onClicked: root.close()
            }
        }
    }

    Loader {
        id: viewer
        objectName: "viewer"
        anchors.fill: parent

        function show() {
            if (root.item) {
                setSource(root.viewerFor(root.item.kind), {item: root.item});
            } else {
                setSource("");
            }
        }

        // A viewer that cannot load (its Qt module missing): the file's thumbnail or icon instead.
        onStatusChanged: {
            if (status === Loader.Error && root.item && source.toString().indexOf("FileViewer.qml") < 0) {
                setSource("FileViewer.qml", {item: root.item});
            }
        }
        Component.onCompleted: show()
        Connections {
            target: root.session
            function onCurrentChanged() {
                viewer.show();
            }
        }
    }

    footer: QQC2.ToolBar {
        position: QQC2.ToolBar.Footer
        QQC2.Label {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
            opacity: 0.8
            text: {
                if (!root.item) {
                    return "";
                }
                const more = viewer.item && viewer.item.extra ? viewer.item.extra : "";
                return more.length > 0 ? root.item.details + " · " + more : root.item.details;
            }
        }
    }

    Shortcut {
        sequences: ["Space", "Escape"]
        onActivated: root.close()
    }
    Shortcut {
        sequences: ["Right", "Down"]
        enabled: root.session.count > 1
        onActivated: root.session.next()
    }
    Shortcut {
        sequences: ["Left", "Up"]
        enabled: root.session.count > 1
        onActivated: root.session.previous()
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        onActivated: root.openCurrent()
    }

    // ---- tests (--test-report): every file in turn, once its viewer is ready
    property var reports: []
    Timer {
        id: testStep
        interval: 100
        repeat: true
        running: root.testReport.length > 0
        property int waited: 0
        onTriggered: {
            const ready = viewer.status === Loader.Ready && viewer.item && viewer.item.ready;
            waited += interval;
            if (!ready && waited < 15000) {
                return;
            }
            const entry = {
                name: root.item ? root.item.name : "",
                kind: root.item ? root.item.kind : "",
                viewer: viewer.item ? viewer.item.objectName : "",
                ready: !!ready,
                details: root.item ? root.item.details : "",
                extra: viewer.item && viewer.item.extra ? viewer.item.extra : "",
                report: viewer.item && viewer.item.report ? viewer.item.report : ({})
            };
            root.reports = root.reports.concat([entry]);
            waited = 0;
            if (root.reports.length < root.session.count) {
                root.session.next();
            } else {
                running = false;
                root.session.writeReport(root.testReport, root.reports);
                Qt.quit();
            }
        }
    }
}
