#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Make a fresh, local-only P0 HOME. Never run setup, SSH or copy live user configuration."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path

if __package__:
    from .cleanup import check_cleanup
    from .completion import CHECKS as COMPLETION_CHECKS
    from .completion import check_completion
    from .keyboard_entry import CHECKS as KEYBOARD_ENTRY_CHECKS
    from .keyboard_entry import check_keyboard_entry
    from .mixed_lifetime import check_mixed
    from .refused_backend import CHECKS as REFUSED_CHECKS
    from .refused_backend import check_refused
    from .two_bar import CHECKS as TWO_BAR_CHECKS
    from .two_bar import check_two_bar
    from .pipeline import CHECKS as PIPELINE_CHECKS
    from .pipeline import check_pipeline
    from .view_loss import CHECKS as VIEW_LOSS_CHECKS
    from .view_loss import check_view_loss
else:
    from cleanup import check_cleanup
    from completion import CHECKS as COMPLETION_CHECKS
    from completion import check_completion
    from keyboard_entry import CHECKS as KEYBOARD_ENTRY_CHECKS
    from keyboard_entry import check_keyboard_entry
    from mixed_lifetime import check_mixed
    from refused_backend import CHECKS as REFUSED_CHECKS
    from refused_backend import check_refused
    from two_bar import CHECKS as TWO_BAR_CHECKS
    from two_bar import check_two_bar
    from pipeline import CHECKS as PIPELINE_CHECKS
    from pipeline import check_pipeline
    from view_loss import CHECKS as VIEW_LOSS_CHECKS
    from view_loss import check_view_loss

HERE = Path(__file__).resolve().parent
SCRIPT_ID = "plasmafusion-layout-probe"
OCCUPIER_ID = "plasmafusion-layout-occupier"
APPLET_ID = "org.plasmafusion.layoutprobe"


