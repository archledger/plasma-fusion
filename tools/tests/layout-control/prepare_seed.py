#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Make a fresh, local-only P0 HOME. Never run setup, SSH or copy live user configuration."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT_ID = "plasmafusion-layout-probe"
APPLET_ID = "org.plasmafusion.layoutprobe"


def prepare(stage: Path, output: Path, *, drop_retirement_frame: bool = False,
            query_timeout_ms: int = 10000, reply_delay_ms: int = 0,
            focus_probe: bool = False, target_probe: bool = False) -> None:
    build = Path.cwd() / "build"
    if build.is_symlink() or not output.resolve().is_relative_to(build.resolve()):
        raise ValueError("output must be under the current worktree's build directory")
    if output.exists() or output.is_symlink():
        raise ValueError("output already exists; use a new name to preserve evidence")
    if not 100 <= query_timeout_ms <= 10000:
        raise ValueError("query deadline must be between 100 and 10000 ms")
    if not 0 <= reply_delay_ms <= 3000:
        raise ValueError("reply delay must be between 0 and 3000 ms")
    if reply_delay_ms and reply_delay_ms <= query_timeout_ms:
        raise ValueError("reply delay must exceed the query deadline for this fault")
    focus_probe = focus_probe or target_probe
    if focus_probe and (drop_retirement_frame or reply_delay_ms):
        raise ValueError("focus observation requires normal transport")
    rules = stage / ".local/share/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js"
    if not rules.is_file():
        raise ValueError("missing staged Tiling.js")
    fixtures = {name: (HERE / name).read_bytes() for name in ("provider.qml", "consumer.qml")}
    focus_helper = (HERE.parent / "lib/heldclient.py").read_bytes() if focus_probe else None
    output.mkdir(parents=True, mode=0o700)
    script = output / ".local/share/kwin/scripts" / SCRIPT_ID
    applet = output / ".local/share/plasma/plasmoids" / APPLET_ID
    for package, structure, identifier, fixture in (
        (script, "KWin/Script", SCRIPT_ID, "provider.qml"),
        (applet, "Plasma/Applet", APPLET_ID, "consumer.qml"),
    ):
        (package / "contents/ui").mkdir(parents=True)
        metadata = {
            "KPackageStructure": structure,
            "KPlugin": {"Id": identifier, "Name": "Layout transport probe", "Version": "0.1",
                        "License": "GPL-2.0-or-later", "EnabledByDefault": False},
        }
        if structure == "KWin/Script":
            metadata.update({"X-Plasma-API": "declarativescript", "X-Plasma-MainScript": "ui/main.qml"})
        else:
            metadata["X-Plasma-API-Minimum-Version"] = "6.0"
        (package / "metadata.json").write_text(json.dumps(metadata))
        (package / "contents/ui/main.qml").write_bytes(fixtures[fixture])
    shutil.copyfile(rules, script / "contents/ui/Tiling.js")
    config = applet / "contents/config"
    config.mkdir()
    entries = "".join(
        f'<entry name="{name}" type="String"><default></default></entry>'
        for name in ("layoutRequest", "layoutResponse")
    )
    entries += (f'<entry name="queryTimeoutMs" type="Int">'
                f'<default>{query_timeout_ms}</default></entry>')
    entries += ('<entry name="focusProbe" type="Bool"><default>'
                f'{"true" if focus_probe else "false"}</default></entry>')
    entries += ('<entry name="targetProbe" type="Bool"><default>'
                f'{"true" if target_probe else "false"}</default></entry>')
    (config / "main.xml").write_text(
        '<?xml version="1.0"?><kcfg xmlns="http://www.kde.org/standards/kcfg/1.0">'
        f'<kcfgfile name=""/><group name="General">{entries}</group></kcfg>'
    )
    private_config = output / ".config"
    private_config.mkdir()
    (private_config / "kwinrc").write_text(
        f"[Plugins]\n{SCRIPT_ID}Enabled=true\n\n[Script-{SCRIPT_ID}]\nProbeAuthorized=true\n"
        f"DropRetirementFrame={'true' if drop_retirement_frame else 'false'}\n"
        f"ReplyDelayMs={reply_delay_ms}\n"
        f"FocusProbe={'true' if focus_probe else 'false'}\n"
        f"TargetProbe={'true' if target_probe else 'false'}\n"
        "\n[Desktops]\nNumber=2\nRows=1\n"
    )
    inputs = {
        name: hashlib.sha256(data).hexdigest() for name, data in fixtures.items()
    } | {"Tiling.js": hashlib.sha256(rules.read_bytes()).hexdigest(),
         "kwinrc": hashlib.sha256((private_config / "kwinrc").read_bytes()).hexdigest(),
         "main.xml": hashlib.sha256((config / "main.xml").read_bytes()).hexdigest()}
    if focus_helper is not None:
        helper = output / ".local/lib/layout-control/heldclient.py"
        helper.parent.mkdir(parents=True)
        helper.write_bytes(focus_helper)
        inputs["heldclient.py"] = hashlib.sha256(focus_helper).hexdigest()
    (output / "probe-inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check-result", type=Path)
    parser.add_argument(
        "--scope",
        choices=("first-slice", "silent-retirement", "reply-ordering",
                 "query-timeout-late", "focus-observation", "target-preparation"),
        default="first-slice",
    )
    parser.add_argument("--drop-retirement-frame", action="store_true",
                        help="fault injection in this private test seed only")
    parser.add_argument("--query-timeout-ms", type=int, help="private client one-shot deadline")
    parser.add_argument("--reply-delay-ms", type=int, help="private delayed-publication fault")
    parser.add_argument("--focus-probe", action="store_true",
                        help="private focus-event observation controls and client helper")
    parser.add_argument("--target-probe", action="store_true",
                        help="private non-mutating target preparation and validation")
    args = parser.parse_args()
    try:
        if args.check_result is not None:
            if (args.stage is not None or args.output is not None or args.drop_retirement_frame
                    or args.query_timeout_ms is not None or args.reply_delay_ms is not None
                    or args.focus_probe or args.target_probe):
                raise ValueError("--check-result cannot be combined with seed preparation")
            check_result(args.check_result, args.scope)
        else:
            if args.scope != "first-slice":
                raise ValueError("--scope requires --check-result")
            if args.stage is None or args.output is None:
                raise ValueError("seed preparation requires --stage and --output")
            prepare(args.stage.resolve(), args.output,
                    drop_retirement_frame=args.drop_retirement_frame,
                    query_timeout_ms=(
                        args.query_timeout_ms if args.query_timeout_ms is not None else 10000
                    ),
                    reply_delay_ms=args.reply_delay_ms if args.reply_delay_ms is not None else 0,
                    focus_probe=args.focus_probe, target_probe=args.target_probe)
    except (ValueError, OSError) as error:
        parser.exit(2, f"{error}\n")


