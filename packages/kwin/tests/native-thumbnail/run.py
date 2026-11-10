# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run only in a disposable container, never against the logged-in compositor.

Usage: run.py STAGE_HOME PROBE_BUILD OUTPUT_ROOT NAME IMAGE --runtime-manifest FILE
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from check_connections import check

# Reuse the private-compositor log oracle from the navigation qualification.
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.path.insert(0, str(REPO / "packages/navigation-cpp/tests"))
from check_runtime import failures  # noqa: E402


def check_session_logs(scenario, container):
    for label, text, prefix in (("scenario", scenario, "scenario"),
                                ("compositor session", scenario, "session"),
                                ("container wrapper", container, "session")):
        statuses = re.findall(rf"^{prefix} rc=(.*)$", text, re.M)
        assert statuses == ["0"], f"{label}: expected one successful status, got {statuses}"


def fresh_session_environment(inherited):
    seed_overrides = ("PFV_HOME_DIR", "PFV_PRE")
    present = [name for name in seed_overrides if inherited.get(name)]
    if present:
        raise ValueError("fresh session rejects seed overrides: " + ", ".join(present))
    return {name: value for name, value in inherited.items() if name not in seed_overrides}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("stage", "build", "output"):
        parser.add_argument(argument, type=Path)
    parser.add_argument("name")
    parser.add_argument("image")
    parser.add_argument("--runtime-manifest", type=Path, required=True)
    parser.add_argument("--retain-hidden", action="store_true")
    parser.add_argument("--filter-target", action="store_true")
    args = parser.parse_args()
    environment = fresh_session_environment(os.environ)
    stage, build, output = (value.resolve() for value in (args.stage, args.build, args.output))
    name = args.name
    assert re.fullmatch(r"[a-zA-Z0-9-]+", name), "invalid session name"
    runtime = json.loads(args.runtime_manifest.read_text())
    files = runtime["files"]
    assert len(files) == 2 and "kwin_wayland" in files
    assert all(key == "kwin_wayland" or re.fullmatch(r"libkwin\.so\.\d+\.\d+\.\d+", key) for key in files)
    assert all(re.fullmatch(r"[a-f0-9]{64}", digest) for digest in files.values())
    image = subprocess.check_output(
        ["podman", "image", "inspect", args.image, "--format", "{{.Id}}"], text=True).strip()
    assert image.removeprefix("sha256:") == runtime["image"].removeprefix("sha256:"), "wrong runtime image"
    here, repo = HERE, REPO
    seed = output / "seeds" / name
    result_dir = output / "vsession-out" / name
    assert not seed.exists() and not result_dir.exists(), "refusing to overwrite a run"
    shutil.copytree(stage, seed)
    (seed / ".config").mkdir(exist_ok=True)
    (seed / ".config/kwinrc").write_text(
        "[TabBox]\nLayoutName=org.plasmafusion.switcher\nDesktopMode=0\nShowTabBox=true\n")
    module = seed / "probe-qml/org/plasmafusion/thumbnailprobe"
    module.mkdir(parents=True)
    shutil.copy2(here / "qmldir", module / "qmldir")
    shutil.copy2(build / "libthumbnailprobe.so", module / "libthumbnailprobe.so")
    probe_hash = hashlib.sha256((module / "libthumbnailprobe.so").read_bytes()).hexdigest()
    (seed / "expected-native.json").write_text(json.dumps({"files": files, "probe": probe_hash}) + "\n")
    (seed / "thumbnail-case").write_text("filtered\n" if args.filter_target else "normal\n")
    shutil.copy2(here / "finish-session.sh", seed / "finish-session.sh")
    (seed / ".config/pfv-env").write_text(
        f"QML_IMPORT_PATH=/var/tmp/pfv-{name}/home/probe-qml\n")
    shutil.copytree(repo / "tools", seed / "pf-tools")
    qml = seed / ".local/share/kwin/tabbox/org.plasmafusion.switcher/contents/ui/main.qml"
    text = qml.read_text()
    assert text.count("import QtQuick\n") == 1 and text.count("        id: root\n") == 1
    text = text.replace("import QtQuick\n", "import QtQuick\nimport org.plasmafusion.thumbnailprobe 1.0 as Inspect\n", 1)
    observer = '''        Inspect.Probe { id: connectionProbe }
        Connections {
            target: tabBox
            function onVisibleChanged() {
                const label = tabBox.visible ? "open" : "closed";
                Qt.callLater(function() {
                    const w = KWin.Workspace.windows.find(w => w.caption === "Thumbnail target");
                    connectionProbe.dump(w, tabBox, label);
                });
            }
        }
'''
    if args.filter_target:
        observer += '''        Connections {
            target: root
            function onShowAllChanged() {
                if (!tabBox.visible) {
                    return;
                }
                const label = root.showAll ? "all" : "filtered";
                Qt.callLater(function() {
                    const w = KWin.Workspace.windows.find(w => w.caption === "Thumbnail target");
                    connectionProbe.dump(w, tabBox, label);
                });
            }
        }
'''
    qml.write_text(text.replace("        id: root\n", "        id: root\n" + observer, 1))
    inputs = {"runtime": runtime, "image": image, "release_hidden": not args.retain_hidden,
              "filter_target": args.filter_target,
              "seed_sha256": {str(p.relative_to(seed)): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in seed.rglob("*") if p.is_file()}}
    (output / f"{name}-inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    command = ["bash", str(repo / "tools/vsession/cvsession.sh"), name,
               str(here / "scenario.sh"), str(seed), "1280x800", "120"]
    with (output / f"{name}.log").open("w") as log:
        result = subprocess.run(command, cwd=output, env={**environment, "PFV_IMAGE": image},
                                stdout=log, stderr=subprocess.STDOUT, timeout=210)
    assert result.returncode == 0, "container wrapper failed"
    scenario = (result_dir / "scenario.log").read_text()
    check_session_logs(scenario, (result_dir / "container.log").read_text())
    assert "PASS: private plasmashell exited before bus teardown" in scenario
    shutil.copy2(output / f"{name}.log", result_dir / "driver.log")
    errors = failures(result_dir, require_bus_log=True)
    assert not errors, errors
    counts = check((result_dir / "kwin.log").read_text(), release_hidden=not args.retain_hidden,
                   filter_target=args.filter_target)
    (result_dir / "connections.json").write_text(json.dumps(counts, indent=2) + "\n")
    print(json.dumps(counts, indent=2))


if __name__ == "__main__":
    main()
