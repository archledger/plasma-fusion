#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stop only the probe's recorded shell; qualify cleanup separately from functionality."""

import argparse
import json
import os
import re
import select
import signal
import subprocess
import time
from pathlib import Path

if __package__:
    from .lifecycle import owner_of, qdbus, require_container
else:
    from lifecycle import owner_of, qdbus, require_container

RECORDS = {
    "cleanup-identity.json", "cleanup-request.json", "cleanup-stopped.json", "cleanup-result.json",
}
PRIVATE_ROOT = re.compile(r"/var/tmp/pfv-layout-control-[A-Za-z0-9-]+")
OWNER = re.compile(r":[0-9]+\.[0-9]+")
FATAL = re.compile(
    r"\bAborted\b|Segmentation fault|\bSIGSEGV\b|\bSIGABRT\b|KCrash:|"
    r'assertion .*failed|ASSERT(?: failure|:)',
    re.IGNORECASE,
)


def _require(condition: bool, reason: str) -> None:
    if not condition:
        raise ValueError("cleanup: " + reason)


def _integer(value, minimum: int, maximum: int) -> bool:
    return type(value) is int and minimum <= value <= maximum


def _schema(value) -> None:
    _require(isinstance(value, dict) and type(value.get("schema")) is int
             and value["schema"] == 1, "invalid record schema")


def _read_json(path: Path) -> dict:
    _require(path.is_file() and not path.is_symlink(), "missing/nonregular record " + path.name)
    with path.open(encoding="utf-8") as source:
        text = source.read(16385)
    _require(len(text) <= 16384, "oversized record " + path.name)
    return json.loads(text)


def read_record(root: Path, name: str) -> dict:
    _require(name in RECORDS, "unknown record")
    return _read_json(root / "out" / name)


def write_record(root: Path, name: str, value: dict) -> None:
    _require(name in RECORDS, "unknown record")
    # A second invocation must not turn a saved identity into a replacement target.
    descriptor = os.open(root / "out" / name,
                         os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as output:
        json.dump(value, output, indent=2)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())


def private_root() -> Path:
    require_container()
    _require(os.geteuid() != 0, "refusing a root session")
    raw = os.environ.get("PFV", "")
    _require(len(raw) <= 256 and PRIVATE_ROOT.fullmatch(raw) is not None, "non-probe root")
    root = Path(raw)
    _require(os.environ.get("HOME") == str(root / "home")
             and os.environ.get("XDG_RUNTIME_DIR") == str(root / "run"), "foreign HOME/runtime")
    for path in (root, root / "home", root / "run", root / "out"):
        _require(path.is_dir() and not path.is_symlink() and path.resolve() == path
                 and path.stat().st_uid == os.geteuid(), "foreign/symlinked private directory")
    return root


def read_process(pid: int, root: Path) -> dict:
    _require(_integer(pid, 2, 2147483647), "invalid process id")
    process = Path("/proc") / str(pid)
    fields = (process / "stat").read_text().rsplit(") ", 1)[1].split()
    environment = (process / "environ").read_bytes().split(b"\0")

    def value(name: str) -> str:
        prefix = os.fsencode(name + "=")
        matches = [row[len(prefix):] for row in environment if row.startswith(prefix)]
        _require(len(matches) == 1, "missing/ambiguous process environment")
        return os.fsdecode(matches[0])

    home, runtime = value("HOME"), value("XDG_RUNTIME_DIR")
    _require(home == str(root / "home") and runtime == str(root / "run"),
             "process belongs to another HOME/runtime")
    return {
        "pid": pid, "parent": int(fields[1]), "start": int(fields[19]),
        "uid": process.stat().st_uid, "executable": str((process / "exe").resolve(strict=True)),
        "home": home, "runtime": runtime,
    }


def validate_shell(shell: dict, controller: dict, root: Path, uid: int) -> None:
    _require(_integer(uid, 1, 4294967295), "invalid session uid")
    for process, executable in ((controller, "/usr/bin/bash"), (shell, "/usr/bin/plasmashell")):
        _require(isinstance(process, dict), "invalid process identity")
        _require(_integer(process.get("pid"), 2, 2147483647)
                 and _integer(process.get("parent"), 1, 2147483647)
                 and _integer(process.get("start"), 1, 18446744073709551615)
                 and type(process.get("uid")) is int and process["uid"] == uid,
                 "invalid process ownership")
        _require(process.get("executable") == executable
                 and process.get("home") == str(root / "home")
                 and process.get("runtime") == str(root / "run"), "foreign process")
    _require(shell["parent"] == controller["pid"] and shell["pid"] != controller["pid"],
             "shell is not the recorded direct child")


