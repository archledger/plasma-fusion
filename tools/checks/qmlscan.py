# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A small QML object-tree scanner for the checks in tools/checks/ (standard library only).

It is not a QML parser: it strips comments, tokenizes, and follows braces well enough to tell
object declarations (`Type {`, `Type on prop {`) from JavaScript blocks and grouped properties
(`anchors { ... }`), and records each object's type, line, parent and property bindings
(`name: value`, with the rest of the value's first line). Good enough for lint rules on
hand-written Plasma QML; unknown syntax degrades to "JavaScript block", never to a crash.
"""
import pathlib
import re

TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)
  | (?P<num>\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
  | (?P<id>[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)
  | (?P<punct>=>|[{}():;,?=\[\]<>+\-*/%!&|.])
  | (?P<other>.)
""", re.X | re.S)

STATEMENT_START = ("{", "}", ";")


def expression(value):
    """A binding value's first line without what follows the binding on that line (`; next: 1`
    or the object's closing `}`); brackets and strings are respected."""
    v = value.strip()
    depth, quote = 0, None
    for k, c in enumerate(v):
        if quote:
            if c == quote:
                quote = None
        elif c in "\"'`":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif c == "}":
            if depth <= 0:
                return v[:k].strip()
            depth -= 1
        elif c == ";" and depth <= 0:
            return v[:k].strip()
    return v


def strip_comments(text):
    """The text with // and /* */ comments blanked out (newlines kept, so line numbers hold);
    string literals stay whole."""
    out, i, n, quote = [], 0, len(text), None
    while i < n:
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == quote or (c == "\n" and quote != "`"):
                quote = None
        elif c in "\"'`":
            quote = c
            out.append(c)
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            end = n if j < 0 else j + 2
            out.append("\n" * text.count("\n", i, end))
            i = end
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


class Obj:
    """One QML object declaration."""

    def __init__(self, type_, line, parent, on=None):
        self.type = type_
        self.short = type_.split(".")[-1]
        self.line = line
        self.parent = parent
        self.on = on            # "x" for `Behavior on x {`
        self.props = {}         # binding name -> (line, rest of the value's first line)
        self.children = []

    def has(self, name):
        return name in self.props

    def value(self, name):
        """The binding's expression on its first line, up to a `;` or `}` that ends it."""
        return expression(self.props.get(name, (0, ""))[1])

    def ancestors(self):
        p = self.parent
        while p is not None:
            yield p
            p = p.parent


def tokens(src):
    out = []
    line = 1
    for m in TOKEN.finditer(src):
        kind = m.lastgroup
        t = m.group()
        if kind != "ws":
            out.append((kind, t, line, m.end()))
        line += t.count("\n")
    return out


def scan(text):
    """The top-level objects (normally one root) of a QML source text."""
    src = strip_comments(text)
    toks = tokens(src)
    roots = []
    stack = []  # Obj, ("group", name, owner Obj) or "js"

    def owner():
        for f in reversed(stack):
            if isinstance(f, Obj):
                return f
        return None

    def starts_statement(i):
        if i == 0:
            return True
        prev = toks[i - 1]
        return prev[1] in STATEMENT_START or prev[2] < toks[i][2]

    for i, (kind, t, ln, end) in enumerate(toks):
        top = stack[-1] if stack else None
        in_object = top is None or isinstance(top, Obj)
        if t == "{":
            prev = toks[i - 1] if i > 0 else None
            frame = "js"
            if prev is not None and prev[0] == "id" and in_object:
                if i >= 3 and toks[i - 2][1] == "on" and toks[i - 3][0] == "id":
                    type_, on, first = toks[i - 3][1], prev[1], i - 3
                else:
                    type_, on, first = prev[1], None, i - 1
                before = toks[first - 1][1] if first > 0 else ""
                # `function f(a): Type {` is a return type annotation, not an object
                returns = before == ":" and first >= 2 and toks[first - 2][1] == ")"
                if type_.split(".")[-1][:1].isupper() and before not in ("function", "new", "class", ".") and not returns:
                    parent = top if isinstance(top, Obj) else None
                    frame = Obj(type_, toks[first][2], parent, on)
                    (parent.children if parent else roots).append(frame)
                elif isinstance(top, Obj) and on is None and starts_statement(i - 1):
                    frame = ("group", prev[1], top)
            stack.append(frame)
            continue
        if t == "}":
            if stack:
                stack.pop()
            continue
        # A binding `name: value` at object level (or inside a grouped property).
        if kind == "id" and i + 1 < len(toks) and toks[i + 1][1] == ":" and (
                isinstance(top, Obj) or (isinstance(top, tuple) and top[0] == "group")):
            decl = i >= 2 and (toks[i - 2][1] == "property" or toks[i - 1][1] == "property")
            if starts_statement(i) or decl:
                name, target = t, top
                if isinstance(top, tuple):
                    name, target = top[1] + "." + t, top[2]
                colon_end = toks[i + 1][3]
                eol = src.find("\n", colon_end)
                value = src[colon_end:eol if eol >= 0 else len(src)]
                target.props.setdefault(name, (ln, value))
    return roots


def walk(objs):
    for o in objs:
        yield o
        yield from walk(o.children)


def upstream_files(path):
    """Files a forked upstream package lists in its UPSTREAM-FILES manifest (one path per line,
    relative to the manifest; # comments). They keep upstream's code and are linted upstream; the
    package's own files and the upstream files it changes for Plasma Fusion stay unlisted."""
    path = pathlib.Path(path).resolve()
    for parent in path.parents:
        manifest = parent / "UPSTREAM-FILES"
        if manifest.is_file():
            listed = set()
            for line in manifest.read_text(encoding="utf-8").splitlines():
                line = line.split("#", 1)[0].strip()
                if line:
                    listed.add((parent / line).resolve())
            return path in listed
        if parent.name == "packages":
            break
    return False


def qml_files(paths, exclude=()):
    for p in paths:
        p = pathlib.Path(p)
        files = [p] if p.is_file() else sorted(p.rglob("*.qml"))
        for f in files:
            if f.suffix == ".qml" and not any(part in exclude for part in f.parts) and not upstream_files(f):
                yield f


def source_line(path, line):
    try:
        return pathlib.Path(path).read_text(encoding="utf-8", errors="replace").split("\n")[line - 1].strip()
    except (OSError, IndexError):
        return ""
