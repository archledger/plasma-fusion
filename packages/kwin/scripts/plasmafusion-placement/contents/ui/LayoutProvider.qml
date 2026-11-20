/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQml
import org.kde.kwin
import org.kde.plasma.workspace.dbus as DBus

// What the placement script tells the bars' layout controls about tiling: whether supported
// tiling is available, whether a session is on and the view it tiles, in an order a reader can
// trust (the workspace layout control, P1). The script stays the only authority: it binds
// `nativeCapable` to its native verdict and hands the session in where the tiler starts or ends
// one (main.qml, tiler.reportSession). This object keeps that state, its revision, a lifetime
// label and the lifetime's identity name on the session bus; it is never given the native
// token.
//
// Read the state on revisionChanged: a change sets the fields first and moves the revision
// last, once.
QtObject {
    id: provider

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

    // The lifetime's identity name: a fence between provider lifetimes on the session bus, not
    // authentication (g0-decisions.md). It is asked for at start(), whatever the capability,
    // without queueing (flag 4: a name another connection holds is refused at once), and
    // released by retire() with the name it stored, so nothing of a torn-down context is
    // looked up; it exports no object. Its owner, once granted, is this connection - KWin's -
    // which a reader checks against the KWin service's owner. The layout probe proved this
    // transport in P0 (tools/tests/layout-control/provider.qml).
    readonly property string identityName: "org.plasmafusion.LayoutProvider.p" + label
    // Whether the name is held and its owner - a unique connection name, kept only then - is
    // known; the identity never moves the revision.
    property bool identityReady: false
    property string selfOwner: ""
    // The pending RequestName, until it is answered or the provider retires.
    property var registration: null

    property Connections registrationWatch: Connections {
        target: provider.registration
        function onFinished() {
            provider.registrationFinished();
        }
    }

    property DBusCall identityLookup: DBusCall {
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "GetNameOwner"
        onFinished: value => provider.ownerFound(String(value[0]))
        onFailed: console.warn("plasmafusion-placement: layout provider: the identity name's owner could not be"
                               + " read; nothing will be published this session")
    }

    property DBusCall identityRelease: DBusCall {
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        dbusInterface: "org.freedesktop.DBus"
        method: "ReleaseName"
    }

    // A verdict that changes while online (a memory that loads late) is a new state; one that
    // changes while offline is no state at all.
    onNativeCapableChanged: {
        if (online) {
            capable = nativeCapable;
            revision += 1;
        }
    }

    // The script has started: the state as it stands is the first one, and the lifetime asks
    // for its identity name.
    function start(): void {
        if (online || revision > 0) {
            return;
        }
        online = true;
        capable = nativeCapable;
        revision = 1;
        // An explicit signature: the plugin then encodes each argument by its letter, so the
        // flags go out as a uint32 with no wrapper type (plasma-workspace components/dbus,
        // the same at 6.7.5 and 6.8.3: DBusPendingReply::callInternal, Encoder::encode).
        registration = DBus.SessionBus.asyncCall({
            service: "org.freedesktop.DBus", path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus", member: "RequestName", signature: "(su)",
            arguments: [identityName, 4]
        });
    }

    // RequestName answered: only a primary ownership (1) is the name; its owner is read next.
    // retire() drops a pending request, so no answer arrives here once offline.
    function registrationFinished(): void {
        if (!registration || !registration.isFinished) {
            return;
        }
        // The plugin's decoder returns a uint32 as a value wrapper, not a plain number, and an
        // error's text as its value: an error is no grant.
        const granted = registration.isValid && registration.value.value === 1;
        const finished = registration;
        registration = null;
        finished.destroy();
        if (!granted) {
            console.warn("plasmafusion-placement: layout provider: the identity name was not granted;"
                         + " nothing will be published this session");
            return;
        }
        identityLookup.arguments = [identityName];
        identityLookup.call();
    }

    // Only a unique connection name is an owner; nothing else is kept as one. The owner is set
    // before the flag, so whatever reacts to identityReady finds it.
    function ownerFound(owner: string): void {
        if (!online) {
            return;
        }
        const unique = owner.startsWith(":");
        selfOwner = unique ? owner : "";
        identityReady = unique;
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

    // The script is going: offline, with no capability or session left to report, and the
    // identity name released - a request still pending is dropped, so its answer reaches
    // nothing. Nothing moves after this.
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
        identityReady = false;
        selfOwner = "";
        if (registration) {
            const pending = registration;
            registration = null;
            pending.destroy();
        }
        identityRelease.arguments = [identityName];
        identityRelease.call();
        revision += 1;
    }
}