def prepare(stage: Path, output: Path, *, drop_retirement_frame: bool = False,
             query_timeout_ms: int = 10000, reply_delay_ms: int = 0,
             focus_probe: bool = False, target_probe: bool = False,
             mixed_lifetime_probe: bool = False, view_loss_probe: bool = False,
             refused_backend_probe: bool = False, pipeline_probe: bool = False,
             completion_probe: bool = False, two_bar_probe: bool = False,
             keyboard_entry_probe: bool = False) -> None:
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
    if reply_delay_ms and drop_retirement_frame:
        # The bridge runs the delayed-reply case and returns before the silent-retirement case.
        raise ValueError("the delayed-reply and dropped-retirement faults are separate seeds")
    if mixed_lifetime_probe and view_loss_probe:
        raise ValueError("mixed-lifetime and view-loss scenarios are separate private cases")
    if two_bar_probe and (completion_probe or mixed_lifetime_probe or view_loss_probe
                          or refused_backend_probe or pipeline_probe or drop_retirement_frame
                          or reply_delay_ms):
        raise ValueError("the two-bar case is a separate private target case")
    if keyboard_entry_probe and (two_bar_probe or completion_probe or mixed_lifetime_probe
                                 or view_loss_probe or refused_backend_probe or pipeline_probe
                                 or drop_retirement_frame or reply_delay_ms):
        raise ValueError("the keyboard-entry case is a separate private target case")
    if completion_probe and (mixed_lifetime_probe or view_loss_probe or refused_backend_probe
                             or pipeline_probe or drop_retirement_frame or reply_delay_ms):
        raise ValueError("the completion case is a separate private target case")
    if refused_backend_probe and (focus_probe or target_probe or mixed_lifetime_probe
                                  or view_loss_probe or drop_retirement_frame or reply_delay_ms):
        raise ValueError("the refused-backend case is a separate plain-transport private case")
    if pipeline_probe and (focus_probe or target_probe or mixed_lifetime_probe or view_loss_probe
                           or refused_backend_probe or drop_retirement_frame or reply_delay_ms):
        raise ValueError("the pipeline case is a separate plain-transport private case")
    target_probe = (target_probe or mixed_lifetime_probe or view_loss_probe or completion_probe
                    or two_bar_probe or keyboard_entry_probe)
    focus_probe = focus_probe or target_probe
    if focus_probe and (drop_retirement_frame or reply_delay_ms):
        raise ValueError("focus observation requires normal transport")
    rules = stage / ".local/share/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js"
    if not rules.is_file():
        raise ValueError("missing staged Tiling.js")
    fixture_names = ["provider.qml", "consumer.qml"]
    if refused_backend_probe:
        fixture_names.append("occupier.qml")
    fixtures = {name: (HERE / name).read_bytes() for name in fixture_names}
    focus_helper = (HERE.parent / "lib/heldclient.py").read_bytes() if focus_probe else None
    receipt_helper = (HERE / "receipts.py").read_bytes() if target_probe else None
    case_names = ()
    if mixed_lifetime_probe:
        case_names = ("mixed_lifetime.py", "mixed_scenario.sh")
    elif view_loss_probe:
        # The view-loss checker reuses only the mixed checker's complete-line event reader.
        case_names = ("mixed_lifetime.py", "view_loss.py", "view_loss_scenario.sh")
    elif refused_backend_probe:
        # So does the refused-backend checker.
        case_names = ("mixed_lifetime.py", "refused_backend.py", "refused_scenario.sh")
    elif pipeline_probe:
        # So does the pipeline checker.
        case_names = ("mixed_lifetime.py", "pipeline.py", "pipeline_scenario.sh")
    elif completion_probe:
        # So does the completion checker.
        case_names = ("mixed_lifetime.py", "completion.py", "completion_scenario.sh")
    elif two_bar_probe:
        # The two-bar checker also applies the completion rules.
        case_names = ("mixed_lifetime.py", "completion.py", "two_bar.py", "two_bar_scenario.sh")
    elif keyboard_entry_probe:
        # Like the view-loss checker, the keyboard-entry checker reuses only the mixed reader.
        case_names = ("mixed_lifetime.py", "keyboard_entry.py", "keyboard_scenario.sh")
    case_helpers = {name: (HERE / name).read_bytes() for name in case_names}
    cleanup_helpers = {
        name: (HERE / name).read_bytes() for name in ("cleanup.py", "lifecycle.py")
    }
    output.mkdir(parents=True, mode=0o700)
    script = output / ".local/share/kwin/scripts" / SCRIPT_ID
    applet = output / ".local/share/plasma/plasmoids" / APPLET_ID
    packages = [(script, "KWin/Script", SCRIPT_ID, "provider.qml", "Layout transport probe"),
                (applet, "Plasma/Applet", APPLET_ID, "consumer.qml", "Layout transport probe")]
    if refused_backend_probe:
        packages.append((output / ".local/share/kwin/scripts" / OCCUPIER_ID, "KWin/Script",
                         OCCUPIER_ID, "occupier.qml", "Layout probe provider occupier"))
    for package, structure, identifier, fixture, title in packages:
        (package / "contents/ui").mkdir(parents=True)
        metadata = {
            "KPackageStructure": structure,
            "KPlugin": {"Id": identifier, "Name": title, "Version": "0.1",
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
    # In the refused-backend case only the occupier starts with the session; the scenario loads
    # the probe once the occupier holds the native provider slot.
    plugins = f"{SCRIPT_ID}Enabled={'false' if refused_backend_probe else 'true'}\n"
    occupier = ""
    if refused_backend_probe:
        plugins += f"{OCCUPIER_ID}Enabled=true\n"
        occupier = f"\n[Script-{OCCUPIER_ID}]\nOccupierAuthorized=true\n"
    (private_config / "kwinrc").write_text(
        f"[Plugins]\n{plugins}\n[Script-{SCRIPT_ID}]\nProbeAuthorized=true\n"
        f"DropRetirementFrame={'true' if drop_retirement_frame else 'false'}\n"
        f"ReplyDelayMs={reply_delay_ms}\n"
        f"FocusProbe={'true' if focus_probe else 'false'}\n"
        f"TargetProbe={'true' if target_probe else 'false'}\n"
        f"MixedLifetimeProbe={'true' if mixed_lifetime_probe else 'false'}\n"
        f"ViewLossProbe={'true' if view_loss_probe else 'false'}\n"
        f"RefusedBackendProbe={'true' if refused_backend_probe else 'false'}\n"
        f"PipelineProbe={'true' if pipeline_probe else 'false'}\n"
        f"CompletionProbe={'true' if completion_probe else 'false'}\n"
        f"TwoBarProbe={'true' if two_bar_probe else 'false'}\n"
        f"KeyboardEntryProbe={'true' if keyboard_entry_probe else 'false'}\n"
        f"{occupier}"
        "\n[Desktops]\nNumber=2\nRows=1\n"
    )
    (private_config / "pfv-env").write_text("PF_LAYOUT_PRIVATE_CONTAINER=1\n")
    # The seed's own copy of the rules: the staged file may be rebuilt after it was copied.
    seeded_rules = (script / "contents/ui/Tiling.js").read_bytes()
    inputs = {
        name: hashlib.sha256(data).hexdigest() for name, data in fixtures.items()
    } | {"Tiling.js": hashlib.sha256(seeded_rules).hexdigest(),
         "kwinrc": hashlib.sha256((private_config / "kwinrc").read_bytes()).hexdigest(),
         "pfv-env": hashlib.sha256((private_config / "pfv-env").read_bytes()).hexdigest(),
         "main.xml": hashlib.sha256((config / "main.xml").read_bytes()).hexdigest()}
    if focus_helper is not None:
        helper = output / ".local/lib/layout-control/heldclient.py"
        helper.parent.mkdir(parents=True)
        helper.write_bytes(focus_helper)
        inputs["heldclient.py"] = hashlib.sha256(focus_helper).hexdigest()
    if receipt_helper is not None:
        helper = output / ".local/lib/layout-control/receipts.py"
        helper.parent.mkdir(parents=True, exist_ok=True)
        helper.write_bytes(receipt_helper)
        inputs["receipts.py"] = hashlib.sha256(receipt_helper).hexdigest()
    for name, data in case_helpers.items():
        helper = output / ".local/lib/layout-control" / name
        helper.parent.mkdir(parents=True, exist_ok=True)
        helper.write_bytes(data)
        inputs[name] = hashlib.sha256(data).hexdigest()
    for name, data in cleanup_helpers.items():
        helper = output / ".local/lib/layout-control" / name
        helper.parent.mkdir(parents=True, exist_ok=True)
        helper.write_bytes(data)
        inputs[name] = hashlib.sha256(data).hexdigest()
    (output / "probe-inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check-result", type=Path)
    parser.add_argument(
        "--scope",
        choices=("first-slice", "silent-retirement", "reply-ordering",
                 "query-timeout-late", "focus-observation", "target-preparation",
                  "consumer-retirement", "mixed-lifetimes", "view-loss", "refused-backend",
                  "pipeline", "completion", "two-bar", "keyboard-entry"),
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
    parser.add_argument("--mixed-lifetime-probe", action="store_true",
                        help="private combined consumer/provider lifetime and replay scenario")
    parser.add_argument("--view-loss-probe", action="store_true",
                        help="private output-loss and activity-switch scenario (two outputs)")
    parser.add_argument("--refused-backend-probe", action="store_true",
                        help="private refused native registration scenario (occupier fixture)")
    parser.add_argument("--pipeline-probe", action="store_true",
                        help="private wake-up burst against the serialized read/publish pipeline")
    parser.add_argument("--completion-probe", action="store_true",
                        help="private target case: decided completions kept by newer frames")
    parser.add_argument("--two-bar-probe", action="store_true",
                        help="private target case: one probe bar per output (two outputs)")
    parser.add_argument("--keyboard-entry-probe", action="store_true",
                        help="private target case: keyboard entry after panel focus")
    args = parser.parse_args()
    try:
        if args.check_result is not None:
            if (args.stage is not None or args.output is not None or args.drop_retirement_frame
                    or args.query_timeout_ms is not None or args.reply_delay_ms is not None
                    or args.focus_probe or args.target_probe or args.mixed_lifetime_probe
                    or args.view_loss_probe or args.refused_backend_probe
                    or args.pipeline_probe or args.completion_probe or args.two_bar_probe
                    or args.keyboard_entry_probe):
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
                    focus_probe=args.focus_probe, target_probe=args.target_probe,
                    mixed_lifetime_probe=args.mixed_lifetime_probe,
                    view_loss_probe=args.view_loss_probe,
                    refused_backend_probe=args.refused_backend_probe,
                    pipeline_probe=args.pipeline_probe,
                    completion_probe=args.completion_probe,
                    two_bar_probe=args.two_bar_probe,
                    keyboard_entry_probe=args.keyboard_entry_probe)
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
    elif scope == "consumer-retirement":
        receipt = directory / "consumer-retirement-result.json"
        checks = ["roundtrip-native", "guarded-target", "consumer-retirement",
                  "busy-replay", "explicit-recovery"]
    elif scope == "mixed-lifetimes":
        receipt = directory / "mixed-lifetime-result.json"
        checks = ["roundtrip-native", "consumer-replacement", "provider-reload",
                  "late-frame-rejection", "stale-intent-refusal", "explicit-recovery"]
    elif scope == "view-loss":
        receipt = directory / "view-loss-result.json"
        checks = VIEW_LOSS_CHECKS
    elif scope == "refused-backend":
        receipt = directory / "refused-backend-result.json"
        checks = REFUSED_CHECKS
    elif scope == "pipeline":
        receipt = directory / "pipeline-result.json"
        checks = PIPELINE_CHECKS
    elif scope == "completion":
        receipt = directory / "completion-result.json"
        checks = COMPLETION_CHECKS
    elif scope == "two-bar":
        receipt = directory / "two-bar-result.json"
        checks = TWO_BAR_CHECKS
    elif scope == "keyboard-entry":
        receipt = directory / "keyboard-entry-result.json"
        checks = KEYBOARD_ENTRY_CHECKS
    else:
        raise ValueError("unknown probe receipt scope")
    if not receipt.is_file():
        raise ValueError(f"missing probe receipt: {receipt.name}")
    result = json.loads(receipt.read_text())
    if result != {"schema": 1, "passed": True, "checks": checks}:
        raise ValueError("incomplete probe receipt")
    if scope == "mixed-lifetimes":
        check_mixed(directory)
    elif scope == "view-loss":
        check_view_loss(directory)
    elif scope == "refused-backend":
        check_refused(directory)
    elif scope == "pipeline":
        check_pipeline(directory)
    elif scope == "completion":
        check_completion(directory)
    elif scope == "two-bar":
        check_two_bar(directory)
    elif scope == "keyboard-entry":
        check_keyboard_entry(directory)
    check_cleanup(directory)
    print(f"PASS: explicit {scope} receipt, inner exit codes and separate cleanup qualification")


if __name__ == "__main__":
    main()
