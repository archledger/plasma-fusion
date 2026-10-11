#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Id scope lint: an id is used where QML cannot see it.

  tools/checks/id-scope-lint.py [--warn] [PATH...]      default PATH: packages/

An object declared as a component (a `Component { }`, the value of a component property such as
`delegate:`, `sourceComponent:`, `fullRepresentation:` or `compactRepresentation:`, a
`property Component name:` or an inline `component Name: Type { }`) gets its own id scope when it
is instantiated. Its own ids are not visible outside it: a binding there that names one fails at
run time with "ReferenceError: name is not defined", every time it is evaluated, and the value
behind it never arrives (the desktop's editingCards read homeLoader, an id inside its
fullRepresentation, from the containment's root). The item has to be reached through the
instance (a Loader's item, the applet's fullRepresentationItem with a property alias).

Findings, one per line as FILE:LINE: RULE message | source:
  id-scope    a name that is an id of an inner component, used outside that component

Ids of an enclosing scope stay visible inside a component, so those uses are not reported. A name
that the file also declares as a property, function, signal, parameter or JavaScript variable is
not reported either (it may be that). Reads after a "." (`item.name`) are member accesses.
Exit status: 1 when anything is found, 0 otherwise; with --warn always 0 (tools/build.sh).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qmlscan  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# Properties of type Component in Qt Quick, Plasma and Kirigami that hand-written QML assigns an
# object to (Item-typed properties such as a Page's header are not components and are left out).
COMPONENT_PROPS = {"delegate", "sourceComponent", "fullRepresentation", "compactRepresentation",
                   "appletContainerComponent", "highlight", "component"}
DECLARERS = {"property", "signal", "function", "let", "const", "var", "alias", "readonly",
             "required", "default", "import", "as", "on", "pragma", "component"}


class Frame:
    def __init__(self, kind, scope, opens=False):
        self.kind = kind    # "obj", "group" or "js"
        self.scope = scope
        # A `Component { }`: its own id belongs to the enclosing scope, the object it holds starts
        # the component's scope.
        self.opens = opens


def scan(text):
    """[(line, name, scope)] for the names read, {scope: parent scope}, {name: {scopes}} of the
    ids and the set of names the file declares otherwise."""
    src = qmlscan.strip_comments(text)
    toks = qmlscan.tokens(src)
    parents = {0: None}
    ids = {}
    declared = set()
    uses = []
    stack = []
    next_scope = 1

    def starts_statement(i):
        if i == 0:
            return True
        prev = toks[i - 1]
        return prev[1] in qmlscan.STATEMENT_START or prev[2] < toks[i][2]

    def scope_here():
        return stack[-1].scope if stack else 0

    for i, (kind, t, ln, _end) in enumerate(toks):
        top = stack[-1] if stack else None
        in_object = top is None or top.kind == "obj"
        prev = toks[i - 1] if i > 0 else None
        if t == "{":
            frame = Frame("js", scope_here())
            if prev is not None and prev[0] == "id" and in_object:
                if i >= 3 and toks[i - 2][1] == "on" and toks[i - 3][0] == "id":
                    type_, first = toks[i - 3][1], i - 3
                else:
                    type_, first = prev[1], i - 1
                before = toks[first - 1][1] if first > 0 else ""
                returns = before == ":" and first >= 2 and toks[first - 2][1] == ")"
                if type_.split(".")[-1][:1].isupper() and before not in ("function", "new", "class", ".") and not returns:
                    holder = type_.split(".")[-1] == "Component"
                    is_component = top is not None and top.opens
                    if not holder and before == ":" and first >= 2 and toks[first - 2][0] == "id":
                        name = toks[first - 2][1].split(".")[-1]
                        lead = [toks[k][1] for k in range(max(0, first - 4), first - 2)]
                        is_component |= name in COMPONENT_PROPS
                        is_component |= lead == ["property", "Component"]
                        is_component |= lead[-1:] == ["component"]
                    scope = scope_here()
                    if is_component or top is None:
                        scope = 0 if top is None and not stack else next_scope
                        if scope:
                            parents[scope] = scope_here()
                            next_scope += 1
                    frame = Frame("obj", scope, holder)
                elif top is not None and top.kind == "obj" and starts_statement(i - 1):
                    frame = Frame("group", top.scope)
            stack.append(frame)
            continue
        if t == "}":
            if stack:
                stack.pop()
            continue
        if kind != "id":
            continue
        name = t.split(".")[0]
        nxt = toks[i + 1][1] if i + 1 < len(toks) else ""
        before = toks[i - 2][1] if i >= 2 else ""
        if prev is not None and prev[1] in DECLARERS:
            declared.add(name)
            continue
        # A typed declaration (`property bool name`, `signal s(string name)`) or a parameter
        # (`function f(name: int)`, `(a, b) =>`).
        if prev is not None and prev[0] == "id" and (before in ("property", "readonly", "required", "default")
                                                     or before in ("(", ",")):
            declared.add(name)
            continue
        if nxt == ":" and prev is not None and prev[1] in ("(", ","):
            declared.add(name)
            continue
        if nxt == "=>" or (nxt in (",", ")") and _in_arrow_params(toks, i)):
            declared.add(name)
            continue
        if prev is not None and prev[1] == ":" and before == "id":
            continue
        if t == "id" and nxt == ":" and (top is None or top.kind != "js"):
            if i + 2 < len(toks) and toks[i + 2][0] == "id":
                ids.setdefault(toks[i + 2][1], set()).add(scope_here())
            continue
        if prev is not None and prev[1] == ".":
            continue
        # A binding (`text: ...`): the name is a property of some type here, and an unqualified
        # read of it may be that property of the scope object.
        if nxt == ":" and (top is None or top.kind != "js") and starts_statement(i):
            declared.add(name)
            continue
        if nxt in (":", "{") or nxt == "on":
            continue
        uses.append((ln, name, scope_here()))
    return uses, parents, ids, declared


def _in_arrow_params(toks, i):
    """True when the token at i sits in a parenthesised list followed by `=>` or opened by
    `function name(`."""
    depth, j = 0, i
    while j < len(toks):
        t = toks[j][1]
        if t == "(":
            depth += 1
        elif t == ")":
            if depth == 0:
                return j + 1 < len(toks) and toks[j + 1][1] == "=>"
            depth -= 1
        elif t in ("{", "}", ";"):
            return False
        j += 1
    return False


def chain(scope, parents):
    while scope is not None:
        yield scope
        scope = parents.get(scope)


def findings(text):
    uses, parents, ids, declared = scan(text)
    out = []
    for ln, name, scope in uses:
        where = ids.get(name)
        if not where or name in declared:
            continue
        if where & set(chain(scope, parents)):
            continue
        out.append((ln, f"'{name}' is an id inside a component; it is not defined here (ReferenceError at run time)"))
    return out


def main(argv):
    warn = False
    if argv and argv[0] == "--warn":
        warn, argv = True, argv[1:]
    paths = argv or [os.path.join(ROOT, "packages")]
    found = []
    for f in qmlscan.qml_files(paths):
        path = str(f.resolve())
        rel = os.path.relpath(path, ROOT) if path.startswith(ROOT + os.sep) else str(f)
        for ln, msg in findings(f.read_text(encoding="utf-8", errors="replace")):
            found.append((rel, ln, msg, path))
    found.sort(key=lambda x: (x[0], x[1]))
    for rel, ln, msg, path in found:
        print(f"{rel}:{ln}: id-scope {msg} | {qmlscan.source_line(path, ln)}")
    print(f"id-scope-lint: {len(found)} finding(s) in {len({x[0] for x in found})} file(s)", file=sys.stderr)
    if warn:
        return 0
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
