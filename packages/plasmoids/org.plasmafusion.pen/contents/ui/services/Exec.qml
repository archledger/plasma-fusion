// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Runs short helper commands (kwriteconfig6, kstart, spectacle). Applications are started with
// kstart --application, which hands them to their own systemd scope, never as a child of plasmashell
// (PEN.md 3.3: an executable-engine child dies with plasmashell).
Item {
    id: exec

    signal finished(string command, int exitCode, string stdout)

    function run(command: string) {
        source.connectSource(command);
    }

    P5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            exec.finished(sourceName, Number(data["exit code"]), String(data["stdout"] || ""));
            disconnectSource(sourceName);
        }
    }
}
