# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Exports core dump journal records as test fixtures, read-only, keeping only what the field log
# reads. The environment keeps a few names (the agent markers with the value 1, the runtime directory,
# the desktop, PWD, HOME); every other variable, which can hold tokens and keys, is dropped. Host,
# machine and boot ids, cursors, maps, limits and open files are dropped too.
#
#   python3 export-fixtures.py SINCE UNTIL [EXE...] > fixtures/FILE.jsonl
#
# SINCE and UNTIL as journalctl takes them. fixtures/coredumps-2026-10-02.jsonl came from the
# UX5406S laptop's journal with
#   export-fixtures.py '2026-10-02 11:40:00 UTC' '2026-10-02 11:50:00 UTC' /usr/bin/python3.14
#   export-fixtures.py '2026-10-02 15:20:00 UTC' '2026-10-02 15:40:00 UTC' /usr/bin/bash
# (two python3 SIGABRT dumps from an agent's scratchpad at 11:44 UTC, ten bash SIGSEGV dumps of the
# login check's fake "rpm-crash" from a build directory at 15:21-15:38 UTC).
import json, subprocess, sys

KEEP = ["__REALTIME_TIMESTAMP", "MESSAGE_ID", "MESSAGE", "COREDUMP_PID", "COREDUMP_UID", "COREDUMP_GID",
        "COREDUMP_EXE", "COREDUMP_COMM", "COREDUMP_CMDLINE", "COREDUMP_CWD", "COREDUMP_CGROUP",
        "COREDUMP_UNIT", "COREDUMP_USER_UNIT", "COREDUMP_SLICE", "COREDUMP_SIGNAL", "COREDUMP_SIGNAL_NAME",
        "COREDUMP_TIMESTAMP", "COREDUMP_PACKAGE_NAME", "COREDUMP_PACKAGE_VERSION"]
ENV_KEEP = {"XDG_RUNTIME_DIR", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "KDE_FULL_SESSION", "PWD", "HOME",
            "LANG", "LC_ALL", "SHLVL", "container"}
MARKERS = {"CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "AI_AGENT", "OPENCODE", "CODEX_SANDBOX",
           "CODEX_SANDBOX_NETWORK_DISABLED", "GEMINI_CLI", "CURSOR_AGENT"}


def text(v):
    if isinstance(v, list):
        return bytes(v).decode("utf-8", "replace")
    return v


def main():
    since, until, exes = sys.argv[1], sys.argv[2], sys.argv[3:]
    args = ["journalctl", "--no-pager", "-a", "-o", "json", "--since", since, "--until", until,
            "MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1"]
    out = subprocess.run(args, capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        d = json.loads(line)
        if exes and d.get("COREDUMP_EXE") not in exes:
            continue
        rec = {k: text(d[k]) for k in KEEP if d.get(k) is not None}
        env = []
        for item in (text(d.get("COREDUMP_ENVIRON")) or "").split("\n"):
            k, _, v = item.partition("=")
            if k in MARKERS:
                env.append(f"{k}=1")
            elif k in ENV_KEEP:
                env.append(f"{k}={v}")
        rec["COREDUMP_ENVIRON"] = "\n".join(env)
        print(json.dumps(rec, sort_keys=True, ensure_ascii=False))


if __name__ == "__main__":
    main()
