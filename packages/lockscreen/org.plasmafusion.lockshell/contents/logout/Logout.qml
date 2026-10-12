/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    Plasma Fusion log-out screen for Plasma 6.8 and later, whose log-out greeter reads the shell
    package (plasma-workspace 3729037a): plasma-desktop Plasma/6.8's desktoppackage
    contents/logout/ (this file, LogoutControls.qml, LogoutButton.qml, timer.js,
    controlsowner.js) with the changes Plasma Fusion's 6.7 copy in the Global Theme has. Breeze
    draws the Complementary colours on a black veil; Plasma Fusion Light has a light
    Complementary set (Colors board), so the veil takes the Complementary background instead:
    dark in Plasma Fusion Dark, light in Plasma Fusion Light, always readable. The count-down
    leaves timer.js's shared list when its screen goes (see timer.js). As in 6.8, every
    screen gets the veil and the count-down, and one set of controls follows the pointer to the
    screen it is on (LogoutControls, owned through controlsowner.js; the greeter's views share
    one engine, so the library is shared too).
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Window

import org.kde.kirigami as Kirigami

import "timer.js" as AutoTriggerTimer
import "controlsowner.js" as ControlsOwner

Item {
    id: root
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    signal logoutRequested()
    signal haltRequested()
    signal haltUpdateRequested()
    signal suspendRequested(int spdMethod)
    signal rebootRequested()
    signal rebootRequested2(int opt)
    signal rebootUpdateRequested()
    signal cancelRequested()
    signal lockScreenRequested()
    signal cancelSoftwareUpdateRequested()

    function sleepRequested() {
        root.suspendRequested(2);
    }

    function hibernateRequested() {
        root.suspendRequested(4);
    }

    property real timeout: 30
    property real remainingTime: root.timeout
    readonly property bool countingDown: countDownTimer.running

    property var currentAction: {
        switch (sdtype) {
        case ShutdownType.ShutdownTypeReboot:
            return () => softwareUpdatePending ? rebootUpdateRequested() : rebootRequested();
        case ShutdownType.ShutdownTypeHalt:
            return () => softwareUpdatePending ? haltUpdateRequested() : haltRequested();
        default:
            return () => logoutRequested();
        }
    }

    readonly property bool showAllOptions: sdtype === ShutdownType.ShutdownTypeDefault

    Component {
        id: controlsComponent
        LogoutControls {}
    }

    function ensureControlsExist() {
        if (!ControlsOwner.controls) {
            ControlsOwner.controls = controlsComponent.createObject(root);
            ControlsOwner.maker = root;
        }
    }
    readonly property bool pointerHere: hover.hovered

    Component.onCompleted: {
        ControlsOwner.roots.push(root);
        ensureControlsExist();
    }
    // The controls are the children of the screen that made them, wherever they are shown, so they
    // go when that screen goes (an output unplugged while the greeter is open). Another screen
    // makes them again at once: the one with the pointer, or the first one left. (Upstream 6.8
    // only reparents them on hover, so the remaining screens kept none.)
    Component.onDestruction: {
        ControlsOwner.roots = ControlsOwner.roots.filter(other => other !== root);
        if (ControlsOwner.maker === root) {
            ControlsOwner.controls = null;
            ControlsOwner.maker = null;
            const next = ControlsOwner.roots.find(other => other.pointerHere) ?? ControlsOwner.roots[0];
            if (next) {
                next.ensureControlsExist();
            }
        }
    }

    // Not MouseArea: hovering a LogoutButton steals
    // the pointer from it, so containsMouse would flicker and the row would
    // flash in and out. HoverHandler is non-blocking, so it just tracks the
    // pointer position and stays accurate.
    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered) {
                if (root.Window.window) {
                    root.Window.window.requestActivate();
                }
                root.ensureControlsExist();
                if (ControlsOwner.controls && ControlsOwner.controls.parent !== root) {
                    ControlsOwner.controls.parent = root;
                }
            }
        }
    }

    QQC2.Action {
        onTriggered: root.cancelRequested()
        shortcut: "Escape"
    }

    onRemainingTimeChanged: {
        if (remainingTime <= 0) {
            (currentAction)();
        }
    }

    Timer {
        id: countDownTimer
        running: !showAllOptions
        repeat: true
        interval: 1000
        onTriggered: remainingTime--
        // Kept to take it out of the shared list again when this screen goes (timer.js).
        property var cancelCallback: null
        Component.onCompleted: {
            cancelCallback = function() {
                countDownTimer.running = false;
            };
            AutoTriggerTimer.addCancelAutoTriggerCallback(cancelCallback);
        }
        Component.onDestruction: AutoTriggerTimer.removeCancelAutoTriggerCallback(cancelCallback)
    }

    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        objectName: "logoutVeil"
        // The Complementary background, so its text colour always reads on it.
        color: Kirigami.Theme.backgroundColor
        opacity: 0.85
    }
    MouseArea {
        // A pointer convenience: a click beside the buttons cancels, like the Cancel button.
        Accessible.ignored: true
        anchors.fill: parent
        onClicked: root.cancelRequested()
    }
}
