#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""P0-only container runner: the private bus belongs to the test, not to KWin."""

import argparse
import configparser
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve()


def validate_run(seed: Path, output: Path, name: str, image: str, root: Path) -> None:
    if not re.fullmatch(r"layout-control-lc-[a-z0-9-]{1,20}", name):
        raise ValueError("use a short layout-control-lc-... run name")
    if not re.fullmatch(r"[0-9a-f]{64}", image):
        raise ValueError("an immutable image ID (64 lowercase hex digits) is required")
    build = root / "build"
    if build.is_symlink() or not seed.resolve().is_relative_to(build.resolve()):
        raise ValueError("seed must be under this worktree's private build directory")
    if output.exists() or output.is_symlink():
        raise ValueError("result directory already exists; preserve it and choose another name")
    if output.with_suffix(".cid").exists():
        raise ValueError("container ID file already exists; preserve it and choose another name")
    if (output != root / "vsession-out" / name or output.parent.is_symlink()
            or not output.resolve().is_relative_to(root.resolve())):
        raise ValueError("results must be in this worktree's vsession-out/<run name>")
    if not seed.is_dir():
        raise ValueError("missing private seed directory")
    if seed.is_symlink() or any(path.is_symlink() for path in seed.rglob("*")):
        raise ValueError("seed symlinks are not permitted")
    config = configparser.ConfigParser()
    config.read(seed / ".config/kwinrc")
    if not config.getboolean("Script-plasmafusion-layout-probe", "ProbeAuthorized", fallback=False):
        raise ValueError("missing private probe authorization marker")


def container_command(seed: Path, output: Path, name: str, image: str) -> list[str]:
    return [
        "podman", "run", "--rm", "--name", "pf-" + name, "--pull=never", "--network=none",
        "--cidfile", str(output.with_suffix(".cid")),
        "--security-opt=no-new-privileges", "--shm-size=1g",
        "--device", "/dev/dri", "--group-add", "keep-groups",
        "--env", "PF_LAYOUT_PRIVATE_CONTAINER=1",
        "--volume", f"{seed}:/seed:ro,z", "--volume", f"{output}:/out:z",
        "--volume", f"{HERE}:/probe/lifecycle.py:ro,z",
        image, "python3", "-B", "/probe/lifecycle.py", "--container", name,
    ]


def session_environment(private: Path) -> dict[str, str]:
    return {
        "HOME": str(private / "home"), "XDG_RUNTIME_DIR": str(private / "run"),
        "XDG_CONFIG_HOME": str(private / "home/.config"),
        "XDG_DATA_HOME": str(private / "home/.local/share"),
        "XDG_STATE_HOME": str(private / "home/.local/state"),
        "XDG_CACHE_HOME": str(private / "home/.cache"),
        "XDG_CONFIG_DIRS": "/etc/xdg", "XDG_SESSION_TYPE": "wayland",
        "XDG_CURRENT_DESKTOP": "KDE", "KDE_FULL_SESSION": "true", "KDE_SESSION_VERSION": "6",
        "QT_QPA_PLATFORM": "wayland", "QT_FORCE_STDERR_LOGGING": "1", "WAYLAND_DISPLAY": "w0",
        "PATH": "/usr/bin:/bin:/usr/lib64/qt6/bin", "LANG": "C.UTF-8",
        "PF_LAYOUT_PRIVATE_CONTAINER": "1",
    }


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def qdbus(*arguments: str) -> str:
    return subprocess.check_output(["qdbus-qt6", *arguments], text=True,
                                   stderr=subprocess.PIPE, timeout=10).strip()


def check_receipt(receipt: dict) -> None:
    if (receipt.get("schema") != 1 or receipt.get("passed") is not True
            or receipt.get("scope") != "p0-process-replacement"
            or receipt.get("checks") != ["private-bus", "shell-restart", "backend-restart"]):
        raise ValueError("missing successful process replacement receipt")
    owners = receipt.get("backendOwners", [])
    if (len(owners) != 2 or len(set(owners)) != 2
            or not all(re.fullmatch(r":[0-9]+\.[0-9]+", owner) for owner in owners)):
        raise ValueError("replacement requires two different backend connections")
    ids = receipt.get("busIds", [])
    if (len(ids) != 3 or len(set(ids)) != 1 or not re.fullmatch(r"[0-9a-f]{32}", ids[0])):
        raise ValueError("replacement must remain on the same private bus")
    shells = receipt.get("shellOwners", [])
    if (len(shells) != 3 or len(set(shells)) != 3
            or not all(re.fullmatch(r":[0-9]+\.[0-9]+", owner) for owner in shells)):
        raise ValueError("replacement requires three different shell connections")


class Children:
    def __init__(self, output: Path):
        self.output = output
        self.processes = []

    def start(self, label: str, command: list[str]) -> subprocess.Popen:
        with (self.output / f"{label}.log").open("w") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        self.processes.append((label, process))
        return process

    @staticmethod
    def stop(process: subprocess.Popen) -> None:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)

    def cleanup(self) -> None:
        for _, process in reversed(self.processes):
            self.stop(process)
        write_json(self.output / "children.json", [
            {"label": label, "pid": process.pid, "returncode": process.returncode}
            for label, process in self.processes
        ])


