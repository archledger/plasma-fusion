#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Characterize native tiling in a disposable container, not a production tiler."""

import configparser
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

home = Path.home()
out = Path(os.environ["OUT"])
runtime = Path(os.environ["XDG_RUNTIME_DIR"])
if not Path("/run/.containerenv").exists() or not str(runtime).startswith("/var/tmp/pfv-"):
    raise SystemExit("This probe requires a disposable tools/vsession container.")
if runtime.parent / "home" != home or out.parent != runtime.parent:
    raise SystemExit("Private HOME, OUT and runtime must belong to the same session.")

sys.path.insert(0, str(home / "pf-tools/tests/lib"))
from pfkwin import run  # noqa: E402

PRELUDE = """
var output = workspace.screens[0];
var desk = workspace.currentDesktopForScreen(output);
var root = workspace.rootTile(output, desk);
function tree(t) {
    var g = t.relativeGeometry;
    return {rect:[g.x,g.y,g.width,g.height], padding:t.padding,
            direction:t.layoutDirection, children:t.tiles.map(tree)};
}
function clients() {
    return workspace.windowList().filter(w => /^DT Gate [0-4]$/.test(w.caption))
        .sort((a,b) => a.caption.localeCompare(b.caption));
}
function frames() {
    return clients().map(w => ({name:w.caption,id:String(w.internalId),
        rect:[w.frameGeometry.x,w.frameGeometry.y,w.frameGeometry.width,w.frameGeometry.height],
        tiled:!!w.tile, output:w.output.name,
        tile:w.tile ? tree(w.tile) : null}));
}
function clear(t) { while(t.tiles.length) t.tiles[t.tiles.length-1].remove(); }
function baseline() {
    clear(root); root.padding=12;
    root.split(1);
    root.tiles[0].relativeGeometry={x:0,y:0,width:0.35,height:1};
    root.tiles[0].split(2);
    root.tiles[0].tiles[0].relativeGeometry={x:0,y:0,width:0.35,height:0.4};
}
function masterStack() {
    clear(root); root.padding=0;
    root.split(1);
    root.tiles[1].split(2);
    root.tiles[1].tiles[0].relativeGeometry={x:0.5,y:0,width:0.5,height:1/3};
    root.tiles[1].tiles[1].split(2);
    return [root.tiles[0]].concat(root.tiles[1].tiles);
}
"""


def command(body):
    return run(PRELUDE + body)


def save(name, value):
    (out / f"{name}.json").write_text(json.dumps(value, indent=2) + "\n")


def persisted_tiles():
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.optionxform = str
    config.read(home / ".config/kwinrc")
    return {section: dict(config[section]) for section in config.sections()
            if section == "Tiling" or section.startswith("Tiling][")}


def wait_for_save(predicate):
    end = time.monotonic() + 10
    while time.monotonic() < end:
        config = persisted_tiles()
        if predicate(config):
            return config
        time.sleep(0.1)
    raise AssertionError(f"Native tiling config did not settle: {config!r}")


def stop_private_kwin():
    # Never use an unscoped pkill: the compositor must be an ancestor on this private socket.
    pid = os.getppid()
    while pid > 1:
        process = Path(f"/proc/{pid}")
        if process.joinpath("comm").read_text().strip() == "kwin_wayland":
            # File capabilities can make /proc/PID/environ unreadable to the same UID.
            # Verify ownership, ancestry and the exact private socket without elevating rights.
            pidfd = os.pidfd_open(pid)
            try:
                assert process.stat().st_uid == os.getuid()
                args = process.joinpath("cmdline").read_bytes().split(b"\0")
                socket_index = args.index(b"--socket") + 1
                assert args[socket_index].decode() == runtime.parent.name
                details = {"signal": "SIGKILL", "pid": pid, "socket": runtime.parent.name}
                save("interruption-intent", details)
                signal.pidfd_send_signal(pidfd, signal.SIGKILL)
                save("interruption-sent", details)
            finally:
                os.close(pidfd)
            return
        status = process.joinpath("status").read_text().splitlines()
        pid = int(next(line.split()[1] for line in status if line.startswith("PPid:")))
    raise AssertionError("Private compositor was not found in the probe's ancestor chain")


def wait_for(body, predicate):
    end = time.monotonic() + 12
    while time.monotonic() < end:
        value = command(body)
        if predicate(value):
            return value
        time.sleep(0.15)
    raise AssertionError(f"Native state did not settle: {value!r}")


