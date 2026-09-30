// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "components"

// Plasma Fusion quick settings: the right side of the top bar (keyboard layout,
// phone, clipboard, status pill, notification bell) and a floating pop-up with
// quick settings and the notification list.
//
// The widget has no fullRepresentation: the bar is shown directly in the panel
// and the pop-up is an own AppletPopup with a margin, so it floats 10 px below the
// top bar and 16 px from the screen edge with all four corners rounded (the stock
// pop-up of a non-floating panel is glued to the panel and the screen edge).
PlasmoidItem {
    id: root

    readonly property bool inPanel: [PlasmaCore.Types.TopEdge, PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge, PlasmaCore.Types.LeftEdge].includes(Plasmoid.location)
    // Text scale and pixel grid of the panel window (docs/parts/shell-quicksettings.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }
    // Width of the pop-up card: 356 px on the board, scaled with the text, at most the screen
    // less 32 px, in whole device pixels of the pop-up's screen.
    readonly property real outerWidth: {
        const pm = content.metrics;
        const screenWidth = Plasmoid.containment ? Plasmoid.containment.availableScreenRect.width : 1440;
        return pm.windowSize(Math.min(pm.px(356), screenWidth - 32));
    }
    readonly property int popupGap: Plasmoid.configuration.popupGap
    readonly property int popupScreenMargin: Plasmoid.configuration.popupScreenMargin

    property bool popupOpen: false
    property bool openOnPress: false
    property real maxPopupHeight: 820

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: popupOpen ? PlasmaCore.Types.RequiresAttentionStatus : PlasmaCore.Types.ActiveStatus
    activationTogglesExpanded: false
    hideOnWindowDeactivate: true
    toolTipMainText: ""
    toolTipSubText: ""

    Layout.minimumWidth: topBar.implicitWidth
    Layout.preferredWidth: topBar.implicitWidth
    Layout.maximumWidth: topBar.implicitWidth
    Layout.minimumHeight: 26
    Layout.preferredHeight: m.px(34)

    function togglePopup() {
        setPopupOpen(!popupOpen);
    }
    function setPopupOpen(open: bool) {
        if (open) {
            placeAnchor();
            const start = String(Plasmoid.configuration.startPage || "main");
            backend.page = ["main", "wifi", "bluetooth", "audio"].indexOf(start) !== -1 ? start : "main";
        }
        popupOpen = open;
    }
    // Places the pop-up's anchor so that the card ends popupScreenMargin px
    // from the screen edge (or at the widget's own edge when it sits further in).
    function placeAnchor() {
        const screen = Plasmoid.containment ? Plasmoid.containment.screenGeometry : null;
        const global = root.mapToGlobal(0, 0);
        if (!screen || screen.width <= 0) {
            popupAnchor.x = root.width - outerWidth;
            return;
        }
        const widgetRight = global.x + root.width;
        const popupRight = Math.min(screen.x + screen.width - popupScreenMargin, widgetRight);
        popupAnchor.x = popupRight - outerWidth - global.x;

        popupAnchor.width = outerWidth;
        if (Plasmoid.location === PlasmaCore.Types.LeftEdge || Plasmoid.location === PlasmaCore.Types.RightEdge) {
            // Beside a vertical panel the pop-up opens next to the widget itself.
            popupAnchor.x = 0;
            popupAnchor.width = root.width;
        }

        // A pop-up of a non-floating panel is placed against the panel window's edge
        // (not the widget's), so measure from there to keep popupScreenMargin exact.
        const windowTop = global.y - root.mapToItem(null, 0, 0).y;
        const windowHeight = root.Window.height > 0 ? root.Window.height : root.height;
        let available = screen.height - popupGap - popupScreenMargin;
        if (Plasmoid.location === PlasmaCore.Types.TopEdge) {
            const panelBottom = Math.max(global.y + root.height, windowTop + windowHeight);
            available = screen.y + screen.height - panelBottom - popupGap - popupScreenMargin;
        } else if (Plasmoid.location === PlasmaCore.Types.BottomEdge) {
            const panelTop = Math.min(global.y, windowTop);
            available = panelTop - screen.y - popupGap - popupScreenMargin;
        }
        maxPopupHeight = Math.max(320, available);
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.togglePopup();
        }
    }

    Backend {
        id: backend
        popupOpen: root.popupOpen
        showKeyboardLayout: Plasmoid.configuration.showKeyboardLayout
        keyboardLayoutAlways: Plasmoid.configuration.keyboardLayoutAlways
        showKdeConnect: Plasmoid.configuration.showKdeConnect
        showClipboard: Plasmoid.configuration.showClipboard
        showBatteryPercent: Plasmoid.configuration.showBatteryPercent
        showNotifications: Plasmoid.configuration.showNotifications
        lightLookAndFeel: Plasmoid.configuration.lightLookAndFeel
        darkLookAndFeel: Plasmoid.configuration.darkLookAndFeel
        onCloseRequested: root.setPopupOpen(false)
    }

    TopBar {
        id: topBar
        anchors.fill: parent
        backend: backend
        metrics: m
        popupOpen: root.popupOpen
        onPillPressed: root.openOnPress = !root.popupOpen
        onPillClicked: {
            backend.showEmptyNotifications = false;
            root.setPopupOpen(root.openOnPress);
        }
        onBellPressed: root.openOnPress = !root.popupOpen
        onBellClicked: {
            backend.showEmptyNotifications = root.openOnPress;
            root.setPopupOpen(root.openOnPress);
        }
    }

    // Invisible item the pop-up is placed under (see placeAnchor()).
    Item {
        id: popupAnchor
        y: 0
        width: root.outerWidth
        height: root.height
    }

    // After the pop-up closed itself (focus moved elsewhere), follow its state a
    // little later, so that a click on the pill closes rather than reopens it.
    Timer {
        id: closeSync
        interval: 150
        onTriggered: {
            if (!popup.visible) {
                root.popupOpen = false;
            }
        }
    }

    onPopupOpenChanged: {
        if (!popupOpen) {
            backend.notif.markRead();
            resetPage.restart();
        }
    }
    Timer {
        id: resetPage
        interval: 300
        onTriggered: {
            if (!root.popupOpen) {
                backend.page = "main";
                backend.showEmptyNotifications = false;
            }
        }
    }

    PlasmaCore.AppletPopup {
        id: popup

        visualParent: popupAnchor
        popupDirection: {
            switch (Plasmoid.location) {
            case PlasmaCore.Types.BottomEdge:
                return Qt.TopEdge;
            case PlasmaCore.Types.LeftEdge:
                return Qt.RightEdge;
            case PlasmaCore.Types.RightEdge:
                return Qt.LeftEdge;
            default:
                return Qt.BottomEdge;
            }
        }
        margin: root.popupGap
        floating: !root.inPanel
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        visible: root.popupOpen

        onVisibleChanged: {
            if (visible) {
                popup.requestActivate();
                content.forceActiveFocus();
                content.focusFirst();
            } else {
                closeSync.restart();
            }
        }

        mainItem: PopupContent {
            id: content
            backend: backend
            open: root.popupOpen
            outerWidth: root.outerWidth
            framePaddingLeft: popup.leftPadding
            framePaddingRight: popup.rightPadding
            framePaddingTop: popup.topPadding
            framePaddingBottom: popup.bottomPadding
            maxOuterHeight: root.maxPopupHeight
            focus: true
        }
    }
}
