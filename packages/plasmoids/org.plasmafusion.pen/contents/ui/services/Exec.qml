// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Runs short helper commands (kwriteconfig6, kstart, spectacle). Each call is a source of its own,
// "COMMAND #N" (a shell comment: the executable engine runs it through sh -c): the engine runs a
// source once while it is connected, so an identical command started before the previous one had
// finished was dropped, and a second handler took the place of the first. The same as quick
// settings' services/Exec.qml (tests/exec_test.py there).
// Applications are started with kstart --application, which hands them to their own systemd scope,
// never as a child of plasmashell (PEN.md 3.3: an executable-engine child dies with plasmashell).
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
