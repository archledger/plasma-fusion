#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Accessibility lint (GAPS.md G25): every interactive item has a name for screen readers.

  tools/checks/a11y-lint.py [--warn] [PATH...]      default PATH: packages/

Findings, one per line as FILE:LINE: RULE message | source:
  control-name    a control (Button, ToolButton, CheckBox, Switch, Slider, SpinBox, ComboBox,
                  TextField, MenuItem, ItemDelegate, ...) with neither `Accessible.name` nor a
                  visible text that Qt Quick Controls turn into the name (`text` for buttons,
                  check boxes and delegates, `placeholderText` for text fields) nor a Kirigami
                  form label
  pointer-name    a MouseArea or TapHandler (the item's click target) where neither it nor its
                  parent or grandparent sets `Accessible.name`
  focus-name      an item with `activeFocusOnTab: true` and no `Accessible.name`
  component-name  a use of a package's own control (IconButton { ... }) that sets neither
                  `Accessible.name` nor the property its file names the control from (the
                  file's `Accessible.name: text` or `Accessible.name: tile.title`, or `text` for a
                  button root that names nothing): the definition leaves the name to its uses
Skipped: `Accessible.ignored: true` on the item or an ancestor, a MouseArea that takes no button
(`acceptedButtons: Qt.NoButton`, cursor and hover areas), `enabled: false`, read-only text.
A file's root object is a component definition: its name is checked at its uses (component-name),
not at the root.
Exit status: 1 when anything is found, 0 otherwise; with --warn always 0 (tools/build.sh).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qmlscan  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

TEXT_NAMED = {"AbstractButton", "Button", "ToolButton", "RoundButton", "DelayButton", "CheckBox", "CheckDelegate", "RadioButton",
              "RadioDelegate", "Switch", "SwitchDelegate", "ItemDelegate", "SwipeDelegate", "MenuItem", "TabButton",
              "BasicListItem", "SubtitleDelegate", "CheckSubtitleDelegate", "RadioSubtitleDelegate",
              "SwitchSubtitleDelegate", "Chip", "ActionToolBar"}
FIELDS = {"TextField", "TextArea", "SearchField", "PasswordField", "ActionTextField"}
NAME_ONLY = {"Slider", "RangeSlider", "Dial", "SpinBox", "ComboBox", "Tumbler", "TextInput", "TextEdit"}
POINTER = {"MouseArea", "TapHandler"}


def named(o):
    """True when the object gives itself an accessible name (Accessible.name, or a grouped
    `Accessible { name: ... }` child)."""
    if o.has("Accessible.name"):
        return True
    return any(c.short == "Accessible" and c.has("name") for c in o.children)


def ignored(o):
    for x in [o, *o.ancestors()]:
        if x.value("Accessible.ignored") == "true":
            return True
    return False


def literal_false(o, prop):
    return o.value(prop) in ("false",)


def name_props(roots):
    """For a component file: the properties of its root that its accessible name comes from, or
    None when the file names itself (or is not a control). "" stands for Accessible.name."""
    if not roots:
        return None
    root = roots[0]
    rid = root.value("id")
    props = set()
    for o in qmlscan.walk(roots):
        v = o.value("Accessible.name")
        m = re.fullmatch(r"(\w+)", v) if o is root else None
        m = m or (re.fullmatch(re.escape(rid) + r"\.(\w+)", v) if rid else None)
        if m and not v.startswith(("i18n", "qsTr")):
            props.add(m.group(1))
    # a property the component binds itself (`readonly property string name: model.display`)
    # needs nothing from its uses
    if any(root.has(p) and root.value(p) not in ('""', "''") for p in props):
        return None
    if not named(root):
        if root.short in TEXT_NAMED:
            props.add("text")
        elif root.short in FIELDS:
            props.update(("placeholderText", ""))
        elif root.short in NAME_ONLY:
            props.add("")
    return props or None


def check(o, components, is_root):
    """The rule and message for an unnamed interactive object, or None."""
    if ignored(o) or literal_false(o, "enabled") or literal_false(o, "visible"):
        return None
    s = o.short
    if "." not in o.type and s in components:
        props = components[s]
        if named(o) or any(p and o.has(p) for p in props):
            return None
        need = " or ".join(sorted(p or "Accessible.name" for p in props))
        return "component-name", f"{s} without {need} (its file names the control from it)"
    if is_root:
        return None
    if s in TEXT_NAMED or s in FIELDS or s in NAME_ONLY:
        if named(o) or o.has("Kirigami.FormData.label"):
            return None
        if s in TEXT_NAMED and o.has("text") and o.value("text") not in ('""', "''"):
            return None
        if s in FIELDS and o.has("placeholderText"):
            return None
        if s in ("TextInput", "TextEdit") and o.value("readOnly") == "true":
            return None
        what = "text" if s in TEXT_NAMED else ("placeholderText" if s in FIELDS else "")
        extra = f" or {what}" if what else ""
        return "control-name", f"{s} without Accessible.name{extra}"
    if s in POINTER:
        if s == "MouseArea" and "NoButton" in o.value("acceptedButtons"):
            return None
        chain = [o]
        p = o.parent
        for _ in range(2):
            if p is None:
                break
            chain.append(p)
            p = p.parent
        if any(named(x) for x in chain):
            return None
        # a control that holds the pointer area and names itself through its text
        if any(x.short in TEXT_NAMED and x.has("text") for x in chain[1:]):
            return None
        owner = chain[1].short if len(chain) > 1 else "the root"
        return "pointer-name", f"{s} in {owner}: neither it nor its parent or grandparent sets Accessible.name"
    if o.value("activeFocusOnTab") == "true" and not named(o):
        return "focus-name", f"{s} takes keyboard focus (activeFocusOnTab) without Accessible.name"
    return None


def package_dir(f):
    """The package a file belongs to: the nearest folder above it with a metadata.json (a
    Plasma or KWin package), else its own folder."""
    d = f.resolve().parent
    for p in [d, *d.parents]:
        if (p / "metadata.json").is_file():
            return p
    return d


def main(argv):
    warn = False
    if argv and argv[0] == "--warn":
        warn, argv = True, argv[1:]
    paths = argv or [os.path.join(ROOT, "packages")]
    findings = []
    files = []
    components = {}  # package folder -> {component name: name properties}
    for f in qmlscan.qml_files(paths):
        roots = qmlscan.scan(f.read_text(encoding="utf-8", errors="replace"))
        pkg = package_dir(f)
        files.append((f, pkg, roots))
        props = name_props(roots)
        if props:
            components.setdefault(pkg, {})[f.stem] = props
    for f, pkg, roots in files:
        path = str(f.resolve())
        rel = os.path.relpath(path, ROOT) if path.startswith(ROOT + os.sep) else str(f)
        for o in qmlscan.walk(roots):
            hit = check(o, components.get(pkg, {}), o is roots[0])
            if hit:
                findings.append((rel, o.line, hit[0], hit[1], path))
    findings.sort(key=lambda x: (x[0], x[1]))
    for rel, line, rule, msg, path in findings:
        print(f"{rel}:{line}: {rule} {msg} | {qmlscan.source_line(path, line)}")
    print(f"a11y-lint: {len(findings)} finding(s) in {len({x[0] for x in findings})} file(s)", file=sys.stderr)
    if warn:
        return 0
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
