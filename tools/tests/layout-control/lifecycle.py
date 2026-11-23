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
CHECKS = ["private-bus", "shell-restart", "backend-restart"]
# A target-mode lease: the provider's epoch and its serial for that consumer.
LEASE = re.compile(r"([0-9a-f]{32}):([1-9][0-9]*)")
SAVED_LEASE = re.compile(r'"consumerLease":"([0-9a-f]{32}:[1-9][0-9]*)"')
# The configuration the first shell leaves, which the second starts from, kept for the recheck.
KEPT_CONFIGURATION = "shell-1-appletsrc"


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


def probe_mode(home: Path) -> str:
    """The seed's mode: a target seed publishes view contexts and consumer leases."""
    config = configparser.ConfigParser()
    config.read(home / ".config/kwinrc")
    return ("target" if config.getboolean("Script-plasmafusion-layout-probe", "TargetProbe",
                                          fallback=False) else "plain")


def bootstrapped(rows: list, mode: str) -> bool:
    """Fresh receiver rows the run can use; in target mode only once every frame carries a leased
    context, which the provider gives a consumer only after a complete inventory confirms it."""
    if not rows:
        return False
    return mode != "target" or all(
        isinstance(row["packet"].get("targetContext"), dict)
        and isinstance(row["packet"]["targetContext"].get("consumerLease"), str) for row in rows)


def saved_response_leases(text: str) -> set:
    """The leases in a shell configuration's saved response fields. Saved target-mode requests
    carry a consumerLease key too, empty for a query, so only response entries count."""
    return {lease for line in text.splitlines() if line.startswith("layoutResponse=")
            for lease in SAVED_LEASE.findall(line)}


def check_leases(leases: object, epochs: object) -> None:
    """Two leases per shell, each of its shell's provider epoch, and no two receivers' alike.
    The restarted shell's receivers get later leases from the same provider; the replacement
    KWin starts a new epoch."""
    if (not isinstance(leases, list) or not isinstance(epochs, list) or len(leases) != 3
            or len(epochs) != 3 or any(not isinstance(group, list) or len(group) != 2
                                       for group in leases)):
        raise ValueError("a target run records two receivers' leases for each of three shells")
    serials = []
    for group, epoch in zip(leases, epochs):
        matches = [LEASE.fullmatch(lease) if isinstance(lease, str) else None for lease in group]
        if any(match is None or match.group(1) != epoch for match in matches):
            raise ValueError("a receiver's lease is not one of its provider lifetime")
        serials.append([int(match.group(2)) for match in matches])
    issued = [lease for group in leases for lease in group]
    if len(set(issued)) != len(issued):
        raise ValueError("two receivers got the same lease")
    if epochs[0] != epochs[1] or epochs[1] == epochs[2]:
        raise ValueError("a shell restart must keep the provider epoch and a KWin restart must"
                         " change it")
    if min(serials[1]) <= max(serials[0]):
        raise ValueError("the restarted shell's receivers got no later leases")


def target_bootstrap(shells: list) -> dict:
    """Each shell's two receivers bound fresh target-mode frames: a context of the frame's own
    provider lifetime with a lease, and neither a preparation nor a completion, since a fresh
    receiver has only queried."""
    leases, epochs = [], []
    for rows in shells:
        if not isinstance(rows, list) or len(rows) != 2:
            raise ValueError("a target run needs two receivers in each shell")
        if any(not isinstance(row, dict) or not isinstance(row.get("packet"), dict)
               for row in rows):
            raise ValueError("a malformed receiver row")
        epoch = rows[0]["packet"].get("epoch")
        for row in rows:
            packet = row["packet"]
            context = packet.get("targetContext")
            if (packet.get("epoch") != epoch or not isinstance(context, dict)
                    or context.get("epoch") != epoch):
                raise ValueError("a receiver's frame has no context of its provider lifetime")
            if packet.get("preparation") is not None or packet.get("completion") is not None:
                raise ValueError("a fresh receiver's frame carries a preparation or completion")
        leases.append([row["packet"]["targetContext"].get("consumerLease") for row in rows])
        epochs.append(epoch)
    check_leases(leases, epochs)
    return {"leases": leases, "epochs": epochs}


def distinct_receivers(shells: list) -> bool:
    """No receiver appears in two shells. A receiver's label belongs to one QML instance, so a
    shell that shows an earlier shell's label kept a receiver it should have replaced. The run
    and the recheck both apply this to all three shells."""
    boots = [row["boot"] for rows in shells for row in rows]
    return len(set(boots)) == len(boots)


def check_receipt(receipt: dict) -> None:
    mode = receipt.get("mode", "plain")
    checks = CHECKS + (["target-bootstrap"] if mode == "target" else [])
    if (receipt.get("schema") != 1 or receipt.get("passed") is not True
            or receipt.get("scope") != "p0-process-replacement" or mode not in ("plain", "target")
            or receipt.get("checks") != checks):
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
    if mode == "target":
        check_leases(receipt.get("leases"), receipt.get("epochs"))
        saved = receipt.get("savedLeases")
        if (not isinstance(saved, list)
                or not all(isinstance(lease, str) and LEASE.fullmatch(lease) for lease in saved)
                or not set(receipt["leases"][0]) <= set(saved)):
            raise ValueError("the first shell's saved responses do not hold its leases")


