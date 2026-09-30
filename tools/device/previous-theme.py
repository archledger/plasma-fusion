#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Save the look recorded in a fusion-config.sh backup as a Global Theme, "My previous desktop"
(org.plasmafusion.previous.desktop in ~/.local/share/plasma/look-and-feel), so it can be chosen
again in System Settings > Colors & Themes > Global Theme or with plasma-apply-lookandfeel.

  previous-theme.py --backup BACKUP_DIR [--data DATA_DIR] [--dry-run] [--force]
  previous-theme.py --config-dir CONFIG_DIR --lookandfeel ID [--data DATA_DIR] [--dry-run]

--backup reads BACKUP_DIR/config (a copy of ~/.config with kdedefaults/) and BACKUP_DIR/info;
--config-dir reads a live ~/.config instead (fusion-config.sh --dry-run). An existing package is
kept unless --force is given.

Each value is the one that was in effect: the user's file, then ~/.config/kdedefaults (what the
previous Global Theme wrote), then the previous Global Theme's own defaults, then the system
configuration directories, then Plasma 6.7.5's built-in default. The package holds:

  contents/defaults           colour scheme, widget style, icons, Plasma style, cursor, fonts,
                              window decoration and border size, window switcher, splash,
                              wallpaper (only when the previous Global Theme names one)
  contents/layouts/defaults   title-bar buttons and borderless maximized windows; Plasma applies
                              them only with "Desktop and window layout"
  contents/previews/          the previous Global Theme's preview images, when it has them

