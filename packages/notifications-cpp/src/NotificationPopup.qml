/*
    SPDX-FileCopyrightText: 2019 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

// Plasma Fusion changes in this file are marked "Plasma Fusion": the banner keyboard triage of
// SPEC-notification-triage.md.

import QtQuick
import QtQuick.Layouts

import org.kde.kquickcontrolsaddons as KQuickAddons
import org.kde.kirigami as Kirigami

import org.kde.notificationmanager as NotificationManager
import plasma.applet.org.kde.plasma.notifications as NotificationsApplet

import "delegates" as Delegates

// Plasma Fusion: the rules of the banner keyboard triage.
import "global/BannerTriage.js" as BannerTriage

NotificationsApplet.NotificationWindow {
    id: notificationPopup

    property int popupWidth
    property bool showPopupTimeout

    // Maximum width the popup can take to not break out of the screen geometry.
    readonly property int availableWidth: NotificationsApplet.Globals.screenRect.width - NotificationsApplet.Globals.popupEdgeDistance * 2 - leftPadding - rightPadding

    readonly property int minimumContentWidth: popupWidth
    readonly property int maximumContentWidth: Math.min((availableWidth > 0 ? availableWidth : Number.MAX_VALUE), popupWidth * 3)

    property alias modelInterface: notificationItem.modelInterface

    property int modelTimeout
    property int dismissTimeout

    property var defaultActionFallbackWindowIdx

    signal expired
    signal hoverEntered
    signal hoverExited

    property int defaultTimeout: 5000
    readonly property int effectiveTimeout: {
        if (modelTimeout === -1) {
            return defaultTimeout;
        }
        if (dismissTimeout) {
            return dismissTimeout;
        }
        return modelTimeout;
    }

    // On wayland we need focus to copy to the clipboard, we change on mouse interaction until the cursor leaves
    // Plasma Fusion: and the banner keyboard triage asks for the window's focus the same way.
    takeFocus: notificationItem.modelInterface.replying || focusListener.wantsFocus || triageState !== BannerTriage.STATE_IDLE

    // Plasma Fusion: banner keyboard triage (SPEC-notification-triage.md; the rules are in
    // BannerTriage.js). The interaction with this banner is idle, requested (the shortcut was
    // pressed) or active (KWin gave the banner keyboard focus).
    property string triageState: BannerTriage.STATE_IDLE
    // Reset by each request; true once Escape dismissed the banner, so that a held key does not
    // dismiss it again while it is on its way out.
    property bool triageDismissed: false
    readonly property bool triageActive: triageState === BannerTriage.STATE_ACTIVE
    // What the banner shows and when its notification was last updated. KDE gives a notification a
    // new update time on every replacement; the text and the actions are a second witness to it.
    // A change means the popup now carries another notification, or the same one replaced. It is
    // never reported: what it holds may be private.
    readonly property string triageIdentity: JSON.stringify([notificationPopup.notificationId,
                                                              isNaN(notificationPopup.updated) ? "" : notificationPopup.updated.valueOf(),
                                                              notificationPopup.summary,
                                                              notificationPopup.body,
                                                              notificationPopup.hasDefaultAction,
                                                              notificationPopup.actionNames,
                                                              notificationPopup.actionLabels])
    // True while keyboard focus is in the banner's content or one of its controls. (isAncestorOf
    // is not exposed to QML, so the parents are walked.)
    readonly property bool triageFocusWithin: {
        if (!triageActive) {
            return false;
        }
        for (let item = notificationPopup.activeFocusItem; item; item = item.parent) {
            if (item === focusListener) {
                return true;
            }
        }
        return false;
    }

    // Plasma Fusion: Globals asks the banner for keyboard focus (requestBannerFocus).
    function requestBannerFocus() {
        triageDismissed = false;
        triageState = BannerTriage.transition(triageState, "request").state;
        // The banner may be the active window already, with the pointer on it, and will not
        // become active a second time: the focus is granted here then.
        if (active) {
            triageState = BannerTriage.transition(triageState, "granted").state;
        }
    }

    // Plasma Fusion: Tab is left to the banner's controls, as in stock. Each move of the keyboard
    // focus inside the banner is reported, so that the session scenarios can press Tab until the
    // control they want has it.
    onActiveFocusItemChanged: reportFocusWithin()

    // Plasma Fusion: reports where the keyboard focus is: the type of the item that has it, and
    // whether that is inside the banner's content.
    function reportFocusWithin() {
        const item = notificationPopup.activeFocusItem;
        let inside = false;
        for (let node = item; node; node = node.parent) {
            if (node === focusListener) {
                inside = true;
                break;
            }
        }
        // The type of the item only: what it shows may be a draft or a notification's text.
        const what = item ? String(item).split("(")[0] : "none";
        NotificationsApplet.Globals.shortcuts.reportTriage("focus-within inside=" + inside + " " + what);
    }

    // Plasma Fusion: ends the interaction because KWin or the banner moved on. Nothing is dismissed.
    function triageEnd(reason) {
        triageState = BannerTriage.transition(triageState, reason).state;
        NotificationsApplet.Globals.shortcuts.reportTriage("ended " + reason);
    }

    // Plasma Fusion: Return and Enter do what a click on the banner does, once per press, but only
    // from the banner's content itself. Qt Quick offers a key press to this item before the control
    // inside the banner that has the keyboard focus, and a Keys handler accepts it by default, so
    // a Return meant for a button or for the reply field is refused here in so many words.
    function activateByEnter(event) {
        const action = BannerTriage.enterAction(triageActive, notificationPopup.activeFocusItem === focusListener, modelInterface.hasDefaultAction, event.isAutoRepeat);
        if (action === "") {
            event.accepted = false; // not ours
            return;
        }
        event.accepted = true;
        if (action === "activate") {
            NotificationsApplet.Globals.shortcuts.reportTriage("activated-by-enter " + notificationPopup.notificationId);
            modelInterface.defaultActionInvoked();
        }
    }

    onTriageStateChanged: {
        // The state is compared here, not triageActive: a binding on triageState has not run yet
        // when this handler does.
        if (triageState === BannerTriage.STATE_ACTIVE) {
            focusListener.forceActiveFocus(Qt.ShortcutFocusReason);
            NotificationsApplet.Globals.shortcuts.reportTriage("focus-granted " + notificationPopup.notificationId);
        }
    }

    onActiveChanged: {
        if (active && triageState === BannerTriage.STATE_REQUESTED) {
            triageState = BannerTriage.transition(triageState, "granted").state;
        } else if (!active && triageState !== BannerTriage.STATE_IDLE) {
            // The user or the compositor moved on, or the screen locked: never pull the focus back.
            triageEnd("lost");
        }
    }

    onVisibleChanged: {
        if (!visible && triageState !== BannerTriage.STATE_IDLE) {
            triageEnd("hidden");
        }
    }

    onTriageIdentityChanged: {
        if (triageState === BannerTriage.STATE_IDLE) {
            return;
        }
        // Another notification took over the banner while the interaction was still going. The
        // focus goes back only if the banner still had it.
        const result = BannerTriage.transition(triageState, "replaced");
        triageState = result.state;
        NotificationsApplet.Globals.shortcuts.reportTriage("ended replaced");
        if (result.restoreFocus) {
            NotificationsApplet.Globals.restorePreviousTask();
        }
    }

    visible: false

    height: mainItem.implicitHeight + topPadding + bottomPadding
    width: mainItem.implicitWidth + leftPadding + rightPadding

    mainItem: KQuickAddons.MouseEventListener {
        id: focusListener
        property bool wantsFocus: false

        implicitWidth: Math.min(Math.max(notificationPopup.minimumContentWidth, notificationItem.Layout.preferredWidth), Math.max(notificationPopup.minimumContentWidth, notificationPopup.maximumContentWidth))
        implicitHeight: notificationItem.implicitHeight

        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: wantsFocus = true
        onContainsMouseChanged: {
            wantsFocus = wantsFocus && containsMouse
            if (containsMouse) {
                onEntered: notificationPopup.hoverEntered()
            } else {
                onExited: notificationPopup.hoverExited()
            }
        }

        // Plasma Fusion: on a banner the shortcut focused, Escape dismisses and Return and Enter
        // act as a click. The keys reach this item from the banner's controls as well.
        Keys.onEscapePressed: event => {
            // The reply field is exempt while the keyboard focus is in it, and only then: from
            // any other control of the banner, the close button included, Escape dismisses.
            const inReplyField = BannerTriage.inReplyField(notificationPopup.activeFocusItem, focusListener);
            const action = BannerTriage.escapeAction(notificationPopup.triageActive, inReplyField, notificationPopup.triageDismissed, event.isAutoRepeat);
            if (action === "") {
                event.accepted = false; // not ours: in the reply field Escape keeps its own behaviour
                return;
            }
            event.accepted = true;
            if (action === "dismiss") {
                // The banner's own expiry, as its timeout would run it: the notification stays in
                // the history.
                notificationPopup.triageDismissed = true;
                NotificationsApplet.Globals.shortcuts.reportTriage("dismissed-by-escape " + notificationPopup.notificationId);
                notificationPopup.expired();
            }
        }
        Keys.onReturnPressed: event => notificationPopup.activateByEnter(event)
        Keys.onEnterPressed: event => notificationPopup.activateByEnter(event)

        // Plasma Fusion: KWin did not make the banner active in time (the screen locked, or another
        // window took the focus), so the request is dropped.
        Timer {
            interval: 1500
            running: notificationPopup.triageState === BannerTriage.STATE_REQUESTED && !notificationPopup.active
            onTriggered: notificationPopup.triageEnd("not-granted")
        }

        // Plasma Fusion: the focus ring, in the theme's focus colour, for as long as the banner
        // holds keyboard focus.
        Rectangle {
            anchors.fill: parent
            z: 999
            color: "transparent"
            border.width: 2
            border.color: Kirigami.Theme.focusColor
            visible: notificationPopup.triageFocusWithin
        }

        // Activate default action when dragging a file over the notification.
        DropArea {
            id: activateDefaultActionDropArea
            anchors.fill: parent

            property bool containsAcceptableDrag: false
            property point lastPosition: Qt.point(-1, -1)

            onEntered: (event) => {
                if (notificationItem.modelInterface.hasDefaultAction && !notificationItem.dragging) {
                    dragActivationTimer.restart();
                    containsAcceptableDrag = true;
                    lastPosition = Qt.point(drag.x, drag.y);
                } else {
                    drag.accepted = false;
                }
            }
            onPositionChanged: {
                if (containsAcceptableDrag) {
                    const manhattanLength = Math.abs((drag.x - lastPosition.x) + (drag.y - lastPosition.y));
                    if (manhattanLength > Application.styleHints.startDragDistance) {
                        dragActivationTimer.restart();
                        lastPosition = Qt.point(drag.x, drag.y);
                    }
                }
            }
            onDropped: {
                containsAcceptableDrag = false;
            }
            onExited: {
                containsAcceptableDrag = false;
                dragActivationTimer.stop();
            }
        }

        Timer {
            id: dragActivationTimer
            interval: 250 // same as Task Manager
            repeat: false
            onTriggered: notificationItem.modelInterface.defaultActionInvoked()
        }

        DraggableDelegate {
            anchors {
                fill: parent
                topMargin: notificationPopup.modelInterface.closable || notificationPopup.modelInterface.dismissable || notificationPopup.modelInterface.configurable ? -notificationPopup.topPadding : 0
            }
            leftPadding: 0
            rightPadding: 0
            hoverEnabled: true
            draggable: notificationItem.modelInterface.notificationType != NotificationManager.Notifications.JobType
            onDismissRequested: NotificationsApplet.Globals.popupNotificationsModel.close(NotificationsApplet.Globals.popupNotificationsModel.index(notificationItem.modelInterface.index, 0))

            TapHandler {
                id: tapHandler
                acceptedButtons: {
                    let buttons = Qt.MiddleButton;
                    if (notificationPopup.modelInterface.hasDefaultAction) {
                        buttons |= Qt.LeftButton;
                    }
                    return buttons;
                }
                onTapped: (_eventPoint, button) => {
                    if (button === Qt.MiddleButton) {
                        if (notificationItem.modelInterface.closable) {
                            notificationItem.modelInterface.closeClicked();
                        }
                    } else if (notificationPopup.modelInterface.hasDefaultAction) {
                        notificationItem.modelInterface.defaultActionInvoked();
                    }
                }
            }

            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            LayoutMirroring.childrenInherit: true

            Timer {
                id: timer
                interval: notificationPopup.effectiveTimeout
                running: {
                    if (!notificationPopup.visible) {
                        return false;
                    }
                    // Plasma Fusion: the same pause while the banner keyboard triage holds the banner.
                    if (notificationPopup.triageActive) {
                        return false;
                    }
                    if (focusListener.containsMouse) {
                        return false;
                    }
                    if (interval <= 0) {
                        return false;
                    }
                    if (notificationItem.dragging || notificationItem.menuOpen || activateDefaultActionDropArea.containsAcceptableDrag) {
                        return false;
                    }
                    if (notificationItem.modelInterface.replying
                            && (notificationPopup.active || notificationItem.modelInterface.hasPendingReply)) {
                        return false;
                    }
                    return true;
                }
                onTriggered: {
                    if (notificationPopup.dismissTimeout) {
                        notificationPopup.modelInterface.dismissClicked();
                    } else {
                        notificationPopup.expired();
                    }
                }
            }

            NumberAnimation {
                target: notificationItem.modelInterface
                property: "remainingTime"
                from: timer.interval
                to: 0
                duration: timer.interval
                running: timer.running && Kirigami.Units.longDuration > 1 && notificationPopup.showPopupTimeout
            }

            contentItem: Delegates.DelegatePopup {
                id: notificationItem

                Layout.preferredHeight: implicitHeight // Why is this necessary?

                modelInterface {
                    maximumLineCount: 8
                    bodyCursorShape: modelInterface.hasDefaultAction ? Qt.PointingHandCursor : 0

                    popupLeftPadding: notificationPopup.leftPadding
                    popupTopPadding: notificationPopup.topPadding
                    popupRightPadding: notificationPopup.rightPadding
                    popupBottomPadding: notificationPopup.bottomPadding

                    // When notification is updated, restart hide timer
                    onTimeChanged: {
                        if (timer.running) {
                            timer.restart();
                        }
                    }
                    timeout: timer.running ? timer.interval : 0

                    closable: true

                    onBodyClicked: {
                        if (modelInterface.hasDefaultAction) {
                            notificationItem.modelInterface.defaultActionInvoked();
                        }
                    }
                }
            }
        }
    }
}
