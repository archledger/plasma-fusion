#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Tables of the coverage measurement (run by tools/tests/coverage.sh).

    coverage_summary.py --root REPO --out DIR

Reads what coverage.sh left in DIR (coverage.py data, kcov's merged report, node's lcov, gcovr's
JSON, tests.tsv) and writes DIR/summary.md and DIR/summary.json: per language the statements (or
lines, for the tools that count lines) of the repository's files and how many the tests ran, for
product code, maintainer tools and test tooling apart, per area, and the files with the most
statements not run.

The file list is the repository's tracked files (git ls-files), so a file no test starts counts
with all of its statements. Test tooling: everything below a tests/, test/ or vsession/
directory, tools/tests/, tools/vsession/, tools/container/, generators/icons/vsession-*, and the
checking aids a person runs by hand to compare built output with the design boards or to measure
it (TEST_RE): generators/cursors/sheet.py, generators/icons/compare_boards.py, the decoration's
tools/shadow-alpha.py, tools/sheet.py and tools/run-preview.sh, and tools/device/power-ab.sh.
Maintainer tools: the programs run by hand to regenerate committed tables and files, and the
package build scripts (packaging/build-rpm.sh, which the build workflow also runs, and the
compiled parts' build-rpm.sh and container-build.sh); neither tools/build.sh nor the package runs
them (MAINT_RE). Everything else is product code: what tools/build.sh runs and what the packages
install. Within product code, the build and lint scripts (BUILD_RE) run whenever the build
runs, so the summary also gives the product figures without them.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys

TEST_RE = re.compile(r"(^|/)(tests?|vsession)/|^tools/(tests|vsession|container)/|^generators/icons/vsession-"
                     r"|^generators/cursors/sheet\.py$|^generators/icons/compare_boards\.py$"
                     r"|^packages/decoration-cpp/tools/(shadow-alpha\.py|sheet\.py|run-preview\.sh)$"
                     r"|^tools/device/power-ab\.sh$")
MAINT_RE = re.compile(r"^generators/icons/(make_[a-z_]+|coverage_report)\.py$|^generators/fonts/make_static\.py$"
                      r"|^generators/look-and-feel/previews\.py$|^packaging/build-rpm\.sh$"
                      r"|^packages/[a-z-]+/(tools/)?(build-rpm|container-build)\.sh$")
BUILD_RE = re.compile(r"^tools/(build\.sh$|build\.d/|build-lib/|checks/)|^generators/[a-z-]+/build\.sh$")
KINDS = ("product", "maintainer", "tests")


def tracked_files(root):
    try:
        out = subprocess.run(["git", "-c", f"safe.directory={root}", "-C", root, "ls-files", "-z"],
                             check=True, capture_output=True).stdout
        return sorted(f for f in out.decode().split("\0") if f and os.path.isfile(os.path.join(root, f)))
    except (OSError, subprocess.CalledProcessError):
        files = []
        for d, dirs, names in os.walk(root):
            # not the build output, nor hidden directories (.git, other working trees)
            dirs[:] = [x for x in dirs if not (d == root and (x in ("build", "stage") or x.startswith(".")))]
            files += [os.path.relpath(os.path.join(d, n), root) for n in names]
        return sorted(files)


def shebang(path):
    try:
        with open(path, "rb") as f:
            line = f.readline(200)
    except OSError:
        return ""
    return line.decode("utf-8", "replace") if line.startswith(b"#!") else ""


def language(root, rel):
    ext = os.path.splitext(rel)[1]
    if ext == ".py":
        return "python"
    if ext == ".sh":
        return "shell"
    if ext == ".js":
        return "js"
    if ext == ".qml":
        return "qml"
    if ext in (".cpp", ".h"):
        return "cpp"
    if not ext:
        line = shebang(os.path.join(root, rel))
        if "python" in line:
            return "python"
        if re.search(r"\b(bash|sh)\b", line):
            return "shell"
    return None


def kind(rel):
    return "tests" if TEST_RE.search(rel) else "maintainer" if MAINT_RE.search(rel) else "product"


def area(rel):
    parts = rel.split("/")
    if parts[0] in ("generators", "packages", "tools") and len(parts) > 2:
        return "/".join(parts[:2])
    return parts[0] if len(parts) > 1 else "(top)"


def code_line_numbers(path):
    """Line numbers of the non-blank lines that are not only a comment (// or /* */): the code
    lines of a JavaScript or QML file."""
    lines, block = set(), False
    with open(path, encoding="utf-8", errors="replace") as f:
        for number, line in enumerate(f, 1):
            s = line.strip()
            if block:
                if "*/" in s:
                    block = False
                continue
            if not s or s.startswith("//"):
                continue
            if s.startswith("/*"):
                block = "*/" not in s
                continue
            lines.add(number)
    return lines


def code_lines(path):
    return len(code_line_numbers(path))


def python_results(root, out, files):
    rc = os.path.join(out, "python", "coveragerc")
    if not os.path.exists(rc):
        return None
    import coverage
    cov = coverage.Coverage(config_file=rc)
    cov.load()
    res = {}
    for rel in files:
        path = os.path.join(root, rel)
        try:
            _, stmts, _, missing, _ = cov.analysis2(path)
        except Exception as e:  # not Python 3 source, or unreadable: listed, not counted
            res[rel] = {"error": f"{type(e).__name__}: {e}"}
            continue
        res[rel] = {"total": len(stmts), "covered": len(stmts) - len(missing)}
    return res


def shell_results(root, out, files):
    path = os.path.join(out, "shell", "merged", "kcov-merged", "coverage.json")
    if not os.path.exists(path):
        return None
    data = json.load(open(path))
    seen = {}
    for f in data.get("files", []):
        rel = os.path.relpath(os.path.realpath(f["file"]), os.path.realpath(root))
        seen[rel] = {"total": int(f["total_lines"]), "covered": int(f["covered_lines"])}
    res = {}
    for rel in files:
        res[rel] = seen.get(rel, {"error": "not in kcov's report"})
    return res


def js_results(root, out, files):
    """node's lcov counts every line of a file, blank and comment lines too; only the code lines
    (code_line_numbers) are counted here. node writes paths relative to its working directory,
    the repository."""
    path = os.path.join(out, "js", "lcov.info")
    if not os.path.exists(path):
        return None
    hits, cur = {}, None
    for line in open(path):
        line = line.strip()
        if line.startswith("SF:"):
            p = line[3:] if os.path.isabs(line[3:]) else os.path.join(root, line[3:])
            cur = os.path.relpath(os.path.realpath(p), os.path.realpath(root))
            hits[cur] = {}
        elif line.startswith("DA:") and cur:
            number, count = line[3:].split(",")[:2]
            hits[cur][int(number)] = int(count)
    res = {}
    for rel in files:
        if rel in hits:
            code = code_line_numbers(os.path.join(root, rel))
            res[rel] = {"total": len(code), "covered": sum(1 for n in code if hits[rel].get(n, 0) > 0)}
        else:  # counted with all of its code lines not run
            res[rel] = {"total": code_lines(os.path.join(root, rel)), "covered": 0, "note": "no node test loads it"}
    return res


def cpp_results(root, out, files):
    res, packages = {}, []
    for name in sorted(os.listdir(out)):
        path = os.path.join(out, name, "gcovr.json")
        if not (name.startswith("cpp-") and os.path.exists(path)):
            continue
        pkg = name[4:]
        packages.append(pkg)
        data = json.load(open(path))
        for f in data.get("files", []):
            rel = os.path.relpath(os.path.realpath(os.path.join(root, f["file"])), os.path.realpath(root))
            lines = {}
            for ln in f.get("lines", []):
                if ln.get("gcovr/noncode") or ln.get("gcovr/excluded"):
                    continue
                lines[ln["line_number"]] = lines.get(ln["line_number"], 0) + int(ln.get("count", 0))
            res[rel] = {"total": len(lines), "covered": sum(1 for c in lines.values() if c > 0), "package": pkg}
    if not packages:
        return None, []
    for rel in files:
        pkg = rel.split("/")[1] if rel.startswith("packages/") else ""
        if pkg in packages and rel.startswith(f"packages/{pkg}/src/") and rel not in res:
            res[rel] = {"error": "no code lines in gcovr's report", "package": pkg}
    return res, packages


def pct(c, t):
    return f"{100.0 * c / t:.1f} %" if t else "-"


def cell(c, t):
    return f"{pct(c, t)} ({c:,} of {t:,})" if t else "-"


def totals(res, files, which):
    c = t = n = 0
    for rel in files:
        r = res.get(rel, {})
        if "total" in r and (which == "all" or kind(rel) == which):
            c, t, n = c + r["covered"], t + r["total"], n + 1
    return c, t, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    root, out = os.path.realpath(a.root), os.path.realpath(a.out)

    by_lang = {}
    for rel in tracked_files(root):
        lang = language(root, rel)
        if lang:
            by_lang.setdefault(lang, []).append(rel)

    results = {}
    py = python_results(root, out, by_lang.get("python", []))
    if py is not None:
        results["python"] = py
    sh = shell_results(root, out, by_lang.get("shell", []))
    if sh is not None:
        results["shell"] = sh
    js = js_results(root, out, by_lang.get("js", []))
    if js is not None:
        results["js"] = js
    cpp, cpp_packages = cpp_results(root, out, by_lang.get("cpp", []))
    if cpp is not None:
        results["cpp"] = cpp

    tests = []
    tsv = os.path.join(out, "tests.tsv")
    if os.path.exists(tsv):
        for line in open(tsv):
            name, rc, secs = line.rstrip("\n").split("\t")
            tests.append({"test": name, "exit": int(rc), "seconds": int(secs)})

    def git(*args):
        try:
            return subprocess.run(["git", "-c", f"safe.directory={root}", "-C", root, *args], check=True,
                                  capture_output=True, text=True).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            return "unknown"

    def version(cmd):
        try:
            return subprocess.run(cmd, capture_output=True, text=True).stdout.strip().splitlines()[0]
        except (OSError, IndexError):
            return "not installed"

    when = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    tools = {"python": version([sys.executable, "-m", "coverage", "--version"]).split(" with ")[0],
             "shell": version(["kcov", "--version"]), "js": "node " + version(["node", "--version"]),
             "cpp": version(["gcovr", "--version"])}
    names = {"python": ("Python", "coverage.py, statements"), "shell": ("Shell (bash)", "kcov, lines"),
             "js": ("JavaScript", "node --experimental-test-coverage, code lines"),
             "cpp": ("C++", "gcov + gcovr, lines"), "qml": ("QML", "no usable tool (docs/parts/coverage.md)")}

    md = ["# Statement coverage", "",
          f"Commit {git('rev-parse', '--short=7', 'HEAD')}, measured {when} by tools/tests/coverage.sh "
          f"({'; '.join(tools[k] for k in results)}).", "",
          "| Language | Tool, unit | Product code | Maintainer tools | Test tooling | All |",
          "|---|---|---|---|---|---|"]
    summary = {"commit": git("rev-parse", "HEAD"), "measured": when, "tools": tools, "languages": {}, "tests": tests}
    for lang in ("python", "shell", "js", "cpp"):
        if lang not in results:
            continue
        res, files = results[lang], by_lang.get(lang, [])
        if lang == "cpp":
            files = [f for f in files if f in res]
        row = {w: totals(res, files, w) for w in KINDS + ("all",)}
        label = names[lang][0] + (f" ({', '.join(cpp_packages)})" if lang == "cpp" else "")
        md.append(f"| {label} | {names[lang][1]} | " + " | ".join(cell(*row[w][:2]) for w in KINDS + ("all",)) + " |")
        summary["languages"][lang] = {
            "totals": {w: {"covered": c, "total": t, "files": n} for w, (c, t, n) in row.items()},
            "files": {rel: res[rel] for rel in files if rel in res}}
    qml = by_lang.get("qml", [])
    qml_lines = sum(code_lines(os.path.join(root, f)) for f in qml)
    md.append(f"| QML | {names['qml'][1]} | not measured ({len(qml)} files, about {qml_lines:,} code lines) | | | |")
    summary["languages"]["qml"] = {"files": len(qml), "approx_code_lines": qml_lines}

    # Product code without the build and lint scripts (BUILD_RE), which run whenever the build runs.
    build_rows = []
    for lang in ("python", "shell", "js", "cpp"):
        if lang not in results:
            continue
        res = results[lang]
        rest = [f for f in by_lang.get(lang, []) if kind(f) == "product" and not BUILD_RE.search(f)]
        c, t, n = totals(res, rest, "product")
        if (c, t) != tuple(summary["languages"][lang]["totals"]["product"][k] for k in ("covered", "total")):
            build_rows.append(f"- {names[lang][0]}: {cell(c, t)}")
        summary["languages"][lang]["totals"]["product_without_build"] = {"covered": c, "total": t, "files": n}
    if build_rows:
        md += ["", "Product code without the build and lint scripts, which run whenever the build "
               "runs (`tools/build.sh`, `tools/build.d/`, `tools/build-lib/`, `tools/checks/`, "
               "`generators/*/build.sh`):", ""] + build_rows

    if tests:
        md += ["", "## Tests run", "", "| Test | Exit status | Seconds |", "|---|---|---|"]
        md += [f"| {t['test']} | {t['exit']} | {t['seconds']} |" for t in tests]

    for lang in ("python", "shell", "js", "cpp"):
        if lang not in results:
            continue
        res = results[lang]
        files = [f for f in by_lang.get(lang, []) if f in res]
        areas = {}
        for rel in files:
            r = res[rel]
            if kind(rel) != "product" or "total" not in r:
                continue
            ar = areas.setdefault(area(rel), [0, 0, 0])
            ar[0] += 1
            ar[1] += r["total"]
            ar[2] += r["covered"]
        unit = "Statements" if lang == "python" else "Lines"
        if areas:
            md += ["", f"## {names[lang][0]}: product code by area", "",
                   f"| Area | Files | {unit} | Run | % |", "|---|---|---|---|---|"]
            for k, (n, t, c) in sorted(areas.items(), key=lambda kv: -kv[1][1]):
                md.append(f"| {k} | {n} | {t:,} | {c:,} | {pct(c, t)} |")
        missing = [(rel, r) for rel, r in res.items() if "error" in r and rel in files]
        if missing:
            md += ["", f"{names[lang][0]} files without a measurement (not counted):", ""]
            md += [f"- `{rel}`: {r['error']}" for rel, r in missing]
        unrun = [(rel, r) for rel, r in res.items() if "note" in r and rel in files]
        if unrun:
            md += ["", f"{names[lang][0]} files counted with every code line not run:", ""]
            md += [f"- `{rel}` ({r['total']} code lines): {r['note']}" for rel, r in unrun]

    gaps = []
    for lang, res in results.items():
        for rel, r in res.items():
            if "total" in r and kind(rel) == "product":
                gaps.append((r["total"] - r["covered"], r["total"], rel, names[lang][0]))
    gaps.sort(reverse=True)
    if gaps:
        md += ["", "## Product code: the 25 files with the most statements or lines not run", "",
               "| File | Language | Not run | Statements or lines | Run |", "|---|---|---|---|---|"]
        for miss, t, rel, lang in gaps[:25]:
            md.append(f"| `{rel}` | {lang} | {miss:,} | {t:,} | {pct(t - miss, t)} |")

    with open(os.path.join(out, "summary.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    with open(os.path.join(out, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1, sort_keys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
