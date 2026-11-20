/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQml

// What the placement script tells the bars' layout controls about tiling: whether supported
// tiling is available, whether a session is on and the view it tiles, in an order a reader can
// trust (the workspace layout control, P1). The script stays the only authority: it binds
// `nativeCapable` to its native verdict and hands the session in where the tiler starts or ends
// one (main.qml, tiler.reportSession). This object keeps that state, its revision and a
// lifetime label; it is never given the native token.
//
// Read the state on revisionChanged: a change sets the fields first and moves the revision
// last, once.
QtObject {
    // The native verdict, bound by the script: a registered provider, its memory loaded and the
    // tiler's facade complete. Anything less never reports ready.
    property bool nativeCapable: false

    // Written by start(), setSession(), retire() and a change of the verdict alone.
    // Whether the provider serves its state: from start() until retire().
    property bool online: false
    // Whether supported tiling is available: the verdict while online, false while offline, so
    // no state carries a capability that changed after its revision.
    property bool capable: false
    // The state's order: 1 at start(), then one step for each change of what a reader is
    // told - capability, the session or its view, going offline - and none otherwise.
    property int revision: 0
    // The session, and the view it tiles as a bar names one.
    property bool active: false
    property string desktopId: ""
    property string activityId: ""
    property string outputName: ""

    // A public lifetime label, not a credential: drawn fresh for every provider lifetime, so a
    // refused or absent backend cannot share one (as the layout probe draws its own).
    readonly property string label: Qt.md5([Date.now(), Math.random(), Math.random(),
                                            Math.random(), Math.random()].join(":"))

    // A verdict that changes while online (a memory that loads late) is a new state; one that
    // changes while offline is no state at all.
    onNativeCapableChanged: {
        if (online) {
            capable = nativeCapable;
            revision += 1;
        }
    }

    // The script has started: the state as it stands is the first one.
    function start(): void {
        if (online || revision > 0) {
            return;
        }
        online = true;
        capable = nativeCapable;
        revision = 1;
    }

    // A session started or ended; nothing moves when nothing changed.
    function setSession(on: bool, desktop: string, activity: string, output: string): void {
        if (!online || (active === on && desktopId === desktop && activityId === activity
                        && outputName === output)) {
            return;
        }
        active = on;
        desktopId = desktop;
        activityId = activity;
        outputName = output;
        revision += 1;
    }

    // The script is going: offline, with no capability or session left to report. Nothing
    // moves after this.
    function retire(): void {
        if (!online) {
            return;
        }
        online = false;
        capable = false;
        active = false;
        desktopId = "";
        activityId = "";
        outputName = "";
        revision += 1;
    }
}
