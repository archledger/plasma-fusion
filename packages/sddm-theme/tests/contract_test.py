#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Contract checks for Plasma Fusion's SDDM theme (packages/sddm-theme/).

SDDM reads metadata.desktop for the theme's identity (docs/THEMING.md) and theme.conf for its
options (GreeterApp.cpp: ThemeConfig from the metadata's ConfigFile). The theme takes no QML
import beyond QtQuick and its own files - a login screen must survive missing optional modules.
These checks run in CI (tools/build.d/91-sddm.sh) and fail on the version before each fix.

    tests/contract_test.py [STAGE]     STAGE = build.sh's OUT (default: a throw-away build)
"""

import ast
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent.parent
REPO = HERE.parent.parent


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ((" - " + detail) if detail and not ok else ""))
    return ok


def main() -> int:
    own_tmp = None
    stage = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if stage is None:
        own_tmp = tempfile.mkdtemp(prefix="sddm-contract-")
        stage = pathlib.Path(own_tmp) / "stage"
    ok = True
    try:
        built = subprocess.run([str(HERE / "build.sh"), str(stage)],
                               capture_output=True, text=True)
        ok &= check("build.sh stages the theme", built.returncode == 0, built.stderr[-400:])

        theme = stage / "plasmafusion"
        for name in ("Main.qml", "palette.js", "LoginCard.qml", "UserSwitcher.qml",
                     "SessionPill.qml", "PowerBar.qml", "CircularImage.qml", "MessageView.qml", "metadata.desktop",
                     "theme.conf", "preview.webp"):
            ok &= check(f"the theme ships {name}", (theme / name).is_file())

        # metadata.desktop: the identity SDDM reads (docs/THEMING.md; KDE's Breeze theme)
        meta = (theme / "metadata.desktop").read_text() if (theme / "metadata.desktop").is_file() else ""
        for key, want in (("Type", "sddm-theme"), ("MainScript", "Main.qml"),
                          ("ConfigFile", "theme.conf"), ("Theme-Id", "plasmafusion"),
                          ("QtVersion", "6")):
            ok &= check(f"metadata {key}={want}",
                        re.search(rf"^{key}={re.escape(want)}$", meta, re.M) is not None)
        ok &= check("metadata has MainScript and ConfigFile pointing at shipped files",
                    (theme / "Main.qml").is_file() and (theme / "theme.conf").is_file())

        # theme.conf: the one option the theme reads, substituted with a real path
        conf = (theme / "theme.conf").read_text() if (theme / "theme.conf").is_file() else ""
        m = re.search(r"^background=(.+)$", conf, re.M)
        ok &= check("theme.conf sets background", m is not None)
        if m:
            ok &= check("theme.conf's background is an absolute path",
                        m.group(1).startswith("/"), m.group(1))
        ok &= check("theme.conf carries no unsubstituted placeholder", "@BACKGROUND@" not in conf)

        # Split the marker so REUSE does not parse the test string as this file's license.
        doc_license = "SPDX-" + "License-Identifier: CC-BY-SA-4.0"
        for doc in ("docs/parts/sddm.md", "packages/sddm-theme/README.md"):
            ok &= check(f"{doc} uses the documentation license",
                        doc_license in (REPO / doc).read_text().splitlines()[:8])
        copyright_stanzas = (REPO / "packaging/debian/copyright").read_text().split("\n\n")
        ok &= check("Debian groups the SDDM README under the documentation license",
                    any(stanza.startswith("Files:") and "packages/sddm-theme/README.md" in stanza
                        and "License: CC-BY-SA-4.0" in stanza for stanza in copyright_stanzas))
        system_doc = (REPO / "docs/parts/system.md").read_text()
        ok &= check("the system part documents the required SDDM install input", "--sddm" in system_doc)
        ok &= check("the system part lists the installed SDDM theme tree",
                    "/usr/share/sddm/themes/plasmafusion/" in system_doc)

        # Debian-family distributions split PySide6 by module. The normal build runs the
        # behavior suite, so every module it imports must be declared even on a headless builder.
        control = (REPO / "packaging/debian/control").read_text().split("\n\n", 1)[0]
        field = re.search(r"(?m)^Build-Depends:([^\n]*(?:\n[ \t]+[^\n]*)*)", control)
        dependencies = field.group(1) if field else ""
        behavior = ast.parse((HERE / "tests/behavior_test.py").read_text())
        modules = sorted({node.module.split(".")[1] for node in ast.walk(behavior)
                          if isinstance(node, ast.ImportFrom) and node.module and
                          node.module.startswith("PySide6.")})
        for module in modules:
            dependency = "python3-pyside6." + module.lower()
            ok &= check(f"Debian Build-Depends declares {dependency}",
                        dependency in dependencies)
        ok &= check("Debian Build-Depends declares the QtQuick QML module",
                    "qml6-module-qtquick" in dependencies)

        # Exercise each channel's actual builder invocation, not a hand-written equivalent:
        # build.sh takes a root and appends plasmafusion, while install-tree takes the theme.
        for channel, file in (("Fedora", "packaging/fedora/plasma-fusion.spec"),
                              ("Arch", "packaging/arch/PKGBUILD"),
                              ("Debian", "packaging/debian/rules"),
                              ("NixOS", "packaging/nix/plasma-fusion.nix")):
            line = next(s.strip() for s in (REPO / file).read_text().splitlines()
                        if s.strip().startswith("bash packages/sddm-theme/build.sh "))
            with tempfile.TemporaryDirectory(prefix="sddm-package-") as package_root:
                line = (line.replace("$(CURDIR)", package_root).replace("$PWD", package_root)
                        .replace("$srcdir", package_root)
                        .replace("${sw}", "/run/current-system/sw"))
                run = subprocess.run(shlex.split(line), cwd=REPO, capture_output=True, text=True)
                out = pathlib.Path(package_root) / ("sddm" if channel == "Arch" else "_sddm")
                ok &= check(f"{channel}'s builder supplies the installer's theme directory",
                            run.returncode == 0 and (out / "plasmafusion/metadata.desktop").is_file(),
                            run.stderr[-400:])
                if channel == "NixOS":
                    configs = list(out.rglob("theme.conf"))
                    ok &= check("NixOS background names the system profile, not /usr/share",
                                len(configs) == 1 and
                                "background=/run/current-system/sw/share/plasma-fusion/backgrounds/"
                                in configs[0].read_text())

        # The theme stays dependency-free: QtQuick and its own files only
        imports = []
        for qml in theme.glob("*.qml"):
            imports += re.findall(r'^import\s+(\S+)', qml.read_text(), re.M)
        bad = sorted({i for i in imports if not (i.startswith('"') or i == "QtQuick")})
        ok &= check("the QML imports only QtQuick and the theme's own files", not bad, ", ".join(bad))

        # The QML parses: qmllint when it is installed, else a balanced-brace read
        lint = shutil.which("qmllint")
        if lint:
            for qml in sorted(theme.glob("*.qml")):
                run = subprocess.run([lint, str(qml)], capture_output=True, text=True)
                clean = run.returncode == 0 and not re.search(r"error", run.stdout + run.stderr, re.I)
                ok &= check(f"qmllint {qml.name}", clean, (run.stdout + run.stderr)[-300:])
        else:
            for qml in sorted(theme.glob("*.qml")):
                text = qml.read_text()
                ok &= check(f"{qml.name} has balanced braces",
                            text.count("{") == text.count("}"), qml.name)

        # build.sh is reproducible; the second build and its comparison live in a directory this
        # invocation owns, so an explicitly given stage never has siblings removed under it
        again_root = pathlib.Path(tempfile.mkdtemp(prefix="sddm-again-"))
        try:
            built2 = subprocess.run([str(HERE / "build.sh"), str(again_root)],
                                    capture_output=True, text=True)
            same = built2.returncode == 0
            if same:
                for f in sorted(theme.iterdir()):
                    twin = again_root / "plasmafusion" / f.name
                    same &= twin.is_file() and twin.read_bytes() == f.read_bytes()
            ok &= check("two builds are byte-identical", same)
        finally:
            shutil.rmtree(again_root, ignore_errors=True)
    finally:
        if own_tmp:
            shutil.rmtree(own_tmp, ignore_errors=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
