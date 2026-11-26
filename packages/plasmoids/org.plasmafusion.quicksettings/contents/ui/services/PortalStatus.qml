// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound
pragma ValueTypeBehavior: Addressable

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// NetworkManager publishes one cached, aggregate result for its last completed check. It is not
// evidence about a particular Wi-Fi activation or a destination to open. Read it only while the
// Wi-Fi page is shown: never call CheckConnectivity and never create another NetworkStatus (whose
// constructor requests a check). The manager's unique owner and request number invalidate a prior
// view before a new snapshot can be considered.
Item {
    id: status

    property bool listVisible: false
    readonly property bool captivePortal: portalState.present
    readonly property string portalNotice: captivePortal ? i18nc("@info:status",
        "The last connectivity check reported a possible network sign-in. "
        + "If your browser offers a network sign-in page, use that prompt or choose another network.") : ""

    property bool initialized: false
    onListVisibleChanged: {
        if (initialized) {
            reset();
        }
    }
    Component.onCompleted: {
        initialized = true;
        reset();
    }
    Component.onDestruction: {
        life.alive = false;
        ++generation;
    }

    readonly property int generationLimit: 1073741823
    property int generation: 0
    // QObject identity is stable in QML; the independent token can be checked by a reply after the
    // rest of this component has been destroyed.
    readonly property var life: QtObject { property bool alive: true }

    readonly property var portalState: QtObject {
        property string owner: ""
        property QtObject watcher: null
        property bool present: false
        property var connectivity: null
        property bool checkAvailable: false
        property bool checkEnabled: false
        property bool connectivityKnown: false
        property bool availableKnown: false
        property bool enabledKnown: false
        readonly property bool complete: connectivityKnown && availableKnown && enabledKnown
        function clear() {
            present = false;
            connectivity = null;
            checkAvailable = false;
            checkEnabled = false;
            connectivityKnown = false;
            availableKnown = false;
            enabledKnown = false;
        }
        function assign(properties: var): void {
            // A live change carries only the changed keys. Keep fields that an earlier complete
            // snapshot established; snapshots call clear() first so no stale field survives.
            const hasConnectivity = Object.prototype.hasOwnProperty.call(properties, "Connectivity");
            const hasAvailable = Object.prototype.hasOwnProperty.call(properties, "ConnectivityCheckAvailable");
            const hasEnabled = Object.prototype.hasOwnProperty.call(properties, "ConnectivityCheckEnabled");
            connectivityKnown = connectivityKnown || hasConnectivity;
            availableKnown = availableKnown || hasAvailable;
            enabledKnown = enabledKnown || hasEnabled;
            connectivity = hasConnectivity ? properties.Connectivity : connectivity;
            // Check the wire values before QML coerces them into these bool properties.
            if (hasAvailable) {
                checkAvailable = properties.ConnectivityCheckAvailable === true;
            }
            if (hasEnabled) {
                checkEnabled = properties.ConnectivityCheckEnabled === true;
            }
        }
        function evaluatePresent(): void {
            present = complete && checkAvailable && checkEnabled
                && connectivity instanceof DBus.uint32 && connectivity.value === 2;
        }
    }

    function nextGeneration(): int {
        const current = generation;
        // Retire this unknown state rather than wrapping into a still-valid request number.
        generation = current >= generationLimit ? generationLimit : current + 1;
        return generation;
    }

    function clearOwner(): void {
        const watcher = portalState.watcher;
        portalState.watcher = null;
        portalState.owner = "";
        portalState.clear();
        if (watcher) {
            watcher.destroy();
        }
    }

    function reset(): void {
        const number = nextGeneration();
        clearOwner();
        // Register for owner changes before asking for the current owner on the same bus.
        ownerSignals.enabled = listVisible && number < generationLimit;
        if (!ownerSignals.enabled) {
            return;
        }
        // The well-known address cannot identify data across a NetworkManager restart. Look up
        // its current unique owner first, before reading any connectivity properties.
        const current = life;
        DBus.SystemBus.asyncCall({
            service: "org.freedesktop.DBus",
            path: "/org/freedesktop/DBus",
            iface: "org.freedesktop.DBus",
            member: "GetNameOwner",
            arguments: [new DBus.string("org.freedesktop.NetworkManager")],
            signature: "(s)"
        }, reply => {
            if (current.alive && number === generation) {
                nameOwnerChanged("org.freedesktop.NetworkManager", "", uniqueName(reply.value));
            }
        }, _error => {
            // A missing owner remains unknown. There is no probe or retry timer.
            if (current.alive && number === generation) {
                portalState.clear();
            }
        });
    }

    function stringValue(value: var): string {
        // Workspace wraps D-Bus strings to preserve their wire type.
        return typeof value === "string" ? value
            : value !== null && value !== undefined && typeof value.value === "string" ? value.value : "";
    }

    function uniqueName(name: var): string {
        const text = stringValue(name);
        return /^:[A-Za-z0-9_.-]+$/.test(text) ? text : "";
    }

    function accept(generationNumber: int, owner: string): bool {
        return life.alive && listVisible && generationNumber > 0 && generationNumber < generationLimit
            && generationNumber === generation && owner !== "" && portalState.owner === owner;
    }

    function nameOwnerChanged(name: var, oldOwner: var, newOwner: var): void {
        if (stringValue(name) !== "org.freedesktop.NetworkManager") {
            return;
        }
        const number = nextGeneration();
        clearOwner();
        if (!listVisible || number >= generationLimit) {
            return;
        }
        const nextOwner = uniqueName(newOwner);
        if (nextOwner === "") {
            return;
        }
        const watcher = managerSignals.createObject(status, {ownerName: nextOwner});
        if (!watcher) {
            return;
        }
        portalState.owner = nextOwner;
        portalState.watcher = watcher;
        readProperties(number);
    }

    function readProperties(number: int): void {
        if (number >= generationLimit) {
            return;
        }
        if (!life.alive || !listVisible || !accept(number, portalState.owner)) {
            return;
        }
        const current = life;
        const owner = portalState.owner;
        DBus.SystemBus.asyncCall({
            service: owner,
            path: "/org/freedesktop/NetworkManager",
            iface: "org.freedesktop.DBus.Properties",
            member: "GetAll",
            arguments: [new DBus.string("org.freedesktop.NetworkManager")],
            signature: "(s)"
        }, reply => {
            if (!current.alive || !accept(number, owner)) {
                return;
            }
            applySnapshot(reply.value);
        }, _error => {
            if (current.alive && accept(number, owner)) {
                portalState.clear();
            }
        });
    }

    function applySnapshot(properties: var): void {
        if (!life.alive || !listVisible || portalState.owner === "") {
            return;
        }
        if (properties === null || typeof properties !== "object") {
            portalState.clear();
            return;
        }
        portalState.clear();
        portalState.assign(properties);
        portalState.evaluatePresent();
    }

    function relevantProperty(key: string): bool {
        return key === "Connectivity" || key === "ConnectivityCheckAvailable"
            || key === "ConnectivityCheckEnabled";
    }

    function propertiesChanged(interfaceName: var, changedProperties: var, invalidatedProperties: var): void {
        if (!life.alive || !listVisible || portalState.owner === ""
                || stringValue(interfaceName) !== "org.freedesktop.NetworkManager") {
            return;
        }
        const changed = changedProperties !== null && typeof changedProperties === "object"
            ? changedProperties : null;
        // Workspace's QVariantList is not always a JavaScript Array. Read its numeric shape rather
        // than requiring Array.isArray, which would silently skip every invalidated property.
        const count = invalidatedProperties ? invalidatedProperties.length : 0;
        let invalidated = false;
        for (let i = 0; i < count; ++i) {
            if (relevantProperty(stringValue(invalidatedProperties[i]))) {
                invalidated = true;
            }
        }
        let updates = false;
        if (changed) {
            for (const key of ["Connectivity", "ConnectivityCheckAvailable", "ConnectivityCheckEnabled"]) {
                if (Object.prototype.hasOwnProperty.call(changed, key)) {
                    updates = true;
                }
            }
        }
        if (!invalidated && !updates) {
            return;
        }
        // A live change is newer than any GetAll already waiting. Retire that reply before taking
        // this state, so a delayed older snapshot cannot undo the current manager's answer.
        nextGeneration();
        if (generation >= generationLimit) {
            clearOwner();
            return;
        }
        if (invalidated || !changed) {
            portalState.clear();
            // Invalidation alone does not prove that the property is gone. One event-driven fresh
            // read either restores a complete current snapshot or confirms that it is still missing.
            readProperties(generation);
            return;
        }
        portalState.assign(changed);
        portalState.evaluatePresent();
        // NetworkManager normally sends only the changed keys. If this update arrived before the
        // first full snapshot, the capability flags are still unknown. The retired reply cannot be
        // used, so take a fresh snapshot instead of leaving the note stuck hidden.
        if (!portalState.complete) {
            readProperties(generation);
        }
    }

    DBus.SignalWatcher {
        id: ownerSignals
        enabled: false
        busType: DBus.BusType.System
        service: "org.freedesktop.DBus"
        path: "/org/freedesktop/DBus"
        iface: "org.freedesktop.DBus"
        function dbusNameOwnerChanged(name: var, previous: var, current: var): void {
            status.nameOwnerChanged(name, previous, current);
        }
        function dbusNameAcquired(_name: var): void {}
        function dbusNameLost(_name: var): void {}
        function dbusActivatableServicesChanged(): void {}
    }

    Component {
        id: managerSignals
        DBus.SignalWatcher {
            id: watcher
            required property string ownerName
            busType: DBus.BusType.System
            service: ownerName
            path: "/org/freedesktop/NetworkManager"
            iface: "org.freedesktop.DBus.Properties"
            function dbusPropertiesChanged(interfaceName: var, changedProperties: var, invalidatedProperties: var): void {
                // Qt can still deliver a queued signal to the retiring watcher.
                if (status.portalState.watcher === watcher) {
                    status.propertiesChanged(interfaceName, changedProperties, invalidatedProperties);
                }
            }
        }
    }
}