def check_run(output: Path) -> dict:
    """Recheck a finished run from its files, as run_container does after its container: the
    receipt and, for a target seed, the receivers it recorded, which must be in their shells' raw
    logs and must first have reported unknown, the saved leases, recomputed from the kept
    configuration, and each provider lifetime's
    reads and publications, which must pass the replay's serialization rules up to its teardown.
    Stopping drops a queued delayed publication and sends the offline frame even while a
    publication is outstanding, so nothing from the offline frame on is replayed."""
    receipt = json.loads((output / "lifecycle-result.json").read_text())
    check_receipt(receipt)
    if receipt.get("mode", "plain") != "target":
        return receipt
    # On the host only: the container mounts this file alone. Leave the search path as found.
    added = str(HERE.parent) not in sys.path
    if added:
        sys.path.insert(0, str(HERE.parent))
    try:
        from mixed_lifetime import complete_lines, events
        from pipeline import EVENT, replay
    finally:
        if added:
            sys.path.remove(str(HERE.parent))
    shells, first_by_shell = [], []
    for number in (1, 2, 3):
        rows = json.loads((output / f"shell-{number}-observations.json").read_text())
        logged = [row for _, row in events(complete_lines(output / f"shell-{number}.log"),
                                           "observation")]
        if not isinstance(rows, list) or any(row not in logged for row in rows):
            raise ValueError(f"a recorded receiver is not in shell-{number}.log")
        first = {}
        for row in logged:
            first.setdefault(row["boot"], row)
        shells.append(rows)
        first_by_shell.append(first)
    # Shells 1 and 2 ran under the first KWin and shell 3 under its replacement. The run bound
    # each receiver to that connection (online_rows), and its files must agree.
    for number, rows in enumerate(shells, 1):
        backend = receipt["backendOwners"][0 if number < 3 else 1]
        for row in rows:
            require_online_receiver(row, backend, f"a shell-{number} receiver")
    if target_bootstrap(shells) != {"leases": receipt["leases"], "epochs": receipt["epochs"]}:
        raise ValueError("the receipt's leases do not match the receivers' frames")
    if not distinct_receivers(shells):
        raise ValueError("a restart reused a receiver")
    for rows, first in zip(shells, first_by_shell):
        for row in rows:
            require_unbound(first[row["boot"]])
    kept = saved_response_leases((output / KEPT_CONFIGURATION).read_text())
    if sorted(kept) != receipt["savedLeases"]:
        raise ValueError("the receipt's saved leases are not the kept configuration's")
    for number in (1, 2):
        name = f"kwin-{number}.log"
        lines = complete_lines(output / name)
        matches = [(index, EVENT.fullmatch(line.rstrip("\n"))) for index, line in enumerate(lines)]
        teardown = next((index for index, match in matches
                         if match and match.group(1).startswith("publication offline")),
                        len(lines))
        try:
            counts = replay(lines[:teardown], 0)["counts"]
        except ValueError as error:
            raise ValueError(f"{name}: {error}") from None
        if not counts["reads"] or not counts["publications"]:
            raise ValueError(f"{name}: no read and publication before the teardown")
    return receipt


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
        # A crashed command is not a completed bus method response, even with a known prefix.
        if error.returncode < 0:
            raise
        # Method errors are on stdout; auxiliary locale warnings must not mask them.
        diagnostic = error.output or error.stderr or ""
        if diagnostic.splitlines()[:1] == ["Error: org.freedesktop.DBus.Error.NameHasNoOwner"]:
            return ""
        raise


def require_container() -> None:
    if (os.environ.get("PF_LAYOUT_PRIVATE_CONTAINER") != "1"
            or not Path("/run/.containerenv").is_file()):
        raise ValueError("refusing execution outside the disposable container")


def require_unbound(first: dict) -> None:
    if first["phase"] != "unknown" or first["accepted"] != 0 or first["packet"] is not None:
        raise ValueError("receiver did not bootstrap unknown")


def require_online_receiver(row: dict, backend: str, label: str) -> None:
    packet = row.get("packet") if isinstance(row, dict) else None
    if (not isinstance(packet, dict) or row.get("phase") != "online"
            or packet.get("status") != "online" or not isinstance(row.get("boot"), str)
            or packet.get("consumer") != row["boot"] or packet.get("capable") is not True):
        raise ValueError(f"{label} is not a capable online receiver for its own frame")
    if packet.get("backendOwner") != backend:
        raise ValueError(f"{label} is bound to another backend")


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
        require_unbound(first[boot])
        require_online_receiver(row, backend, "receiver")
        packet = row["packet"]
        if owner_of(packet["identityName"]) != backend:
            raise ValueError("receiver's alias belongs to another connection")
    return list(latest.values())