def check_result(directory: Path, scope: str = "first-slice") -> None:
    lines = (directory / "scenario.log").read_text().splitlines()
    codes = [line for line in lines if line.startswith(("scenario rc=", "session rc="))]
    if not {"scenario rc=0", "session rc=0"}.issubset(codes) or any(
        line not in {"scenario rc=0", "session rc=0"} for line in codes
    ):
        raise ValueError("scenario did not finish successfully; outer harness status is insufficient")
    if scope == "first-slice":
        receipt = directory / "layout-probe-result.json"
        checks = ["roundtrip-native", "retirement"]
    elif scope == "silent-retirement":
        receipt = directory / "silent-retirement-result.json"
        checks = ["roundtrip-native", "silent-retirement", "provider-reload"]
    elif scope == "reply-ordering":
        receipt = directory / "reply-ordering-result.json"
        checks = ["roundtrip-native", "same-provider-ordering"]
    elif scope == "query-timeout-late":
        receipt = directory / "query-timeout-result.json"
        checks = ["roundtrip-native", "query-timeout", "late-state"]
    elif scope == "focus-observation":
        receipt = directory / "focus-observation-result.json"
        checks = ["roundtrip-native", "panel-keyboard-focus"]
    elif scope == "target-preparation":
        receipt = directory / "target-preparation-result.json"
        checks = ["roundtrip-native", "guarded-target"]
    else:
        raise ValueError("unknown probe receipt scope")
    if not receipt.is_file():
        raise ValueError(f"missing probe receipt: {receipt.name}")
    result = json.loads(receipt.read_text())
    if result != {"schema": 1, "passed": True, "checks": checks}:
        raise ValueError("incomplete probe receipt")
    print(f"PASS: explicit {scope} receipt and inner scenario/session exit codes")


if __name__ == "__main__":
    main()
