#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ClusterFuzzLite build (docs/parts/ci.md, "Fuzzing"), run by OSS-Fuzz's compile in the image of
# .clusterfuzzlite/Dockerfile with the source in $SRC/plasma-fusion. Each fuzz/*_fuzzer.py becomes a
# PyInstaller package in $OUT (compile_python_fuzzer) that ships the tool the fuzzer names in its
# TOOL line as data at the same path (fuzz/load_tool.py finds it below sys._MEIPASS), with the
# standard modules the tool imports (PyInstaller does not look inside a data file), next to the
# fuzzer's seed corpus and dictionary.
set -euo pipefail
cd "$SRC/plasma-fusion"
for fuzzer in fuzz/*_fuzzer.py; do
  name=$(basename "$fuzzer" .py)
  tool=$(sed -n 's/^TOOL = "\(.*\)"$/\1/p' "$fuzzer")
  [ -n "$tool" ] && [ -f "$tool" ] || { echo "build.sh: $fuzzer names no tool (TOOL = \"path\")" >&2; exit 1; }
  python3 - "$tool" >"$WORK/$name.imports" <<'PY'
import ast, importlib.util, sys
names = set()
for node in ast.walk(ast.parse(open(sys.argv[1], encoding="utf-8").read())):
    if isinstance(node, ast.Import):
        names.update(a.name for a in node.names)
    elif isinstance(node, ast.ImportFrom) and node.module and not node.level:
        names.add(node.module)
for name in sorted(names):
    if importlib.util.find_spec(name.split(".")[0]):   # PIL and PySide6 draw icons; not fuzzed, not here
        print("--hidden-import=" + name)
PY
  mapfile -t imports <"$WORK/$name.imports"
  compile_python_fuzzer "$fuzzer" --add-data "$tool:$(dirname "$tool")" "${imports[@]}"
  zip -q -j "$OUT/${name}_seed_corpus.zip" "fuzz/corpus/$name"/*
  cp "fuzz/$name.dict" "$OUT/$name.dict"
done
