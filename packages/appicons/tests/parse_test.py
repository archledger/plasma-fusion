# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# What the familiar icon tool reads from files other programs write: desktop entries (the first
# value of a key wins, other groups and hidden entries are left out), plasmafusionrc and the theme's
# designed-apps.txt with bytes that are not UTF-8 (read, not a crash), and desktop ids too long for
# an icon file name (no per-app tile, the other apps keep theirs). Standard library only.
# Usage: python3 parse_test.py <path to plasma-fusion-app-icons>
import importlib.machinery, importlib.util, os, pathlib, sys, tempfile

with tempfile.TemporaryDirectory() as d:
    d = pathlib.Path(d)
    for k, sub in (("XDG_DATA_HOME", "data"), ("XDG_STATE_HOME", "state"), ("XDG_CONFIG_HOME", "config")):
        os.environ[k] = str(d / sub)
    os.environ["XDG_DATA_DIRS"] = str(d / "system")
    os.environ["HOME"] = str(d)

    loader = importlib.machinery.SourceFileLoader("appicons", sys.argv[1])
    spec = importlib.util.spec_from_loader("appicons", loader)
    tool = importlib.util.module_from_spec(spec)
    loader.exec_module(tool)
    tool.FLATPAK = []
    fails = []

    values = tool.parse_desktop_entry(
        "Icon=outside\n[Desktop Entry]\nType=Application\n Icon = first \nIcon=second\nno equals sign\n"
        "[Desktop Action new]\nIcon=action\n[Desktop Entry]\nIcon=third\nNoDisplay=false\n")
    if values != {"Type": "Application", "Icon": "first", "NoDisplay": "false"}:
        fails.append(f"parse_desktop_entry gave {values}")
    app = {"Type": "Application", "Icon": "x"}
    for entry, icon in ((app, "x"), (dict(app, Icon=""), None), (dict(app, Type="Link"), None),
                        (dict(app, NoDisplay="true"), None), (dict(app, Hidden="true"), None)):
        if tool.visible_icon(entry) != icon:
            fails.append(f"visible_icon({entry}) is not {icon!r}")
    rc = "[General]\nAppIcons=designs\n[Icons]\nAppIcons = familiar\nAppIcons=Designs\nAppIcons=familiar\n"
    if tool.parse_mode(rc) != "designs":
        fails.append("parse_mode did not take the first AppIcons= line of [Icons]")
    if tool.parse_mode("[Icons]\nAppIcons=other\n") != "familiar":
        fails.append("parse_mode did not fall back to familiar for an unknown value")

    # bytes that are not UTF-8 (a hand-edited file in Latin-1) are replaced, not a crash
    (d / "config").mkdir()
    (d / "config/plasmafusionrc").write_bytes(b"[General]\nName=Caf\xe9\n[Icons]\nAppIcons=designs\n")
    try:
        if tool.mode() != "designs":
            fails.append("mode() did not read AppIcons=designs next to a Latin-1 line")
    except ValueError as e:
        fails.append(f"mode() failed on a Latin-1 line: {e!r}")
    root = d / "data/icons" / tool.THEMES[0]
    root.mkdir(parents=True)
    (root / "designed-apps.txt").write_bytes(b"org.kde.kate\ncaf\xe9\norg.kde.dolphin\n")
    try:
        names = tool.designed_names()
        if not {"org.kde.kate", "org.kde.dolphin"} <= names:
            fails.append(f"designed_names() gave {sorted(names)}")
    except ValueError as e:
        fails.append(f"designed_names() failed on a Latin-1 line: {e!r}")

    # A desktop id below nested application directories (Wine's start menu) can be longer than a
    # file name: that app gets no per-app tile, the others keep theirs.
    (d / "config/plasmafusionrc").write_text("[Icons]\nAppIcons=familiar\n")
    (root / "designed-apps.txt").write_text("org.kde.kate\n")
    apps = d / "data/applications"
    deep = apps / "wine/Programs" / ("A Vendor With A Long Name " * 4) / ("A Program With A Long Name " * 4)
    deep.mkdir(parents=True)
    (deep / "Uninstall.desktop").write_text("[Desktop Entry]\nType=Application\nName=Uninstall\nIcon=foo\n")
    (apps / "foo.desktop").write_text("[Desktop Entry]\nType=Application\nName=Foo\nIcon=foo\n")
    (d / "data/icons/hicolor/scalable/apps").mkdir(parents=True)
    (d / "data/icons/hicolor/scalable/apps/foo.svg").write_text("<svg/>")
    long_id = str((deep / "Uninstall.desktop").relative_to(apps)).replace("/", "-")[:-len(".desktop")]
    if len(tool.app_tile_name(long_id) + ".svg") <= 255:
        fails.append("the long desktop id of the test is not too long")
    want = tool.wanted()
    if sorted(want) != ["foo", "plasmafusion_app.foo"]:
        fails.append(f"wanted() {sorted(want)}, expected foo and plasmafusion_app.foo only")
    for name in want:
        try:
            tool.write_icon(tool.THEMES[0], name, tool.MARK + "<svg/>")
        except OSError as e:
            fails.append(f"write_icon({name[:40]}...) failed: {e}")

    for f in fails:
        print("app-icons parse test:", f, file=sys.stderr)
    if fails:
        sys.exit(1)
    print("app-icons parse test: desktop entries, plasmafusionrc and designed-apps.txt read; long ids left out")