def wait_until(predicate, description: str, seconds: int = 30):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise ValueError(f"timed out: {description}")


def owner_of(name: str) -> str:
    try:
        return qdbus("org.freedesktop.DBus", "/org/freedesktop/DBus",
                     "org.freedesktop.DBus.GetNameOwner", name)
    except subprocess.CalledProcessError as error:
        # qdbus-qt6 reports method errors on stdout in the pinned test image.
        diagnostic = error.stderr or error.output or ""
        if diagnostic.splitlines()[:1] == ["Error: org.freedesktop.DBus.Error.NameHasNoOwner"]:
            return ""
        raise


def require_container() -> None:
    if (os.environ.get("PF_LAYOUT_PRIVATE_CONTAINER") != "1"
            or not Path("/run/.containerenv").is_file()):
        raise ValueError("refusing execution outside the disposable container")


def online_rows(log: Path, backend: str) -> list[dict]:
    latest = {}
    first = {}
    for line in log.read_text().splitlines(keepends=True):
        if not line.endswith("\n") or "layout-probe-observation " not in line:
            continue
        row = json.loads(line.split("layout-probe-observation ", 1)[1])
        first.setdefault(row["boot"], row)
        latest[row["boot"]] = row
    if len(latest) != 2 or any(row["phase"] != "online" for row in latest.values()):
        return []
    for boot, row in latest.items():
        packet = row["packet"]
        if (first[boot]["phase"] != "unknown" or first[boot]["accepted"] != 0
                or first[boot]["packet"] is not None or packet["consumer"] != boot
                or packet["backendOwner"] != backend or packet["capable"] is not True):
            raise ValueError("receiver did not bootstrap unknown and bind the expected backend")
        if owner_of(packet["identityName"]) != backend:
            raise ValueError("receiver's alias belongs to another connection")
    return list(latest.values())


def session_probe(name: str) -> None:
    require_container()
    private = Path("/var/tmp/pfv-" + name)
    if (os.environ.get("PF_LAYOUT_PRIVATE_CONTAINER") != "1" or os.geteuid() == 0
            or os.environ.get("HOME") != str(private / "home")
            or os.environ.get("XDG_RUNTIME_DIR") != str(private / "run")
            or not os.environ.get("DBUS_SESSION_BUS_ADDRESS")):
        raise ValueError("refusing a non-private session")
    output = Path("/out")
    services = private / "home/.local/share/dbus-1/services"
    services.mkdir(parents=True, exist_ok=True)
    (services / "org.kde.kdeconnect.service").write_text(
        "[D-BUS Service]\nName=org.kde.kdeconnect\nExec=/bin/false\n"
    )
    subprocess.run(["dbus-update-activation-environment", *session_environment(private)], check=True)
    with (output / "packages.txt").open("w") as versions:
        subprocess.run(["rpm", "-q", "kwin", "plasma-workspace", "qt6-qtbase",
                        "qt6-qtdeclarative", "kf6-kconfig"], stdout=versions, check=True)
    children = Children(output)
    receipt = {"schema": 1, "scope": "p0-process-replacement", "passed": False}
    bus_id = lambda: qdbus("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.GetId")
    kwin_command = ["kwin_wayland", "--virtual", "--width", "1440", "--height", "900",
                    "--socket", "w0", "--no-lockscreen"]

    def start_shell(label: str, backend: str, create_widgets: bool = False):
        process = children.start(label, ["plasmashell"])
        shell = wait_until(lambda: owner_of("org.kde.plasmashell"), "shell owner")
        def shell_ready():
            if process.poll() is not None:
                raise ValueError(f"{label} exited before shell initialization")
            text = qdbus(shell, "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
                         "print(desktops().length);")
            return text.isdigit() and int(text) > 0
        wait_until(shell_ready, "desktop containment")
        if create_widgets:
            qdbus(shell, "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
                  "var p=new Panel;p.location='top';p.height=40;"
                  "p.addWidget('org.plasmafusion.layoutprobe');"
                  "p.addWidget('org.plasmafusion.layoutprobe');")
        rows = wait_until(lambda: online_rows(output / f"{label}.log", backend),
                          f"{label} fresh receiver exchange")
        write_json(output / f"{label}-observations.json", rows)
        return process, shell, rows

    try:
        ids = [bus_id()]
        kwin1 = children.start("kwin-1", kwin_command)
        backend1 = wait_until(lambda: owner_of("org.kde.KWin"), "first KWin owner")
        children.start("kamd", ["/usr/libexec/kactivitymanagerd"])
        shell1, owner1, rows1 = start_shell("shell-1", backend1, create_widgets=True)
        saved = private / "home/.config/plasma-org.kde.plasma.desktop-appletsrc"
        if "layoutResponse=" not in saved.read_text():
            raise ValueError("no saved response fields for the restart negative control")
        children.stop(shell1)
        wait_until(lambda: not owner_of("org.kde.plasmashell"), "first shell retirement")
        shell2, owner2, rows2 = start_shell("shell-2", backend1)
        ids.append(bus_id())
        if owner_of("org.kde.KWin") != backend1 or {row["boot"] for row in rows1} & {
                row["boot"] for row in rows2}:
            raise ValueError("shell restart reused a receiver or changed KWin")
        children.stop(kwin1)
        wait_until(lambda: not owner_of("org.kde.KWin"), "first KWin retirement")
        children.stop(shell2)
        wait_until(lambda: not owner_of("org.kde.plasmashell"), "second shell retirement")
        if owner_of(rows2[0]["packet"]["identityName"]):
            raise ValueError("old backend alias survived its connection")
        kwin2 = children.start("kwin-2", kwin_command)
        backend2 = wait_until(lambda: owner_of("org.kde.KWin"), "replacement KWin owner")
        _, owner3, rows3 = start_shell("shell-3", backend2)
        ids.append(bus_id())
        if (kwin2.poll() is not None or {row["boot"] for row in rows2} & {row["boot"] for row in rows3}
                or rows2[0]["epoch"] == rows3[0]["epoch"]):
            raise ValueError("replacement did not establish new receiver/provider lifetimes")
        receipt.update({
            "passed": True, "busIds": ids, "backendOwners": [backend1, backend2],
            "shellOwners": [owner1, owner2, owner3],
            "checks": ["private-bus", "shell-restart", "backend-restart"],
        })
        check_receipt(receipt)
    except Exception as error:
        receipt.update({"passed": False, "error": str(error)})
        raise
    finally:
        children.cleanup()
        write_json(output / "lifecycle-result.json", receipt)