def _validate_session(value: dict, *, shell_required: bool) -> None:
    _require(isinstance(value, dict) and set(value) == {"bus", "backend", "shell"},
             "invalid session identity")
    _require(isinstance(value["bus"], str) and re.fullmatch(r"[0-9a-f]{32}", value["bus"]) is not None
             and isinstance(value["backend"], str) and OWNER.fullmatch(value["backend"]) is not None,
             "invalid bus/backend identity")
    shell = value["shell"]
    _require(isinstance(shell, str) and (OWNER.fullmatch(shell) is not None
             or (not shell_required and shell == "")), "invalid shell owner")


def _validate_identity(identity: dict, root: Path, uid: int) -> None:
    _schema(identity)
    _require(identity.get("root") == str(root), "capture belongs to another root")
    validate_shell(identity.get("shell"), identity.get("controller"), root, uid)
    _validate_session(identity.get("session"), shell_required=True)


def _matching_shell(shell: dict, identity: dict) -> None:
    validate_shell(shell, identity["controller"], Path(identity["root"]),
                   identity["controller"]["uid"])
    _require(shell == identity["shell"], "contradictory cleanup shell")


def _validate_request(request: dict, identity: dict) -> None:
    _schema(request)
    _matching_shell(request.get("shell"), identity)
    _require(request.get("signal") == "SIGTERM" and request.get("session") == identity["session"],
             "contradictory cleanup request")


def session_snapshot() -> dict:
    return {
        "bus": qdbus("org.freedesktop.DBus", "/org/freedesktop/DBus",
                     "org.freedesktop.DBus.GetId"),
        "backend": owner_of("org.kde.KWin"), "shell": owner_of("org.kde.plasmashell"),
    }


def _shell_pid(session: dict) -> int:
    return int(qdbus("org.freedesktop.DBus", "/org/freedesktop/DBus",
                     "org.freedesktop.DBus.GetConnectionUnixProcessID", session["shell"]))


def _controller_is_current(controller: dict, root: Path) -> bool:
    current = os.getppid()
    for _ in range(8):
        if current <= 1:
            return False
        process = read_process(current, root)
        if (process["uid"] != controller["uid"] or process["home"] != str(root / "home")
                or process["runtime"] != str(root / "run")):
            return False
        if current == controller["pid"]:
            return process == controller
        current = process["parent"]
    return False


def _withdrawn_session(before: dict) -> dict:
    deadline = time.monotonic() + 2
    while True:
        after = session_snapshot()
        _validate_session(after, shell_required=False)
        _require(after["bus"] == before["bus"] and after["backend"] == before["backend"],
                 "bus/backend changed during shell stop")
        if after["shell"] == "":
            return after
        _require(after["shell"] == before["shell"], "shell replaced during cleanup")
        _require(time.monotonic() < deadline, "shell owner did not withdraw")
        time.sleep(0.05)


def capture() -> None:
    root = private_root()
    _require(not (root / "out/cleanup-identity.json").exists(), "capture already exists")
    before = session_snapshot()
    _validate_session(before, shell_required=True)
    pid = _shell_pid(before)
    controller = read_process(os.getppid(), root)
    shell = read_process(pid, root)
    validate_shell(shell, controller, root, os.geteuid())
    _require(session_snapshot() == before, "session changed during capture")
    write_record(root, "cleanup-identity.json", {
        "schema": 1, "root": str(root), "controller": controller, "shell": shell, "session": before,
    })


def signal_owned() -> int:
    root = private_root()
    identity = read_record(root, "cleanup-identity.json")
    _validate_identity(identity, root, os.geteuid())
    _require(_controller_is_current(identity["controller"], root), "foreign controller")
    _require(session_snapshot() == identity["session"], "session changed before cleanup")
    shell = identity["shell"]
    _require(_shell_pid(identity["session"]) == shell["pid"], "shell owner/process binding changed")
    _require(read_process(shell["pid"], root) == shell, "recorded shell changed")
    _require(hasattr(os, "pidfd_open") and hasattr(signal, "pidfd_send_signal")
             and hasattr(select, "poll"), "Linux descriptor signalling is unavailable")
    descriptor = os.pidfd_open(shell["pid"], 0)
    try:
        # The PID can disappear or be recycled while opening the descriptor. Never redirect.
        _require(read_process(shell["pid"], root) == shell, "shell changed while opening descriptor")
        poller = select.poll()
        poller.register(descriptor, select.POLLIN)
        _require(not poller.poll(0), "shell exited before the cleanup request")
        # Claim the intent before its effect. An interrupted/unknown stop must not be retried.
        write_record(root, "cleanup-request.json", {
            "schema": 1, "signal": "SIGTERM", "shell": shell, "session": identity["session"],
        })
        signal.pidfd_send_signal(descriptor, signal.SIGTERM, None, 0)
        events = poller.poll(8000)
        _require(any(fd == descriptor and flags & select.POLLIN for fd, flags in events),
                 "owned shell stop timed out")
        after = _withdrawn_session(identity["session"])
        write_record(root, "cleanup-stopped.json", {
            "schema": 1, "signal": "SIGTERM", "shell": shell, "exitObserved": True, "session": after,
        })
    finally:
        os.close(descriptor)
    return shell["pid"]