It has no layout script: Plasma falls back to Breeze's default layout when "Desktop and window
layout" is chosen (as for every Global Theme without one); it cannot restore the old panels.
"""
import argparse
import datetime
import json
import os
import shutil
import sys
import tempfile

PKG_ID = "org.plasmafusion.previous.desktop"
PKG_NAME = "My previous desktop"

# Plasma 6.7.5 defaults (fonts: kcms/fonts/fontssettings.kcfg, as Qt 6.11 QFont::toString()).
NOTO_10 = "Noto Sans,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular,0,0"
NOTO_8 = "Noto Sans,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular,0,0"
HACK_10 = "Hack,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular,0,0"
BUILTIN = {
    ("kdeglobals", "KDE", "widgetStyle"): "Breeze",
    ("kdeglobals", "General", "ColorScheme"): "BreezeLight",
    ("kdeglobals", "Icons", "Theme"): "breeze",
    ("plasmarc", "Theme", "name"): "default",
    ("kcminputrc", "Mouse", "cursorTheme"): "breeze_cursors",
    ("kdeglobals", "General", "font"): NOTO_10,
    ("kdeglobals", "General", "fixed"): HACK_10,
    ("kdeglobals", "General", "smallestReadableFont"): NOTO_8,
    ("kdeglobals", "General", "toolBarFont"): NOTO_10,
    ("kdeglobals", "General", "menuFont"): NOTO_10,
    ("kdeglobals", "WM", "activeFont"): NOTO_10,
    ("kwinrc", "org.kde.kdecoration2", "library"): "org.kde.breeze",
    ("kwinrc", "org.kde.kdecoration2", "theme"): "Breeze",
    ("kwinrc", "org.kde.kdecoration2", "NoPlugin"): "false",
    ("kwinrc", "org.kde.kdecoration2", "ButtonsOnLeft"): "MS",
    ("kwinrc", "org.kde.kdecoration2", "ButtonsOnRight"): "HIAX",
    ("kwinrc", "TabBox", "LayoutName"): "thumbnail_grid",
    ("kwinrc", "Windows", "BorderlessMaximizedWindows"): "false",
}
# Border size a decoration asks for while kwinrc BorderSizeAuto is true (KWin's default);
# fusion-config.sh sets BorderSizeAuto=false, so the package names the size explicitly.
RECOMMENDED_BORDER = {"org.kde.breeze": "None"}
FUSION_IDS = ("org.plasmafusion.dark.desktop", "org.plasmafusion.light.desktop")


def parse_kconfig(path):
    """KConfig file -> {(group, key): value}; group is the raw header text ("A][B" when nested)."""
    out = {}
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return out
    group = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            while line.endswith("]") and line.rfind("[$") > 0 and line.rfind("[$") == line.rfind("["):
                line = line[: line.rfind("[$")]
            group = line[1:-1]
            continue
        if "=" not in line:
            if line.endswith("]") and "[$" in line and "d" in line[line.index("[$"):]:
                out[(group, line[: line.index("[")])] = None
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if key.endswith("]") and "[" in key:
            opts = key[key.index("[") + 1: -1]
            if not opts.startswith("$"):
                continue  # localised value
            key = key[: key.index("[")]
            if "d" in opts:
                out[(group, key)] = None
                continue
        out[(group, key)] = value
    return out


def data_dirs(data):
    dirs = [data]
    for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if d and d not in dirs:
            dirs.append(d)
    return dirs


def config_dirs(skip):
    """The system configuration directories. A Plasma session's XDG_CONFIG_DIRS starts with the
    live ~/.config/kdedefaults (startplasma adds it, and fusion-config.sh takes the variable from
    plasmashell), which holds the CURRENT Global Theme's values (Plasma Fusion's once it was
    applied), not the previous look's: any kdedefaults directory is left out; the backup's own
    kdedefaults is its own layer."""
    dirs = []
    for d in os.environ.get("XDG_CONFIG_DIRS", "/etc/xdg").split(":") + [
            "/etc/xdg", "/usr/share/kde-settings/kde-profile/default/xdg"]:
        d = d.rstrip("/")
        if (d and d not in dirs and d not in skip and os.path.basename(d) != "kdedefaults"
                and os.path.isdir(d)):
            dirs.append(d)
    return dirs


class Look:
    def __init__(self, config_dir, lookandfeel, data):
        self.config_dir = config_dir
        self.user = {}
        self.kdedefaults = {}
        self.system = []
        self.sysdirs = config_dirs({config_dir.rstrip("/"), os.path.join(config_dir, "kdedefaults")})
        self.data = data
        if not lookandfeel or lookandfeel in FUSION_IDS:
            lookandfeel = self.system_value("kdeglobals", "KDE", "LookAndFeelPackage") or "org.kde.breeze.desktop"
        self.lookandfeel = lookandfeel
        self.package = None
        for d in data_dirs(data):
            p = os.path.join(d, "plasma/look-and-feel", lookandfeel)
            if os.path.isfile(os.path.join(p, "metadata.json")) or os.path.isfile(os.path.join(p, "metadata.desktop")):
                self.package = p
                break
        self.pkg_defaults = {}
        if self.package:
            for (g, k), v in parse_kconfig(os.path.join(self.package, "contents/defaults")).items():
                parts = g.split("][")
                if len(parts) == 2:
                    self.pkg_defaults[(parts[0], parts[1], k)] = v
                elif len(parts) == 1:
                    self.pkg_defaults[("", parts[0], k)] = v

    def _user(self, f):
        if f not in self.user:
            self.user[f] = parse_kconfig(os.path.join(self.config_dir, f))
        return self.user[f]

    def _kdedefaults(self, f):
        if f not in self.kdedefaults:
            self.kdedefaults[f] = parse_kconfig(os.path.join(self.config_dir, "kdedefaults", f))
        return self.kdedefaults[f]

    def system_value(self, f, g, k):
        for d in self.sysdirs:
            v = parse_kconfig(os.path.join(d, f)).get((g, k))
            if v:
                return v
        return None

    def value(self, f, g, k, theme_key=None):
        """(value, source) in effect for file f, group g, key k."""
        for layer, name in ((self._user(f), "user"), (self._kdedefaults(f), "kdedefaults")):
            if (g, k) in layer:
                if layer[(g, k)] is None:
                    break  # deleted: the built-in default
                return layer[(g, k)], name
        else:
            tf, tg, tk = theme_key or (f, g, k)
            v = self.pkg_defaults.get((tf, tg, tk))
            if v:
                return v, "previous Global Theme"
            v = self.system_value(f, g, k)
            if v:
                return v, "system"
        v = BUILTIN.get((f, g, k))
        return (v, "Plasma default") if v is not None else (None, None)


def build(look):
    """[(file-group header, key, value, source)] for contents/defaults and layouts/defaults."""
    d, lay = [], []

    def add(target, header, key, fgk, theme_key=None):
        v, src = look.value(*fgk, theme_key=theme_key)
        if v is not None:
            target.append((header, key, v, src))
        return v

    add(d, "kdeglobals][KDE", "widgetStyle", ("kdeglobals", "KDE", "widgetStyle"))
    add(d, "kdeglobals][General", "ColorScheme", ("kdeglobals", "General", "ColorScheme"))
    add(d, "kdeglobals][Icons", "Theme", ("kdeglobals", "Icons", "Theme"))
    add(d, "plasmarc][Theme", "name", ("plasmarc", "Theme", "name"))
    add(d, "kcminputrc][Mouse", "cursorTheme", ("kcminputrc", "Mouse", "cursorTheme"))
    general_font = None
    for key in ("font", "fixed", "smallestReadableFont", "toolBarFont", "menuFont"):
        v = add(d, "kdeglobals][General", key, ("kdeglobals", "General", key))
        if key == "font":
            general_font = v
    add(d, "kdeglobals][WM", "activeFont", ("kdeglobals", "WM", "activeFont"))
    # Plasma 6.7.5 turns the fonts on only when [kdeglobals][WM] holds font..menuFont or
    # [kdeglobals][General] activeFont (KLookAndFeelManager::packageContents looks in the swapped
    # groups); this marker is read for that test only and never written anywhere.
    if general_font:
        d.append(("kdeglobals][WM", "font", general_font, "marker for Plasma's font test"))
    lib = add(d, "kwinrc][org.kde.kdecoration2", "library", ("kwinrc", "org.kde.kdecoration2", "library"))
    add(d, "kwinrc][org.kde.kdecoration2", "theme", ("kwinrc", "org.kde.kdecoration2", "theme"))
    add(d, "kwinrc][org.kde.kdecoration2", "NoPlugin", ("kwinrc", "org.kde.kdecoration2", "NoPlugin"))
    auto, _ = look.value("kwinrc", "org.kde.kdecoration2", "BorderSizeAuto")
    size, src = look.value("kwinrc", "org.kde.kdecoration2", "BorderSize")
    if auto is None or auto.lower() == "true" or size is None:
        size, src = RECOMMENDED_BORDER.get(lib, "Normal"), "size the decoration asks for"
    d.append(("kwinrc][org.kde.kdecoration2", "BorderSize", size, src))
    add(d, "kwinrc][WindowSwitcher", "LayoutName", ("kwinrc", "TabBox", "LayoutName"),
        theme_key=("kwinrc", "WindowSwitcher", "LayoutName"))
    splash, src = look.value("ksplashrc", "KSplash", "Theme")
    if not splash:
        splash, src = look.lookandfeel, "previous Global Theme"
    d.append(("ksplashrc][KSplash", "Theme", splash, src))
    wall = look.pkg_defaults.get(("", "Wallpaper", "Image"))
    if wall:
        d.append(("Wallpaper", "Image", wall, "previous Global Theme"))
    add(lay, "kwinrc][org.kde.kdecoration2", "ButtonsOnLeft", ("kwinrc", "org.kde.kdecoration2", "ButtonsOnLeft"))
    add(lay, "kwinrc][org.kde.kdecoration2", "ButtonsOnRight", ("kwinrc", "org.kde.kdecoration2", "ButtonsOnRight"))
    add(lay, "kwinrc][Windows", "BorderlessMaximizedWindows", ("kwinrc", "Windows", "BorderlessMaximizedWindows"))
    return d, lay


def render(entries, comment):
    groups = {}
    for header, key, value, _src in entries:
        groups.setdefault(header, []).append("%s=%s" % (key, value))
    out = [comment]
    for header, lines in groups.items():
        out += ["", "[%s]" % header] + lines
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--backup", help="fusion-config.sh backup directory")
    ap.add_argument("--config-dir", help="a ~/.config directory (instead of --backup)")
    ap.add_argument("--lookandfeel", default="", help="the Global Theme in effect (with --config-dir)")
    ap.add_argument("--data", default=os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="replace an existing package")
    a = ap.parse_args()

    if a.backup:
        config_dir = os.path.join(a.backup, "config")
        lnf = a.lookandfeel
        try:
            for line in open(os.path.join(a.backup, "info"), encoding="utf-8"):
                if line.startswith("lookandfeel="):
                    lnf = line.split("=", 1)[1].strip()
        except OSError:
            pass
        origin = a.backup
    elif a.config_dir:
        config_dir, lnf, origin = a.config_dir, a.lookandfeel, a.config_dir
    else:
        ap.error("--backup or --config-dir is required")
    if not os.path.isdir(config_dir):
        print("previous-theme: %s does not exist" % config_dir, file=sys.stderr)
        return 1

    look = Look(config_dir, lnf, a.data)
    defaults, layout = build(look)
    dest = os.path.join(a.data, "plasma/look-and-feel", PKG_ID)
    prev_name = look.lookandfeel
    if look.package:
        try:
            meta = json.load(open(os.path.join(look.package, "metadata.json"), encoding="utf-8"))
            prev_name = meta.get("KPlugin", {}).get("Name", prev_name)
        except (OSError, ValueError):
            pass
    for header, key, value, src in defaults + layout:
        print("  %s [%s] %s = %s  (%s)" % ("defaults" if (header, key, value, src) in defaults else "layout",
                                            header, key, value, src))
    if os.path.exists(dest) and not a.force:
        print("  %s exists (kept)" % dest)
        return 0
    if a.dry_run:
        print("  would write %s (%s, from %s)" % (dest, prev_name, origin))
        return 0

    today = datetime.date.today().isoformat()
    comment = ("# My previous desktop: the look in effect before Plasma Fusion (%s), saved on %s by\n"
               "# tools/device/previous-theme.py from %s." % (prev_name, today, origin))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="." + PKG_ID + ".", dir=os.path.dirname(dest))
    try:
        os.makedirs(os.path.join(tmp, "contents/layouts"))
        with open(os.path.join(tmp, "contents/defaults"), "w", encoding="utf-8") as fh:
            fh.write(render(defaults, comment))
        with open(os.path.join(tmp, "contents/layouts/defaults"), "w", encoding="utf-8") as fh:
            fh.write(render(layout, comment + "\n# Applied only together with \"Desktop and window layout\"."))
        if look.package:
            for name in ("preview.png", "fullscreenpreview.jpg"):
                src = os.path.join(look.package, "contents/previews", name)
                if os.path.isfile(src):
                    os.makedirs(os.path.join(tmp, "contents/previews"), exist_ok=True)
                    shutil.copyfile(src, os.path.join(tmp, "contents/previews", name))
        meta = {
            "KPackageStructure": "Plasma/LookAndFeel",
            "KPlugin": {
                "Authors": [{"Email": "archledger236@gmail.com", "Name": "Wisbendji Fimerlus"}],
                "Category": "",
                "Description": "The look this computer had before Plasma Fusion (%s), saved on %s" % (prev_name, today),
                "Id": PKG_ID,
                "License": "GPL-2.0-or-later",
                "Name": PKG_NAME,
                "Version": "1.0",
            },
            "Keywords": "Desktop;Workspace;Appearance;Look and Feel;Previous;Restore;",
        }
        with open(os.path.join(tmp, "metadata.json"), "w", encoding="utf-8") as fh:
            json.dump(meta, fh, indent=4, ensure_ascii=False)
            fh.write("\n")
        for root, dirs, files in os.walk(tmp):
            os.chmod(root, 0o755)
            for f in files:
                os.chmod(os.path.join(root, f), 0o644)
        if os.path.exists(dest):
            shutil.rmtree(dest)
        os.rename(tmp, dest)
    except Exception:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    print("  wrote %s (%s, from %s)" % (dest, prev_name, origin))
    return 0


if __name__ == "__main__":
    sys.exit(main())
