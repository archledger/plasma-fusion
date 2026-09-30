// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

import "services"

// Plasma Fusion pen menu (PEN.md 3, docs/parts/pen.md): a button in the top bar, between the tray
// and quick settings, that opens a card with pen actions (new note, snip, mark up, whiteboard,
// draw on screen) and the pen settings. The button shows only while a pen exists and, by default,
// in tablet posture (FusionTablet, KWin's own state); hidden, the widget still opens the card from
// its global shortcut (Meta+Shift+W, set by fusion-config.sh --pen) and from an openRequest
// written through desktop scripting ("<mode>:<nonce>", modes open, close, toggle, newnote,
// settings). The card is placed from the screen alone (right edge 16 px from the screen, 12 in
// tablet posture; centred in portrait), never from the widget, which a hidden widget has at the
// panel's start (PEN.md 3.1). Its content is built on the first open; at idle only the button
// and one D-Bus read of the pen exist.
PlasmoidItem {
    id: root

    readonly property bool inPanel: [PlasmaCore.Types.TopEdge, PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge, PlasmaCore.Types.LeftEdge].includes(Plasmoid.location)

    FusionTablet {
        id: tabletState
    }
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
        tablet: tabletState.tablet
    }
    FusionAccent {
        id: barTint
    }
    PenDevice {
        id: penDevice
        forcePen: Plasmoid.configuration.forcePen
        onLogged: text => console.info(text)
    }
    Exec {
        id: penExec
    }

    // A pen is connected (quick settings' tablet row reads it from the same bar).
    readonly property bool hasPen: penDevice.hasPen
    readonly property string showButton: String(Plasmoid.configuration.showButton)
    readonly property bool buttonShown: penDevice.hasPen && (showButton === "always" || (showButton === "tablet" && tabletState.tablet))
    // The global shortcut as portable text ("Meta+Shift+W"), for the click-button choice.
    readonly property string shortcutText: {
        const s = Plasmoid.globalShortcut;
        return s ? String(s) : "";
    }

    property bool popupOpen: false
    property bool openOnPress: false
    property bool wantSettings: false
    property bool openReportPending: false

    readonly property real screenMargin: m.px(tabletState.tablet ? 12 : 16)
    readonly property real barGap: m.px(tabletState.tablet ? 8 : 10)
    // The card: 404 px, scaled with the text, at most the screen less 32 px, in whole device
    // pixels.
    readonly property real outerWidth: {
        const screenWidth = Plasmoid.containment ? Plasmoid.containment.availableScreenRect.width : 1440;
        return m.windowSize(Math.min(m.px(404), screenWidth - 32));
    }
    property real maxPopupHeight: 800

    // Test hook: the button's place once the panel has laid the applet out (it gets its width only
    // after buttonShown changes, so the report waits until the geometry stops changing).
    onButtonShownChanged: buttonReport.restart()
    onWidthChanged: buttonReport.restart()
    Timer {
        id: buttonReport
        interval: 150
        onTriggered: {
            const g = button.mapToGlobal(0, 0);
            console.info("pen: button " + (root.buttonShown ? "shown at " + Math.round(g.x) + "," + Math.round(g.y) + " "
                                                             + Math.round(button.width) + "x" + Math.round(button.height) : "hidden"));
        }
    }
    Connections {
        target: root.buttonShown ? button : null
        function onXChanged() { buttonReport.restart(); }
        function onYChanged() { buttonReport.restart(); }
        function onWidthChanged() { buttonReport.restart(); }
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: popupOpen ? PlasmaCore.Types.RequiresAttentionStatus
                               : buttonShown ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    activationTogglesExpanded: false
    hideOnWindowDeactivate: true
    toolTipMainText: ""
    toolTipSubText: ""

    Layout.minimumWidth: buttonShown ? button.implicitWidth : 0
    Layout.preferredWidth: buttonShown ? button.implicitWidth : 0
    Layout.maximumWidth: buttonShown ? button.implicitWidth : 0
    Layout.minimumHeight: buttonShown ? Math.min(button.implicitHeight, m.px(26)) : 0
    Layout.preferredHeight: buttonShown ? button.implicitHeight : 0

    function setPopupOpen(open: bool): void {
        if (open) {
            menuLoader.active = true;
            placeAnchor();
            if (menuLoader.item) {
                menuLoader.item.refresh();
                if (wantSettings) {
                    menuLoader.item.openSettings();
                } else {
                    menuLoader.item.page = "main";
                }
                wantSettings = false;
            }
        }
        popupOpen = open;
    }
    function togglePopup(): void {
        setPopupOpen(!popupOpen);
    }

    // Places the pop-up's anchor from the screen alone (PEN.md 3.1, PT7).
    function placeAnchor(): void {
        const screen = Plasmoid.containment ? Plasmoid.containment.screenGeometry : null;
        const avail = Plasmoid.containment ? Plasmoid.containment.availableScreenRect : null;
        const global = root.mapToGlobal(0, 0);
        popupAnchor.width = outerWidth;
        if (!screen || screen.width <= 0) {
            popupAnchor.x = root.width - outerWidth;
            return;
        }
        const right = m.portrait ? screen.x + (screen.width + outerWidth) / 2 : screen.x + screen.width - screenMargin;
        popupAnchor.x = right - outerWidth - global.x;
        const top = avail ? screen.y + avail.y : screen.y;
        const bottom = avail ? screen.y + avail.y + avail.height : screen.y + screen.height;
        maxPopupHeight = Math.max(320, bottom - top - barGap - screenMargin);
    }

    // Actions (PEN.md 3.3). Apps start through kstart --application in their own scope.
    function q(text: string): string {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }
    function localPath(url): string {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    }
    function openNote(template: string, prefix: string): void {
        const tpl = StandardPaths.locate(StandardPaths.GenericDataLocation, "plasma-fusion/pen/templates/" + template);
        const docs = localPath(StandardPaths.writableLocation(StandardPaths.DocumentsLocation));
        const dir = docs + "/Notes";
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd HHmm");
        const base = prefix + " " + stamp;
        // The app gets a file:// URL (the name has spaces; a bare path reaches it through
        // kio-fuse), kept next to the path while a free name is looked for.
        let cmd = "dir=" + q(dir) + "; durl=" + q("file://" + encodeURI(dir)) + "; base=" + q(base)
                + "; ubase=" + q(encodeURIComponent(base)) + "; mkdir -p \"$dir\"; f=\"$dir/$base.xopp\"; u=\"$durl/$ubase.xopp\"; n=2; "
                + "while [ -e \"$f\" ]; do f=\"$dir/$base ($n).xopp\"; u=\"$durl/$ubase%20($n).xopp\"; n=$((n+1)); done; ";
        if (String(tpl).length > 0) {
            cmd += "cp " + q(localPath(tpl)) + " \"$f\" && ";
        }
        cmd += "kstart --application com.github.xournalpp.xournalpp --url \"$u\"";
        console.info("pen: run " + cmd);
        penExec.run(cmd);
    }
    function runAction(id: string): void {
        setPopupOpen(false);
        if (id === "newnote") {
            openNote("Note.xopp", i18nc("file name prefix of a new note", "Note"));
        } else if (id === "whiteboard") {
            openNote("Whiteboard.xopp", i18nc("file name prefix of a new whiteboard", "Whiteboard"));
        } else if (id === "installxournal") {
            console.info("pen: open appstream://com.github.xournalpp.xournalpp");
            Qt.openUrlExternally("appstream://com.github.xournalpp.xournalpp");
        } else if (id === "snip" || id === "markup" || id === "drawonscreen") {
            // After the card has closed, so that it is not in the picture.
            afterClose.action = id;
            afterClose.restart();
        }
    }
    Timer {
        id: afterClose
        property string action: ""
        interval: 250
        onTriggered: {
            if (action === "snip") {
                console.info("pen: run spectacle -b -r -k -c -n");
                penExec.run("spectacle -b -r -k -c -n");
            } else if (action === "markup") {
                console.info("pen: invokeShortcut RectangularRegionScreenShot");
                DBus.SessionBus.asyncCall({
                    "service": "org.kde.kglobalaccel",
                    "path": "/component/org_kde_spectacle_desktop",
                    "iface": "org.kde.kglobalaccel.Component",
                    "member": "invokeShortcut",
                    "arguments": [new DBus.string("RectangularRegionScreenShot")],
                    "signature": "(s)"
                });
            } else if (action === "drawonscreen") {
                console.info("pen: run kstart wayscriber");
                penExec.run("kstart wayscriber");
            }
        }
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.togglePopup();
        }
    }
    // Desktop scripting: openRequest = "<mode>:<nonce>" (the launcher's form; "<mode> <nonce>"
    // is accepted too). "close" never opens a closed card (the garage service cannot know).
    Connections {
        target: Plasmoid.configuration
        function onOpenRequestChanged() {
            const mode = String(Plasmoid.configuration.openRequest || "").split(/[: ]/)[0];
            if (mode === "open") {
                root.setPopupOpen(true);
            } else if (mode === "close") {
                if (root.popupOpen) {
                    root.setPopupOpen(false);
                }
            } else if (mode === "toggle") {
                root.togglePopup();
            } else if (mode === "newnote") {
                root.runAction("newnote");
            } else if (mode === "settings") {
                root.wantSettings = true;
                root.setPopupOpen(true);
            }
        }
    }

    PenButton {
        id: button
        anchors.centerIn: parent
        visible: root.buttonShown
        metrics: m
        tint: barTint
        ink: Kirigami.Theme.textColor
        open: root.popupOpen
        onPressed: root.openOnPress = !root.popupOpen
        onClicked: root.setPopupOpen(root.openOnPress)
    }

    // Invisible item the pop-up is placed under (placeAnchor()).
    Item {
        id: popupAnchor
        y: 0
        width: root.outerWidth
        height: Math.max(1, root.height)
    }

    // After the pop-up closed itself (focus moved elsewhere), follow its state a little later,
    // so that a tap on the button closes rather than reopens it.
    Timer {
        id: closeSync
        interval: 150
        onTriggered: {
            if (!popup.visible) {
                root.popupOpen = false;
            }
        }
    }

    PlasmaCore.AppletPopup {
        id: popup

        visualParent: popupAnchor
        popupDirection: Plasmoid.location === PlasmaCore.Types.BottomEdge ? Qt.TopEdge : Qt.BottomEdge
        margin: root.barGap
        floating: !root.inPanel
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        visible: root.popupOpen && menuLoader.status === Loader.Ready

        onVisibleChanged: {
            if (visible) {
                popup.requestActivate();
                menuLoader.item.forceActiveFocus();
                menuLoader.item.focusFirst();
                root.openReportPending = true;
                menuLoader.item.requestReport();
            } else {
                console.info("pen: card closed");
                closeSync.restart();
                // Give the closed card's graphics resources back (PEN.md PT8): the card is opened
                // now and then, and its window would otherwise keep them for the session.
                popup.releaseResources();
            }
        }

        mainItem: Loader {
            id: menuLoader
            active: false
            asynchronous: true
            focus: true
            onLoaded: {
                item.refresh();
                if (root.wantSettings) {
                    item.openSettings();
                    root.wantSettings = false;
                }
            }
            sourceComponent: PenMenu {
                metrics: m
                device: penDevice
                exec: penExec
                shortcutText: root.shortcutText
                outerWidth: root.outerWidth
                frameLeft: popup.leftPadding
                frameRight: popup.rightPadding
                frameTop: popup.topPadding
                frameBottom: popup.bottomPadding
                maxHeight: root.maxPopupHeight - popup.topPadding - popup.bottomPadding
                focus: true
                onCloseRequested: root.setPopupOpen(false)
                onActionRequested: id => root.runAction(id)
                onReport: text => {
                    if (root.openReportPending) {
                        root.openReportPending = false;
                        const s = Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0);
                        console.info("pen: card open at " + popup.x + "," + popup.y + " " + popup.width + "x" + popup.height
                                     + " on screen " + s.x + "," + s.y + " " + s.width + "x" + s.height + "; " + text);
                    } else {
                        console.info("pen: " + text);
                    }
                }
            }
        }
    }
}
