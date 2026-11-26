#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Passive portal status through real Workspace D-Bus QML on a private bus.

The mock exports only cached manager reads and typed change signals. Every method is counted, so
a connectivity probe, a write or a hidden-page read fails the test. GLib serves the mock while Qt
serves QML; one thread pumps both explicitly, making delayed replies deterministic.

QT_QPA_PLATFORM=offscreen dbus-run-session --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
    python3 packages/plasmoids/org.plasmafusion.quicksettings/tests/portal_status_test.py
"""

import os
from pathlib import Path
import sys
import tempfile
import time

import dbus
import dbus.lowlevel
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
from PySide6.QtCore import QCoreApplication, QEvent, QObject, QUrl, Slot, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest


MANAGER = "org.freedesktop.NetworkManager"
MANAGER_PATH = "/org/freedesktop/NetworkManager"
PROPERTIES = "org.freedesktop.DBus.Properties"
DAEMON = "org.freedesktop.DBus"
DAEMON_PATH = "/org/freedesktop/DBus"
SOURCE = Path(__file__).resolve().parent.parent / "contents/ui/services/PortalStatus.qml"
checks = 0
messages = []


def record_message(kind, context, text):
    messages.append(text)


class Context(QObject):
    @Slot(str, str, result=str)
    def i18nc(self, context, text):
        return text


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message, flush=True)


def pump(milliseconds=20):
    # qWait spins Qt; a nonblocking GLib iteration then delivers the mock's method returns/signals.
    deadline = time.monotonic() + milliseconds / 1000
    context = GLib.main_context_default()
    while time.monotonic() < deadline:
        QTest.qWait(5)
        while context.iteration(False):
            pass


def portal_values(connectivity=2):
    return {"Connectivity": dbus.UInt32(connectivity),
            "ConnectivityCheckAvailable": dbus.Boolean(True),
            "ConnectivityCheckEnabled": dbus.Boolean(True)}


class Manager(dbus.service.Object):
    def __init__(self, connection):
        super().__init__(connection, MANAGER_PATH)
        self.values = portal_values(4)
        self.delay = 0
        self.fail = False
        self.calls = {"GetAll": 0, "CheckConnectivity": 0, "Set": 0}
        self.replies = 0
        self.errors = 0
        self.hold = False
        self.held_reply = None
        self.read_destinations = []
        self.reply_connectivity = []

    @dbus.service.method(PROPERTIES, in_signature="s", out_signature="a{sv}",
                         async_callbacks=("ok", "err"), message_keyword="message")
    def GetAll(self, interface, ok, err, message):
        self.calls["GetAll"] += 1
        self.read_destinations.append(message.get_destination())
        if self.fail:
            self.errors += 1
            err(dbus.exceptions.DBusException("fixture read failure", name="org.freedesktop.DBus.Error.Failed"))
            return
        snapshot = dict(self.values)

        def send_reply():
            self.replies += 1
            self.reply_connectivity.append(snapshot.get("Connectivity"))
            ok(snapshot)

        if self.hold:
            assert self.held_reply is None
            self.held_reply = send_reply
        elif self.delay == 0:
            send_reply()
        else:
            GLib.timeout_add(self.delay, lambda: send_reply() and False)

    def release_held_reply(self):
        reply = self.held_reply
        assert reply is not None
        self.held_reply = None
        self.hold = False
        reply()

    @dbus.service.signal(PROPERTIES, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    @dbus.service.method(PROPERTIES, in_signature="ssv")
    def Set(self, interface, key, value):
        self.calls["Set"] += 1
        raise dbus.exceptions.DBusException("read-only fixture", name="org.freedesktop.DBus.Error.PropertyReadOnly")

    @dbus.service.method(MANAGER, out_signature="u")
    def CheckConnectivity(self):
        self.calls["CheckConnectivity"] += 1
        return self.values["Connectivity"]

    def changed(self, values=None, invalidated=()):
        changed = dbus.Dictionary(values or {}, signature="sv")
        self.PropertiesChanged(MANAGER, changed, list(invalidated))

    def set(self, connectivity=2):
        self.values = portal_values(connectivity)
        self.changed(self.values)


class Owner:
    def __init__(self, app, address, name, connectivity=4, delay=0):
        self.name = name
        self.registered = False
        self.connection = dbus.bus.BusConnection(address)
        self.bus_name = dbus.service.BusName(MANAGER, self.connection, do_not_queue=True)
        self.virtual = Manager(self.connection)
        self.virtual.values = portal_values(connectivity)
        self.virtual.delay = delay
        pump(30)
        check(self.connection.name_has_owner(MANAGER), f"{name} owns NetworkManager on the private bus")
        self.unique = self.connection.get_unique_name()
        check(self.unique.startswith(":"), f"{name} has a unique D-Bus identity")
        self.registered = True

    def set(self, connectivity=2):
        self.virtual.set(connectivity)

    def changed(self, values=None, invalidated=()):
        self.virtual.changed(values, invalidated)

    def release(self):
        self.connection.release_name(MANAGER)
        self.virtual.remove_from_connection()
        self.registered = False
        pump(20)
        check(not self.connection.name_has_owner(MANAGER), f"{self.name} released NetworkManager")


def observe_owner_traffic(address, owner_traffic):
    monitor = dbus.bus.BusConnection(address)

    def record(_connection, message):
        if message.get_type() != dbus.lowlevel.MESSAGE_TYPE_METHOD_CALL:
            return
        args = message.get_args_list()
        if message.get_member() == "GetNameOwner" and args == [MANAGER]:
            owner_traffic.append((message.get_sender(), "lookup"))
        elif message.get_member() == "AddMatch" and args and f"path='{DAEMON_PATH}'" in args[0]:
            owner_traffic.append((message.get_sender(), "watch"))

    monitor.add_message_filter(record)
    rules = [f"type='method_call',interface='{DAEMON}',member='{member}'"
             for member in ("AddMatch", "GetNameOwner")]
    monitor.call_blocking(DAEMON, DAEMON_PATH, DAEMON + ".Monitoring", "BecomeMonitor",
                          "asu", (rules, dbus.UInt32(0)))
    return monitor


def main():
    global checks
    if "DBUS_SESSION_BUS_ADDRESS" not in os.environ:
        raise SystemExit("Run with dbus-run-session and an isolated session bus")
    DBusGMainLoop(set_as_default=True)
    with tempfile.TemporaryDirectory(prefix="pf-portal-status-") as home:
        os.environ.update(HOME=home, XDG_CONFIG_HOME=home, QT_QUICK_BACKEND="software")
        address = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        if not address.startswith("unix:"):
            raise SystemExit("The test requires a private Unix session bus")
        os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = address
        owner_traffic = []
        monitor = observe_owner_traffic(address, owner_traffic)
        app = QGuiApplication(sys.argv[:1])
        qInstallMessageHandler(record_message)
        engine = QQmlEngine()
        context = Context()
        engine.rootContext().setContextObject(context)
        component = QQmlComponent(engine, QUrl.fromLocalFile(str(SOURCE)))
        component.create()
        check(component.status() == QQmlComponent.Ready and not component.errors(),
              "the passive portal component loads (%s)" % "; ".join(e.toString() for e in component.errors()))
        roots = []
        owners = []

        def make(visible=True):
            root = component.createWithInitialProperties({"listVisible": visible})
            check(root is not None, "create a portal status view")
            roots.append(root)
            return root

        def wait_for(predicate, message, milliseconds=3000):
            deadline = time.monotonic() + milliseconds / 1000
            while time.monotonic() < deadline:
                pump(20)
                if predicate():
                    return
            raise AssertionError(message + "\nQt messages:\n" + "\n".join(messages[-40:]))

        def state(root, expected, message):
            wait_for(lambda: root.property("captivePortal") is expected,
                     f"{message}: expected captivePortal={expected}")
            check(root.property("captivePortal") is expected, message)

        def settle(milliseconds=80):
            pump(milliseconds)

        def no_probe(owner, before):
            settle(180)
            check(owner.virtual.calls["CheckConnectivity"] == 0, "the lifecycle made no CheckConnectivity call")
            check(owner.virtual.calls["Set"] == 0, "the lifecycle made no connectivity-policy write")
            check(owner.virtual.calls["GetAll"] == before, "no periodic polling followed the event-driven read")

        try:
            root = make(False)
            settle()
            check(not root.property("captivePortal"), "a hidden page with no owner is unknown")
            owner = Owner(app, address, "a", connectivity=2)
            owners.append(owner)
            state(root, False, "a new owner does not affect a hidden page")
            check(owner.virtual.calls["GetAll"] == 0, "a hidden page performs no cached reads")

            traffic_before = len(owner_traffic)
            root.setProperty("listVisible", True)
            state(root, True, "initial cached portal state is shown")
            traffic = owner_traffic[traffic_before:]
            check(len(traffic) >= 2 and traffic[0][0] == traffic[1][0]
                  and [action for _, action in traffic[:2]] == ["watch", "lookup"],
                  f"the owner watcher is registered before the lookup on the same bus: {traffic}")
            before = owner.virtual.calls["GetAll"]
            no_probe(owner, before)

            owner.set(4)
            state(root, False, "Full clears the note")
            for label, connectivity in (("Unknown", 0), ("None", 1), ("Limited", 3), ("Full", 4)):
                owner.set(2)
                state(root, True, "restore portal before " + label)
                owner.set(connectivity)
                state(root, False, label + " is not presented as a portal")
            owner.set(2)
            state(root, True, "restore portal before checking disabled checks")
            owner.values = portal_values(2)
            owner.values["ConnectivityCheckEnabled"] = dbus.Boolean(False)
            owner.changed(owner.values)
            state(root, False, "disabled checks hide the note")
            owner.set(2)
            state(root, True, "restore portal before checking unavailable checks")
            owner.values = portal_values(2)
            owner.values["ConnectivityCheckAvailable"] = dbus.Boolean(False)
            owner.changed(owner.values)
            state(root, False, "unavailable checks hide the note")
            owner.set(2)
            state(root, True, "restore portal before invalidation")
            owner.virtual.values.pop("Connectivity")
            owner.changed({}, ["Connectivity"])
            state(root, False, "an invalidated connectivity value hides the note")
            for malformed in (dbus.String("2"), dbus.Int32(2), dbus.Double(2.0)):
                label = type(malformed).__name__
                owner.set(2)
                state(root, True, f"restore portal before Connectivity as {label}")
                owner.changed({"Connectivity": malformed})
                state(root, False, f"Connectivity as {label} is rejected despite valid capability flags")
            for gate in ("ConnectivityCheckAvailable", "ConnectivityCheckEnabled"):
                for malformed in (dbus.String("true"), dbus.UInt32(1)):
                    label = f"{gate} as {type(malformed).__name__}"
                    owner.set(2)
                    state(root, True, f"restore portal before malformed {label}")
                    owner.virtual.values[gate] = malformed
                    owner.changed({gate: malformed})
                    state(root, False, f"live {label} is rejected with valid Portal connectivity")

                    before = owner.virtual.replies
                    root.setProperty("listVisible", False)
                    root.setProperty("listVisible", True)
                    wait_for(lambda: owner.virtual.replies > before, f"snapshot with malformed {label} arrived")
                    settle()
                    check(not root.property("captivePortal"),
                          f"snapshot {label} is rejected with valid Portal connectivity")
            owner.set(2)
            state(root, True, "restore portal before a fractional value")
            owner.virtual.values = portal_values(2)
            owner.virtual.values["Connectivity"] = dbus.Double(2.5)
            reply_before = owner.virtual.replies
            root.setProperty("listVisible", False)
            root.setProperty("listVisible", True)
            wait_for(lambda: owner.virtual.replies > reply_before, "the fractional snapshot arrived")
            settle()
            state(root, False, "a fractional connectivity snapshot is rejected")
            owner.set(2)
            state(root, True, "restore portal before an incomplete snapshot")
            owner.virtual.values = {"Connectivity": dbus.UInt32(2)}
            reply_before = owner.virtual.replies
            root.setProperty("listVisible", False)
            root.setProperty("listVisible", True)
            wait_for(lambda: owner.virtual.replies > reply_before, "the incomplete snapshot arrived")
            settle()
            state(root, False, "a snapshot without both gates is incomplete")
            owner.virtual.values = portal_values(2)
            root.setProperty("listVisible", False)
            root.setProperty("listVisible", True)
            state(root, True, "reopening obtains a complete current snapshot")

            # A connectivity-only update retires an older GetAll while the gates are still unknown.
            # A fresh snapshot must follow; the late old Portal reply cannot roll the page back.
            owner.virtual.delay = 250
            before = owner.virtual.calls["GetAll"]
            reply_before = owner.virtual.replies
            root.setProperty("listVisible", False)
            root.setProperty("listVisible", True)
            wait_for(lambda: owner.virtual.calls["GetAll"] > before, "a delayed snapshot was actually requested")
            owner.virtual.delay = 0
            owner.virtual.values = portal_values(4)
            owner.changed({"Connectivity": dbus.UInt32(4)})
            state(root, False, "a connectivity-only Full update takes effect immediately")
            wait_for(lambda: owner.virtual.replies >= reply_before + 2, "fresh and delayed snapshots were delivered")
            settle()
            check(owner.virtual.reply_connectivity[reply_before:] == [4, 2],
                  "the newer Full snapshot was followed by a frozen stale Portal snapshot")
            check(root.property("captivePortal") is False,
                  "a delayed Portal snapshot cannot overwrite a newer live Full result")
            check(owner.virtual.calls["GetAll"] >= before + 2,
                  "the incomplete live update obtained a fresh complete snapshot")
            owner.virtual.values = portal_values(2)
            owner.changed({"Connectivity": dbus.UInt32(2)})
            state(root, True, "a later connectivity-only Portal update is accepted without another full signal")
            settled_reads = owner.virtual.calls["GetAll"]
            settle(150)
            check(owner.virtual.calls["GetAll"] == settled_reads,
                  "known gate flags are retained without another cached read")

            # Closing clears at once, suppresses new reads, and fences callbacks on reopening.
            root.setProperty("listVisible", False)
            check(root.property("captivePortal") is False, "closing the page clears the note synchronously")
            owner.virtual.hold = True
            root.setProperty("listVisible", True)
            wait_for(lambda: owner.virtual.held_reply is not None, "the page's Portal reply is held")
            root.setProperty("listVisible", False)
            before = owner.virtual.calls["GetAll"]
            owner.changed(portal_values(2))
            owner.virtual.release_held_reply()
            settle()
            check(owner.virtual.calls["GetAll"] == before and not root.property("captivePortal"),
                   "a hidden page ignores signals and delayed replies without polling")
            owner.virtual.values = portal_values(4)
            reply_before = owner.virtual.replies
            root.setProperty("listVisible", True)
            wait_for(lambda: owner.virtual.replies > reply_before, "the reopened page's Full snapshot arrived")
            settle()
            state(root, False, "reopening does not revive the previous portal snapshot")
            owner.set(2)
            state(root, True, "the reopened page follows the current owner")

            # Losing the owner invalidates the previous snapshot and any still-running reply.
            owner.virtual.delay = 250
            before = owner.virtual.calls["GetAll"]
            root.setProperty("listVisible", False)
            root.setProperty("listVisible", True)
            wait_for(lambda: owner.virtual.calls["GetAll"] > before, "old owner snapshot was dispatched")
            check(set(owner.virtual.read_destinations) == {owner.unique},
                  "every cached snapshot is addressed to the resolved original owner")
            owner.release()
            state(root, False, "owner loss clears the note")
            replacement = Owner(app, address, "b", connectivity=4)
            owners.append(replacement)
            wait_for(lambda: replacement.virtual.replies > 0, "replacement cached snapshot arrived")
            check(set(replacement.virtual.read_destinations) == {replacement.unique},
                  "replacement snapshots are addressed to the new unique owner")
            state(root, False, "the replacement owner is read without assuming the old portal result")
            settle(300)
            check(root.property("captivePortal") is False, "the old owner's delayed portal reply cannot revive the note")
            retired_signal = dbus.lowlevel.SignalMessage(MANAGER_PATH, PROPERTIES, "PropertiesChanged")
            retired_signal.append(MANAGER, portal_values(), [], signature="sa{sv}as")
            owner.connection.send_message(retired_signal)
            owner.connection.flush()
            settle()
            check(not root.property("captivePortal"), "a signal from the retired owner cannot revive the note")
            replacement.set(2)
            state(root, True, "the replacement's current portal update is shown")
            replacement.release()

            # A -> B -> C: B's pending Portal answer must not defeat C's later Full snapshot.
            third = Owner(app, address, "c", connectivity=2, delay=250)
            owners.append(third)
            root.setProperty("listVisible", False)
            root.setProperty("listVisible", True)
            wait_for(lambda: third.virtual.calls["GetAll"] > 0, "middle owner's delayed read was requested")
            third.release()
            state(root, False, "a rapid owner loss clears the note")
            fourth = Owner(app, address, "d", connectivity=4)
            owners.append(fourth)
            state(root, False, "the final replacement reports its own Full state")
            wait_for(lambda: third.virtual.replies > 0, "middle owner's delayed reply arrived")
            settle()
            check(root.property("captivePortal") is False, "a middle owner's delayed Portal reply is rejected")
            check(fourth.virtual.calls["GetAll"] > 0, "the final owner was actually read")

            # Read errors fail closed, without retry loops or checks.
            root.setProperty("listVisible", False)
            fourth.virtual.fail = True
            errors_before = fourth.virtual.errors
            root.setProperty("listVisible", True)
            wait_for(lambda: fourth.virtual.errors > errors_before, "the read returned an explicit error")
            state(root, False, "a failed property read leaves no note")
            before = fourth.virtual.calls["GetAll"]
            settle(250)
            check(fourth.virtual.calls["GetAll"] == before, "a failed read does not start a polling loop")
            root.setProperty("listVisible", False)
            fourth.virtual.fail = False
            fourth.virtual.values = portal_values(2)
            root.setProperty("listVisible", True)
            state(root, True, "reopening after a read error can show a valid Portal snapshot")
            fourth.release()

            # Delete a view while a read is outstanding. The independent lifetime token prevents
            # the late callback from dereferencing the destroyed QML object.
            root.setProperty("listVisible", False)
            pending = Owner(app, address, "pending", connectivity=2)
            owners.append(pending)
            pending.virtual.hold = True
            doomed = make(False)
            doomed.setProperty("listVisible", True)
            wait_for(lambda: pending.virtual.held_reply is not None, "the doomed view's request is held")
            destroyed = []
            doomed.destroyed.connect(lambda: destroyed.append(True))
            doomed.deleteLater()
            QCoreApplication.sendPostedEvents(doomed, QEvent.DeferredDelete)
            roots.remove(doomed)
            check(destroyed == [True], "the requesting QML view was destroyed before its reply")
            pending.virtual.release_held_reply()
            settle()
            errors = [m for m in messages if "TypeError" in m or "ReferenceError" in m]
            check(not errors, "a callback after QML destruction raises no TypeError (%s)" % errors)
            check(all(item.virtual.calls["CheckConnectivity"] == 0 and item.virtual.calls["Set"] == 0
                      for item in owners), "all owners saw zero connectivity probes and zero writes")

            # Exhausting the request number retires the reader permanently: neither reopening nor
            # an owner change may wrap it or start another asynchronous read.
            root.setProperty("generation", root.property("generationLimit") - 1)
            root.setProperty("listVisible", False)
            root.setProperty("listVisible", True)
            before = pending.virtual.calls["GetAll"]
            pending.changed({"Connectivity": dbus.UInt32(2)})
            settle(100)
            check(pending.virtual.calls["GetAll"] == before and not root.property("captivePortal"),
                  "a live update cannot restart an exhausted request generation")
            pending.release()
            settle(150)
            check(root.property("generation") == root.property("generationLimit")
                  and pending.virtual.calls["GetAll"] == before,
                  "an exhausted request generation never wraps or restarts on owner loss")
        finally:
            for root in roots:
                root.setProperty("listVisible", False)
                root.deleteLater()
            pump(30)
            for item in owners:
                if item.registered:
                    item.connection.release_name(MANAGER)
                    item.virtual.remove_from_connection()
            pump(30)
            monitor.close()
    print(f"Passive portal status: {checks} checks, 0 failures", flush=True)


if __name__ == "__main__":
    main()