def container_setup(name: str) -> int:
    require_container()
    if os.geteuid() != 0:
        raise ValueError("refusing setup outside the disposable container")
    private = Path("/var/tmp/pfv-" + name)
    private.mkdir(mode=0o700)
    shutil.copytree("/seed", private / "home")
    (private / "run").mkdir(mode=0o700)
    # Drop an image-only file capability, rather than adding SYS_NICE to this container.
    subprocess.run(["setcap", "-r", "/usr/bin/kwin_wayland"], check=True)
    output = Path("/out")
    original_owner = output.stat().st_uid, output.stat().st_gid
    uid = int(subprocess.check_output(["id", "-u", "test"], text=True))
    gid = int(subprocess.check_output(["id", "-g", "test"], text=True))
    for path in (private, *private.rglob("*"), output, *output.rglob("*")):
        os.chown(path, uid, gid, follow_symlinks=False)
    environment = session_environment(private)
    command = ["env", "-i", *[f"{key}={value}" for key, value in environment.items()],
               "dbus-run-session", "--", "python3", "-B", "/probe/lifecycle.py", "--session", name]
    try:
        return subprocess.run(["su", "test", "-s", "/bin/sh", "-c", "exec " + shlex.join(command)],
                              timeout=210, check=False).returncode
    finally:
        for path in (*output.rglob("*"), output):
            os.chown(path, *original_owner, follow_symlinks=False)


def run_container(seed: Path, output: Path, name: str, image: str) -> None:
    output.mkdir(parents=True, mode=0o700, exist_ok=False)
    command = container_command(seed, output, name, image)
    write_json(output / "launch.json", {
        "command": command, "image": image, "runnerSha256": hashlib.sha256(HERE.read_bytes()).hexdigest(),
    })
    cid = output.with_suffix(".cid")
    try:
        with (output / "container.log").open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=240, check=False)
        if result.returncode != 0:
            raise ValueError(f"container exited {result.returncode}; inspect {output}/container.log")
        receipt = json.loads((output / "lifecycle-result.json").read_text())
        check_receipt(receipt)
        print(f"PASS: private-bus process replacement only; results in {output}")
    finally:
        if cid.is_file():
            identifier = cid.read_text().strip()
            if re.fullmatch(r"[0-9a-f]{64}", identifier):
                # This ID was created by this invocation, never found by name or process scan.
                subprocess.run(["podman", "stop", "--ignore", "--time", "10", identifier],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20, check=False)
                (output / "container-id.txt").write_text(identifier + "\n")
                cid.unlink()


def main() -> None:
    signal.signal(signal.SIGTERM, lambda number, _: sys.exit(128 + number))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name")
    parser.add_argument("--seed", type=Path)
    parser.add_argument("--image")
    parser.add_argument("--container", help=argparse.SUPPRESS)
    parser.add_argument("--session", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        name = args.session or args.container or args.name or ""
        if not re.fullmatch(r"layout-control-lc-[a-z0-9-]{1,20}", name):
            raise ValueError("use a short layout-control-lc-... run name")
        if args.session:
            session_probe(name)
        elif args.container:
            raise SystemExit(container_setup(name))
        else:
            if args.seed is None or args.image is None:
                raise ValueError("--seed and --image are required")
            root = HERE.parents[3]
            output = root / "vsession-out" / name
            seed = args.seed.absolute()
            validate_run(seed, output, name, args.image, root)
            run_container(seed, output, name, args.image)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(2, f"{error}\n")


if __name__ == "__main__":
    main()