def confirm(status: int) -> None:
    root = private_root()
    identity = read_record(root, "cleanup-identity.json")
    _validate_identity(identity, root, os.geteuid())
    _require(_controller_is_current(identity["controller"], root), "foreign confirming controller")
    _validate_request(read_record(root, "cleanup-request.json"), identity)
    stopped = read_record(root, "cleanup-stopped.json")
    _schema(stopped)
    _matching_shell(stopped.get("shell"), identity)
    _require(stopped.get("signal") == "SIGTERM" and stopped.get("exitObserved") is True,
             "missing observed shell stop")
    _require(type(status) is int, "invalid parent wait status")
    after = _withdrawn_session(identity["session"])
    _require(stopped.get("session") == after, "session changed after observed stop")
    write_record(root, "cleanup-result.json", {
        "schema": 1, "passed": status == 0, "signal": "SIGTERM", "exit": status,
        "shell": identity["shell"], "before": identity["session"], "after": after,
    })
    _require(status == 0, "owned shell parent wait failed: " + str(status))


def check_cleanup(directory: Path) -> None:
    for name in ("kwin.log", "plasmashell.log", "container.log", "teardown.log"):
        path = directory / name
        _require(path.is_file() and not path.is_symlink(), "missing cleanup diagnostic " + name)
    for path in sorted(directory.glob("*.log")):
        _require(path.is_file() and not path.is_symlink(), "nonregular cleanup diagnostic")
        with path.open(encoding="utf-8", errors="replace") as source:
            for number, line in enumerate(source, 1):
                _require(FATAL.search(line) is None,
                         f"crash diagnostics in {path.name}:{number}")
    identity, request, stopped, result = [_read_json(directory / name) for name in (
        "cleanup-identity.json", "cleanup-request.json", "cleanup-stopped.json", "cleanup-result.json",
    )]
    root_value = identity.get("root") if isinstance(identity, dict) else None
    _require(isinstance(root_value, str) and len(root_value) <= 256
             and PRIVATE_ROOT.fullmatch(root_value) is not None,
             "invalid captured private root")
    controller = identity.get("controller")
    _require(isinstance(controller, dict), "missing controller")
    _validate_identity(identity, Path(root_value), controller.get("uid"))
    _validate_request(request, identity)
    _schema(stopped)
    _schema(result)
    _matching_shell(stopped.get("shell"), identity)
    _matching_shell(result.get("shell"), identity)
    _require(stopped.get("signal") == result.get("signal") == "SIGTERM"
             and stopped.get("exitObserved") is True, "contradictory owned shell stop")
    _require(result.get("passed") is True and type(result.get("exit")) is int
             and result["exit"] == 0, "owned shell did not exit successfully")
    before, after = result.get("before"), result.get("after")
    _validate_session(before, shell_required=True)
    _validate_session(after, shell_required=False)
    _require(before == identity["session"] and stopped.get("session") == after
             and after["bus"] == before["bus"] and after["backend"] == before["backend"]
             and after["shell"] == "", "cleanup lifetime changed")
    sweep = (directory / "teardown.log").read_text().splitlines()
    _require(bool(sweep) and re.fullmatch(r"[0-9]+(?:\.[0-9]+)? done; left: none", sweep[-1]) is not None,
             "cleanup sweep incomplete or has residual processes")
    _require(not any("SIGKILL" in line for line in sweep), "forced cleanup is not qualified")
    outer = [line for line in (directory / "container.log").read_text().splitlines()
             if line.startswith("session rc=")]
    _require(outer == ["session rc=0"], "outer cleanup session failed or is incomplete")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("capture", "signal", "confirm"))
    parser.add_argument("status", nargs="?", type=int)
    args = parser.parse_args()
    if (args.mode == "confirm") != (args.status is not None):
        parser.error("only confirm requires the actual parent wait status")
    try:
        if args.mode == "capture":
            capture()
        elif args.mode == "signal":
            print(signal_owned())
        else:
            confirm(args.status)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(2, f"{error}\n")


if __name__ == "__main__":
    main()
