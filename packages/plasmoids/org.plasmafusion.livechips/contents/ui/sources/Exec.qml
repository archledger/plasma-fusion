// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Runs a short helper command (pw-dump, for the apps reading a camera). Each call is a source of
// its own, "COMMAND #N" (a shell comment: the executable engine runs it through sh -c): the engine
// runs a source once while it is connected, so an identical command started before the previous
// one had finished would be dropped. The same as quick settings' and the pen menu's
// services/Exec.qml (tests/exec_test.py in quick settings).
Item {
    id: exec

    // The command as given to run(), its exit code and output.
    signal finished(string command, int exitCode, string stdout)

    property int serial: 0
    // source -> {command, handler}
    property var pending: ({})

    // handler(exitCode, stdout), optional, is called once when this run has finished.
    function run(command: string, handler): void {
        const name = command + " #" + (++serial);
        pending[name] = { "command": command, "handler": handler || null };
        source.connectSource(name);
    }

    P5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            const job = exec.pending[sourceName];
            delete exec.pending[sourceName];
            disconnectSource(sourceName);
            const code = Number(data["exit code"]);
            const out = String(data["stdout"] || "");
            if (job && job.handler) {
                job.handler(code, out);
            }
            exec.finished(job ? job.command : sourceName, code, out);
        }
    }
}
