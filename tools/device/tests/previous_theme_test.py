# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# What the "My previous desktop" generator (tools/device/previous-theme.py) reads from files other
# programs write: KConfig text (a later value wins, [$d] deletes, localised values are left out, a
# group's [$i] is dropped), a Global Theme's contents/defaults and its metadata.json (a file that is
# not an object, or a name with line breaks, gives a package with one comment line and no extra
# keys). Standard library only; the package is written below a temporary directory.
# Usage: python3 previous_theme_test.py <path to previous-theme.py>
import importlib.machinery, importlib.util, json, os, pathlib, subprocess, sys, tempfile

loader = importlib.machinery.SourceFileLoader("previous_theme", sys.argv[1])
spec = importlib.util.spec_from_loader("previous_theme", loader)
tool = importlib.util.module_from_spec(spec)
loader.exec_module(tool)
fails = []

parsed = tool.parse_kconfig_text(
    "top=1\n# comment\n[General][$i]\nColorScheme=A\n ColorScheme = B \nName[de]=Lokal\nIcon[$e]=x\n"
    "font[$d]\nfixed[$d]=gone\n[kdeglobals][KDE]\nwidgetStyle=Fusion\n")
want = {("", "top"): "1", ("General", "ColorScheme"): "B", ("General", "Icon"): "x", ("General", "font"): None,
        ("General", "fixed"): None, ("kdeglobals][KDE", "widgetStyle"): "Fusion"}
if parsed != want:
    fails.append(f"parse_kconfig_text gave {parsed}")
want = {("", "", "top"): "1", ("", "General", "ColorScheme"): "B", ("", "General", "Icon"): "x",
        ("", "General", "font"): None, ("", "General", "fixed"): None, ("kdeglobals", "KDE", "widgetStyle"): "Fusion"}
if tool.package_defaults(parsed) != want:
    fails.append(f"package_defaults gave {tool.package_defaults(parsed)}")

for text, name in (('{"KPlugin": {"Name": "Ocean"}}', "Ocean"), ('[1, 2]', "id"), ('{"KPlugin": "Ocean"}', "id"),
                   ('{"KPlugin": {"Name": 5}}', "id"), ('{"KPlugin": {"Name": " "}}', "id"), ("not json", "id"),
                   ("[" * 100000, "id"), ('{"KPlugin": {"Name": "Two\\nlines"}}', "Two lines")):
    try:
        got = tool.package_name(text, "id")
        if got != name:
            fails.append(f"package_name({text[:40]!r}) is {got!r}, not {name!r}")
    except Exception as e:
        fails.append(f"package_name({text[:40]!r}) failed: {e!r}")
entries = [("kdeglobals][General", "ColorScheme", "Ocean", "user")]
text = tool.render(entries, tool.defaults_comment("A\n[kdeglobals][KDE]\nwidgetStyle=Other", "2026-10-02", "/b\nx=y"))
if tool.parse_kconfig_text(text) != {("kdeglobals][General", "ColorScheme"): "Ocean"}:
    fails.append("a name with line breaks added keys to the package's defaults:\n" + text)

# The whole generator on a Global Theme whose metadata.json is not an object and one whose name has
# line breaks: a package is written, with the theme's id or the name on one line.
with tempfile.TemporaryDirectory() as d:
    d = pathlib.Path(d)
    (d / "config").mkdir()
    (d / "config/kdeglobals").write_text("[General]\nColorScheme=Ocean\n")
    pkg = d / "data/plasma/look-and-feel/org.example.ocean.desktop"
    (pkg / "contents").mkdir(parents=True)
    (pkg / "contents/defaults").write_text("[kdeglobals][KDE]\nwidgetStyle=Fusion\n")
    env = dict(os.environ, XDG_CONFIG_DIRS=str(d / "none"), XDG_DATA_DIRS=str(d / "none"))
    for meta, name in (([1, 2], "org.example.ocean.desktop"),
                       ({"KPlugin": {"Name": "Ocean\n[x]\ny=z"}}, "Ocean [x] y=z")):
        (pkg / "metadata.json").write_text(json.dumps(meta))
        out = subprocess.run([sys.executable, sys.argv[1], "--config-dir", str(d / "config"), "--lookandfeel",
                              "org.example.ocean.desktop", "--data", str(d / "data"), "--force"],
                             capture_output=True, text=True, env=env)
        defaults = d / "data/plasma/look-and-feel" / tool.PKG_ID / "contents/defaults"
        if out.returncode != 0 or not defaults.is_file():
            fails.append(f"metadata.json {meta}: exit {out.returncode}, {out.stderr.strip()[-200:]}")
            continue
        got = tool.parse_kconfig_text(defaults.read_text())
        if got.get(("kdeglobals][General", "ColorScheme")) != "Ocean" or ("x", "y") in got:
            fails.append(f"metadata.json {meta}: defaults {got}")
        if f"before Plasma Fusion ({name})" not in defaults.read_text().splitlines()[0]:
            fails.append(f"metadata.json {meta}: first line {defaults.read_text().splitlines()[0]!r}")

for f in fails:
    print("previous-theme test:", f, file=sys.stderr)
if fails:
    sys.exit(1)
print("previous-theme test: KConfig text, Global Theme defaults and metadata.json read; one comment line")