def desktop_containment_ready(shell: str) -> bool:
    try:
        # With no method argument, qdbus calls Introspect directly. Its method mode instead
        # collapses an absent object and an absent method into the same "Cannot find" message.
        qdbus(shell, "/PlasmaShell")
    except subprocess.CalledProcessError as error:
        if (error.returncode == 2 and (error.output or "").splitlines()[:1]
                == ["Error: org.freedesktop.DBus.Error.UnknownObject"]):
            return False
        raise
    text = qdbus(shell, "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
                 "print(desktops().length);")
    return text.isdigit() and int(text) > 0


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
    mode = probe_mode(private / "home")
    receipt = {"schema": 1, "scope": "p0-process-replacement", "passed": False, "mode": mode}
    bus_id = lambda: qdbus("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.GetId")
    kwin_command = ["kwin_wayland", "--virtual", "--width", "1440", "--height", "900",
                    "--socket", "w0", "--no-lockscreen"]

    def start_shell(label: str, backend: str, create_widgets: bool = False):
        process = children.start(label, ["plasmashell"])
        shell = wait_until(lambda: owner_of("org.kde.plasmashell"), "shell owner")
        def shell_ready():
            if process.poll() is not None:
                raise ValueError(f"{label} exited before shell initialization")
            return desktop_containment_ready(shell)
        wait_until(shell_ready, "desktop containment")
        if create_widgets:
            qdbus(shell, "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
                  "var p=new Panel;p.location='top';p.height=40;"
                  "p.addWidget('org.plasmafusion.layoutprobe');"
                  "p.addWidget('org.plasmafusion.layoutprobe');")
        def fresh():
            rows = online_rows(output / f"{label}.log", backend)
            return rows if bootstrapped(rows, mode) else []
        rows = wait_until(fresh, f"{label} fresh receiver exchange")
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
        # In target mode the configuration the second shell starts from holds the first
        # shell's receivers' leases in its saved response fields. The run keeps that file, and
        # the leases are taken from the copy the host recheck reads too.
        if mode == "target":
            kept = output / KEPT_CONFIGURATION
            shutil.copyfile(saved, kept)
            leases = {row["packet"]["targetContext"]["consumerLease"] for row in rows1}
            saved_leases = saved_response_leases(kept.read_text())
            if not leases <= saved_leases:
                raise ValueError("the first shell's saved responses do not hold its leases")
            receipt["savedLeases"] = sorted(saved_leases)
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
        if (kwin2.poll() is not None or not distinct_receivers([rows1, rows2, rows3])
                or rows2[0]["epoch"] == rows3[0]["epoch"]):
            raise ValueError("replacement did not establish new receiver/provider lifetimes")
        bootstrap = target_bootstrap([rows1, rows2, rows3]) if mode == "target" else {}
        receipt.update({
            "passed": True, "busIds": ids, "backendOwners": [backend1, backend2],
            "shellOwners": [owner1, owner2, owner3],
            "checks": CHECKS + (["target-bootstrap"] if mode == "target" else []),
        } | bootstrap)
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
    stopped = True
    try:
        with (output / "container.log").open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=240, check=False)
        if result.returncode != 0:
            raise ValueError(f"container exited {result.returncode}; inspect {output}/container.log")
        receipt = check_run(output)
    finally:
        if cid.is_file():
            identifier = cid.read_text().strip()
            if re.fullmatch(r"[0-9a-f]{64}", identifier):
                # This ID was created by this invocation, never found by name or process scan.
                # --ignore: a container that --rm already removed is not an error.
                stop = subprocess.run(["podman", "stop", "--ignore", "--time", "10", identifier],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                      timeout=20, check=False)
                (output / "container-id.txt").write_text(identifier + "\n")
                if stop.returncode == 0:
                    cid.unlink()
                else:
                    # The container may still run: keep its ID file and say so, also when the
                    # run has already failed for another reason.
                    stopped = False
                    print(f"cleanup: podman stop exited {stop.returncode}; container ID kept in"
                          f" {cid}", file=sys.stderr)
    if not stopped or cid.exists():
        raise ValueError(f"the container stop was not confirmed; its ID is kept in {cid}")
    if receipt.get("mode", "plain") == "target":
        print("PASS: private-bus process replacement with fresh target contexts and leases"
              f" and a serialized pipeline; results in {output}")
    else:
        print(f"PASS: private-bus process replacement only; results in {output}")


def main() -> None:
    signal.signal(signal.SIGTERM, lambda number, _: sys.exit(128 + number))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name")
    parser.add_argument("--seed", type=Path)
    parser.add_argument("--image")
    parser.add_argument("--check-result", type=Path, metavar="DIR",
                        help="recheck a finished run's results, writing nothing")
    parser.add_argument("--container", help=argparse.SUPPRESS)
    parser.add_argument("--session", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        if args.check_result is not None:
            if args.name or args.seed or args.image or args.container or args.session:
                raise ValueError("--check-result takes no other arguments")
            cid = args.check_result.with_suffix(".cid")
            if cid.exists():
                raise ValueError(f"the container stop was not confirmed; its ID is kept in {cid}")
            receipt = check_run(args.check_result)
            print(f"PASS: {receipt.get('mode', 'plain')} process replacement evidence in"
                  f" {args.check_result}")
            return
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