def main():
    processes = []
    checks = []

    def check(name, condition):
        checks.append({"name": name, "pass": bool(condition)})
        save("checks", checks)
        if not condition:
            raise AssertionError(name)

    expectation = home / "tiling-gate-expect.json"
    if expectation.exists():
        expected = json.loads(expectation.read_text())
        current = command("report(tree(root));")
        config = persisted_tiles()
        save("reopened", {"tree": current, "config": config})
        check("restart loaded the last saved temporary tree", current == expected["candidateTree"])
        acceptance = {"originalTreeSurvivesInterruption": current == expected["originalTree"],
                      "originalConfigSurvivesInterruption": config == expected["originalConfig"]}
        save("result", {"characterizationChecks": checks, "acceptance": acceptance,
                        "gatePassed": all(acceptance.values())})
        # Leave even this disposable HOME on its original fixture after recording the failure.
        command("baseline(); report(true);")
        wait_for_save(lambda saved: saved == expected["originalConfig"])
        return

    for i in range(5):
        path = out / f"window-{i}.qml"
        path.write_text(f'''import QtQuick
import QtQuick.Window
Window {{ title: "DT Gate {i}"; visible: true; width: 420; height: 300
    minimumWidth: 120; minimumHeight: 100
    Rectangle {{ anchors.fill: parent; color: "#345678" }}
}}
''')
        log = (out / f"window-{i}.log").open("w")
        processes.append(subprocess.Popen(["qml", str(path)], stdout=log, stderr=log))
        log.close()
    wait_for("report(frames());", lambda rows: len(rows) == 5)
    command("""
clients().forEach((w,i) => {
    if(w.tile) w.tile.unmanage(w);
    w.setMaximize(false,false);
    workspace.sendClientToScreen(w,output);
    w.frameGeometry={x:50+i*70,y:80+i*30,width:420,height:300};
});
baseline(); report(tree(root));
""")
    time.sleep(0.5)
    before = command("report({tree:tree(root),frames:frames()});")
    save("baseline", before)
    original_config = wait_for_save(lambda saved: bool(saved))
    # readSettings may have scheduled an initial default save; require the fixture's padding too.
    original_config = wait_for_save(lambda saved: any(v.get("padding") == "12" for v in saved.values()))
    save("baseline-config", original_config)
    check("five native fixture windows", len(before["frames"]) == 5)
    command("root.tiles[0].tiles[0].manage(clients()[4]); report(true);")
    wait_for("report(frames());", lambda rows: rows[4]["tiled"])
    manual = command("report({tree:tree(root),frames:frames()});")
    save("manual-member", manual)
    # This deliberately probes the temporary-tree approach, not an accepted implementation.
    # Leave the manual member untouched while the candidate replaces its tree.
    layout = command("""
var focus=String(workspace.activeWindow.internalId);
var leaves=masterStack();
var ok=leaves.map((t,i)=>t.manage(clients()[i]));
report({tree:tree(root),managed:ok,focusBefore:focus,
        focusAfter:String(workspace.activeWindow.internalId)});
""")
    save("candidate", layout)
    check("four native targets selected", len(layout["managed"]) == 4)
    check("native manage accepted four windows", all(layout["managed"]))
    check("native manage did not steal focus", layout["focusBefore"] == layout["focusAfter"])
    wait_for("report(frames());", lambda rows: all(row["tiled"] for row in rows[:4]))
    settled = command("report({tree:tree(root),frames:frames()});")
    save("candidate-settled", settled)
    rects = [row["tile"]["rect"] for row in settled["frames"][:4]]
    expected = [[0, 0, .5, 1], [.5, 0, .5, 1/3], [.5, 1/3, .5, 1/3], [.5, 2/3, .5, 1/3]]
    check("four distinct master-stack leaves", len(set(map(tuple, rects))) == 4 and all(
        all(abs(a-b) < 1e-6 for a, b in zip(actual, wanted))
        for actual, wanted in zip(rects, expected)
    ))
    acceptance = {"originalTreePreservedWhileEnabled": settled["tree"] == before["tree"],
                  "manualTilePreservedWhileEnabled": settled["frames"][4]["tile"] == manual["frames"][4]["tile"]}
    candidate_config = wait_for_save(lambda saved: saved != original_config)
    save("candidate-config", candidate_config)
    acceptance["originalConfigPreservedAfterScriptUnload"] = candidate_config == original_config
    # pfkwin.run unloads each script before it returns. The saved mutation has no script owner now.
    check("temporary tree remains after its creating script unloaded", command("report(tree(root));") == layout["tree"])
    command("clients().slice(0,4).forEach(w=>w.tile.unmanage(w)); report(true);")

    def floating_restored(rows):
        current = {row["id"]: row for row in rows}
        return all(old["id"] in current and not current[old["id"]]["tiled"] and all(
            abs(a-b) <= 2 for a, b in zip(old["rect"], current[old["id"]]["rect"])
        ) for old in before["frames"][:4])

    # Requested membership changes before a Wayland client commits its restored frame.
    restored = wait_for("report(frames());", floating_restored)
    save("unmanaged", restored)
    check("unmanage restores original floating frames", floating_restored(restored))
    command("if(clients()[4].tile) clients()[4].tile.unmanage(clients()[4]); baseline(); report(true);")
    check("fixture tree can be rebuilt normally", command("report(tree(root));") == before["tree"])
    wait_for_save(lambda saved: saved == original_config)
    save("result", {"characterizationChecks": checks, "acceptance": acceptance,
                    "gatePassed": all(acceptance.values())})
    if (home / "tiling-gate-crash").exists():
        candidate = command("masterStack(); report(tree(root));")
        wait_for_save(lambda saved: saved != original_config)
        expectation.write_text(json.dumps({"originalTree": before["tree"],
                                          "originalConfig": original_config,
                                          "candidateTree": candidate}, indent=2) + "\n")
        save("interruption", {"plannedSignal": "SIGKILL", "target": "ancestor private kwin_wayland",
                              "savedTemporaryTree": candidate})
        stop_private_kwin()
        raise SystemExit("Private compositor stopped; reopen the same disposable HOME next")
    for process in processes:
        process.terminate()
    for process in processes:
        process.wait(timeout=5)


if __name__ == "__main__":
    main()
