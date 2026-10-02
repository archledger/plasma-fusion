# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Names the theme draws with a designed tile (designed-apps.txt) get no familiar icon, and the
# backup of the file a familiar icon hides follows a redeployed theme: dropping the familiar icon
# puts the newest file back, or keeps a file that replaced it since. Standard library only.
# Usage: python3 designed_test.py <path to plasma-fusion-app-icons>
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

    data = d / "data"
    theme = tool.THEMES[0]
    root = data / "icons" / theme
    (root / "art").mkdir(parents=True)
    (root / "apps/scalable").mkdir(parents=True)
    for art in ("tile-old", "tile-new", "tile-app-kate"):
        (root / "art" / (art + ".svg")).write_text("<svg/>")
    (root / "designed-apps.txt").write_text("org.kde.kate\n")
    (data / "applications").mkdir(parents=True)
    (data / "icons/hicolor/scalable/apps").mkdir(parents=True)
    for did, icon in (("org.kde.kate", "org.kde.kate"), ("foo", "foo")):
        (data / "applications" / (did + ".desktop")).write_text(
            f"[Desktop Entry]\nType=Application\nName={did}\nIcon={icon}\n")
        (data / "icons/hicolor/scalable/apps" / (icon + ".svg")).write_text("<svg/>")

    fails = []
    want = tool.wanted()
    if sorted(want) != ["foo"]:
        fails.append(f"wanted() {sorted(want)}, expected ['foo'] (org.kde.kate is designed)")

    path = tool.theme_file(theme, "foo")
    saved = tool.BACKUP / theme / "foo.svg"
    familiar = tool.MARK + "<svg/>"

    # a familiar icon hides the theme's link; dropping it puts the link back
    os.symlink("../../art/tile-old.svg", path)
    tool.write_icon(theme, "foo", familiar)
    if not tool.ours(path) or os.readlink(saved) != "../../art/tile-old.svg":
        fails.append("write_icon did not keep the theme's link as the backup")
    tool.drop_icon(theme, "foo")
    if not path.is_symlink() or os.readlink(path) != "../../art/tile-old.svg" or os.path.lexists(saved):
        fails.append("drop_icon did not put the theme's link back")

    # the theme is redeployed while the familiar icon is in place: the new link stays
    tool.write_icon(theme, "foo", familiar)
    path.unlink()
    os.symlink("../../art/tile-new.svg", path)
    tool.drop_icon(theme, "foo")
    if not path.is_symlink() or os.readlink(path) != "../../art/tile-new.svg":
        fails.append("drop_icon replaced a newer theme link with an old backup")
    if os.path.lexists(saved):
        fails.append("drop_icon kept an out-of-date backup")

    # rebuilt after a redeploy: the backup is the newest link
    tool.write_icon(theme, "foo", familiar)
    path.unlink()
    os.symlink("../../art/tile-old.svg", path)          # older art written over it, e.g. a rollback
    tool.write_icon(theme, "foo", familiar)
    if os.readlink(saved) != "../../art/tile-old.svg":
        fails.append("write_icon kept an older backup instead of the file it hid")

    for f in fails:
        print("app-icons designed test:", f, file=sys.stderr)
    if fails:
        sys.exit(1)
    print("app-icons designed test: designed names skipped; backups follow the theme")
