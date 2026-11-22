// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in (test use only) for the session bus of org.kde.plasma.workspace.dbus
// (plasma-workspace 6.8.3, components/dbus): asyncCall records the message and returns a pending
// reply shaped as DBusPendingReply is - isFinished, isError, isValid, error, value, values and
// finished() - which only the test answers (answer()). Nothing is sent anywhere.
pragma Singleton
import QtQuick

QtObject {
    id: bus

    // Every call, oldest first: { message, reply }. One engine runs every scenario, so a test
    // picks its own calls by their arguments.
    property var calls: []

    readonly property Component replyType: Component {
        QtObject {
            // As DBusPendingReply: valid until it finishes as anything but a reply.
            property bool isFinished: false
            property bool isError: false
            property bool isValid: true
            property var error: ({ isValid: false, message: "", name: "" })
            property var value: undefined
            property var values: []
            signal finished()
        }
    }

    // The plugin's two forms: a reply to watch, or callbacks (resolve for a reply, reject
    // otherwise, each given the reply once).
    function asyncCall(message, resolve, reject) {
        const reply = replyType.createObject(bus);
        calls = calls.concat([{ message: message, reply: reply }]);
        if (resolve !== undefined || reject !== undefined) {
            const settle = () => {
                reply.finished.disconnect(settle);
                const callback = reply.isValid ? resolve : reject;
                if (typeof callback === "function") {
                    callback(reply);
                }
            };
            reply.finished.connect(settle);
        }
        return reply;
    }

    // Finishes a pending reply as the bus would: with these return values (the first is
    // `value`; a uint32 comes as the plugin's wrapper, { value: n }), or with an error, whose
    // text the plugin decodes as the reply's one value. A reply the caller destroyed in the
    // meantime cannot be answered.
    function answer(reply, values, errorName) {
        if (!reply || reply.isFinished) {
            return false;
        }
        reply.isFinished = true;
        reply.isError = !!errorName;
        reply.isValid = !errorName;
        reply.values = errorName ? [String(errorName)] : (values || []);
        reply.value = reply.values.length > 0 ? reply.values[0] : undefined;
        if (errorName) {
            reply.error = { isValid: true, message: String(errorName), name: String(errorName) };
        }
        reply.finished();
        return true;
    }
}
