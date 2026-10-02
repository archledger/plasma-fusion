# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Tests of the field log (tools/device/fieldlog/plasma-fusion-fieldlog), standard library only:
# classification of real core dump records of 2026-10-02 (fixtures/) and of a synthetic plasmashell
# session crash shaped like the ThinkPad's global menu crash, dedupe with counts, privacy filtering,
# journal handling, the digest, retention, install/remove with a fake systemctl, and "run" against a
# fake coredumpctl, journalctl and systemctl on PATH and a fake /proc and /sys.
#
#   python3 tools/device/fieldlog/tests/fieldlog_test.py [-v]
#
# Scratch goes to build/fieldlog-tests/ of the checkout (PF_FIELDLOG_TEST_DIR overrides), never /tmp;
# nothing touches the real session, the real systemctl or the owner's state directory.
import importlib.machinery, importlib.util, json, os, pathlib, shutil, signal, subprocess, sys, tempfile
import threading, time, unittest

HERE = pathlib.Path(__file__).resolve().parent
TOOL = HERE.parent / "plasma-fusion-fieldlog"
REPO = HERE.parents[2]
SCRATCH = pathlib.Path(os.environ.get("PF_FIELDLOG_TEST_DIR") or REPO / "build" / "fieldlog-tests")
FIXTURE = HERE / "fixtures" / "coredumps-2026-10-02.jsonl"
UID = os.getuid()
MSGID = "fc2e22bc6ee647b6b90729ab34a250b1"

os.environ["TZ"] = "UTC"
time.tzset()
SCRATCH.mkdir(parents=True, exist_ok=True)
BASE = pathlib.Path(tempfile.mkdtemp(prefix="unit-", dir=SCRATCH))
os.environ["XDG_STATE_HOME"] = str(BASE / "state")
os.environ["HOME"] = str(BASE / "home")
os.environ.pop("PF_FIELDLOG_SHARE", None)
os.environ.pop("PF_FIELDLOG_SINCE", None)

loader = importlib.machinery.SourceFileLoader("fieldlog", str(TOOL))
spec = importlib.util.spec_from_loader("fieldlog", loader)
fl = importlib.util.module_from_spec(spec)
loader.exec_module(fl)


def fixtures():
    return [json.loads(l) for l in FIXTURE.read_text().splitlines() if l.strip()]


# A plasmashell crash in the session's session.slice, shaped like the ThinkPad's of 2026-10-01
# (coredump 2078: SIGSEGV in the global menu applet, QWidget::removeAction from
# AppMenuModel::removeSearchActionsFromMenu), dated 2026-10-02 16:00 UTC here.
def session_record(uid=UID, pid=2078, t=1790956800):
    trace = "\n".join([
        f"Process {pid} (plasmashell) of user {uid} dumped core.", "",
        "Module org.kde.plasma.appmenu.so from rpm plasma-workspace-6.7.5-1.fc44.x86_64",
        f"Stack trace of thread {pid}:",
        "#0  0x00007fa456c7bd0c __pthread_kill_implementation (libc.so.6 + 0x74d0c)",
        "#1  0x00007fa456c20e8e raise (libc.so.6 + 0x19e8e)",
        "#2  0x00007fa45a4c10d4 _ZN6KCrash19defaultCrashHandlerEi (libKF6Crash.so.6 + 0x50d4)",
        "#3  0x00007fa456c20fb0 __restore_rt (libc.so.6 + 0x19fb0)",
        "#4  0x00007fa459a9b4cf _ZN9QtPrivate19sequential_erase_ifI5QListIP7QObjectEZNS_16sequential_eraseIS4_P7QWidgetEEDaRT_RKT0_EUlRKS8_E_EEDaS9_RSA_.isra.0 (libQt6Widgets.so.6 + 0x9b4cf)",
        "#5  0x00007fa459aa3f2a _ZN7QWidget12removeActionEP7QAction (libQt6Widgets.so.6 + 0xa3f2a)",
        "#6  0x00007fa441738fca _ZN12AppMenuModel27removeSearchActionsFromMenuEv (org.kde.plasma.appmenu.so + 0xffca)",
        "#7  0x00007fa457381db7 _Z10doActivateILb0EEvP7QObjectiPPv (libQt6Core.so.6 + 0x181db7)",
        "#8  0x00007fa459c16679 _ZN9QLineEdit11textChangedERK7QString (libQt6Widgets.so.6 + 0x216679)",
        "",
        f"Stack trace of thread {pid + 23}:",
        "#0  0x00007fa456cf3a3d __poll (libc.so.6 + 0xeca3d)",
        "#1  0x00007fa455bf6f2d g_main_context_iterate_unlocked.isra.0 (libglib-2.0.so.0 + 0x47f2d)",
        "ELF object binary architecture: AMD x86-64"])
    return {
        "__REALTIME_TIMESTAMP": str(t * 1000000 + 812345), "MESSAGE_ID": MSGID, "MESSAGE": trace,
        "COREDUMP_PID": str(pid), "COREDUMP_UID": str(uid), "COREDUMP_GID": str(uid),
        "COREDUMP_EXE": "/usr/bin/plasmashell", "COREDUMP_COMM": "plasmashell",
        "COREDUMP_CMDLINE": "/usr/bin/plasmashell --no-respawn", "COREDUMP_CWD": "/home/test",
        "COREDUMP_CGROUP": f"/user.slice/user-{uid}.slice/user@{uid}.service/session.slice/plasma-plasmashell.service",
        "COREDUMP_UNIT": f"user@{uid}.service", "COREDUMP_USER_UNIT": "plasma-plasmashell.service",
        "COREDUMP_SLICE": f"user-{uid}.slice", "COREDUMP_SIGNAL": "11", "COREDUMP_SIGNAL_NAME": "SIGSEGV",
        "COREDUMP_TIMESTAMP": str(t * 1000000), "COREDUMP_PACKAGE_NAME": "plasma-workspace",
        "COREDUMP_PACKAGE_VERSION": "6.7.5-1.fc44",
        "COREDUMP_ENVIRON": f"XDG_RUNTIME_DIR=/run/user/{uid}\nXDG_CURRENT_DESKTOP=KDE\nKDE_FULL_SESSION=true\nHOME=/home/test",
    }


def app_record(uid=UID, pid=31337, t=1790960400, env_extra=""):
    r = session_record(uid, pid, t)
    r.update({"COREDUMP_EXE": "/usr/bin/dolphin", "COREDUMP_COMM": "dolphin", "COREDUMP_CMDLINE": "/usr/bin/dolphin",
              "COREDUMP_CGROUP": f"/user.slice/user-{uid}.slice/user@{uid}.service/app.slice/app-org.kde.dolphin@1a2b.service",
              "COREDUMP_USER_UNIT": "app-org.kde.dolphin@1a2b.service", "COREDUMP_PACKAGE_NAME": "dolphin",
              "MESSAGE": f"Process {pid} (dolphin) of user {uid} dumped core.\n\nStack trace of thread {pid}:\n"
                         "#0  0x00007f0000001000 _ZN11DolphinView4openEv (libdolphinprivate.so.6 + 0x1000)\n"})
    r["COREDUMP_ENVIRON"] += env_extra
    return r


def entry(rec):
    return {"time": int(rec["__REALTIME_TIMESTAMP"]), "pid": int(rec["COREDUMP_PID"]), "uid": int(rec["COREDUMP_UID"]),
            "gid": int(rec.get("COREDUMP_GID") or 0), "sig": int(rec.get("COREDUMP_SIGNAL") or 0),
            "corefile": "missing", "exe": rec["COREDUMP_EXE"], "size": None}


def fresh_dir(name):
    d = BASE / name
    shutil.rmtree(d, ignore_errors=True)
    d.mkdir(parents=True)
    return d


class Classify(unittest.TestCase):
    def setUp(self):
        self.proc = fresh_dir("cls-proc")
        self.cg = fresh_dir("cls-cg")
        fl.PROC, fl.CGROOT = str(self.proc), str(self.cg)

    def test_rpm_crash_fixtures_are_tooling(self):
        recs = [r for r in fixtures() if r["COREDUMP_COMM"] == "rpm-crash"]
        self.assertEqual(len(recs), 10)
        for r in recs:
            cls, reason, markers = fl.classify(r)
            self.assertEqual(cls, "tooling", reason)
            self.assertIn("development directory", reason)
            self.assertIn("/build/", reason)

    def test_python_fixtures_are_tooling(self):
        recs = [r for r in fixtures() if r["COREDUMP_COMM"] == "python3"]
        self.assertEqual(len(recs), 2)
        for r in recs:
            cls, reason, markers = fl.classify(r)
            self.assertEqual(cls, "tooling", reason)
            self.assertIn("scratchpad", reason)  # approved_pick.py, resolved against its working directory
            self.assertIn("CLAUDECODE", markers)
            # Without the path, the marker in its environment decides.
            r2 = dict(r, COREDUMP_CWD="/home/someone", COREDUMP_CMDLINE="python3 /home/someone/pick.py")
            cls, reason, _ = fl.classify(r2)
            self.assertEqual(cls, "tooling")
            self.assertIn("agent marker", reason)

    def test_session_crash(self):
        cls, reason, markers = fl.classify(session_record())
        self.assertEqual(cls, "session")
        self.assertIn("session.slice", reason)

    def test_session_crash_with_marker_stays_session(self):
        r = session_record()
        r["COREDUMP_ENVIRON"] += "\nAI_AGENT=1"
        cls, reason, markers = fl.classify(r)
        self.assertEqual(cls, "session")
        self.assertEqual(markers, ["AI_AGENT"])

    def test_app_and_app_with_marker(self):
        self.assertEqual(fl.classify(app_record())[0], "app")
        self.assertEqual(fl.classify(app_record(env_extra="\nOPENCODE=1"))[0], "tooling")

    def test_container_and_private_session(self):
        r = session_record(uid=525287)
        r["COREDUMP_CGROUP"] = f"/user.slice/user-{UID}.slice/user@{UID}.service/user.slice/libpod-f78d7678.scope/container"
        self.assertEqual(fl.classify(r)[:2], ("tooling", "container (libpod)"))
        r = session_record()
        r["COREDUMP_CGROUP"] = f"/user.slice/user-{UID}.slice/session-7.scope"
        r["COREDUMP_ENVIRON"] = "XDG_RUNTIME_DIR=/var/tmp/pfv-smoke3/run\nXDG_CURRENT_DESKTOP=KDE"
        cls, reason, _ = fl.classify(r)
        self.assertEqual(cls, "tooling")
        self.assertIn("private session", reason)

    def test_cgroup_shared_with_an_agent(self):
        cg = f"/user.slice/user-{UID}.slice/user@{UID}.service/app.slice/app-org.kde.konsole-7072.scope/tab(7139).scope"
        (self.cg / cg.lstrip("/")).mkdir(parents=True)
        (self.cg / cg.lstrip("/") / "cgroup.procs").write_text("4242\n4243\n")
        for pid, comm, env in (("4242", "bash", b"PATH=/usr/bin\0"), ("4243", "tmux: server", b"AI_AGENT=x\0TERM=xterm\0")):
            (self.proc / pid).mkdir()
            (self.proc / pid / "comm").write_text(comm + "\n")
            (self.proc / pid / "environ").write_bytes(env)
        r = app_record()
        r.update({"COREDUMP_CGROUP": cg, "COREDUMP_EXE": "/usr/bin/kate", "COREDUMP_CMDLINE": "kate"})
        cls, reason, _ = fl.classify(r)
        self.assertEqual(cls, "tooling")
        self.assertIn("4243", reason)
        (self.proc / "4243" / "environ").write_bytes(b"TERM=xterm\0")
        (self.proc / "4242" / "comm").write_text("claude\n")
        cls, reason, _ = fl.classify(r)
        self.assertEqual((cls, "claude (4242)" in reason), ("tooling", True))
        (self.proc / "4242" / "comm").write_text("bash\n")
        self.assertEqual(fl.classify(r)[0], "app")

    def test_other(self):
        r = app_record()
        r.update({"COREDUMP_EXE": "/usr/libexec/someservice", "COREDUMP_CGROUP": "/system.slice/someservice.service"})
        self.assertEqual(fl.classify(r)[0], "other")

    def test_plasma_units_and_crash_handler_are_session(self):
        # Seen on the laptop on 2026-09-27: xembedsniproxy in background.slice and DrKonqi's launcher
        # in app.slice crashed with KWin.
        r = app_record()
        r.update({"COREDUMP_EXE": "/usr/bin/xembedsniproxy",
                  "COREDUMP_CGROUP": f"/user.slice/user-{UID}.slice/user@{UID}.service/background.slice/plasma-xembedsniproxy.service"})
        self.assertEqual(fl.classify(r)[:2], ("session", "Plasma unit plasma-xembedsniproxy.service"))
        r.update({"COREDUMP_EXE": "/usr/libexec/drkonqi-coredump-launcher",
                  "COREDUMP_CGROUP": f"/user.slice/user-{UID}.slice/user@{UID}.service/app.slice/drkonqi-coredump-launcher@87-0.service"})
        self.assertEqual(fl.classify(r)[0], "session")

    def test_top_frames_and_signature(self):
        top = fl.top_frames(session_record()["MESSAGE"])
        self.assertTrue(top[0].startswith("_ZN9QtPrivate19sequential_erase_if"), top)
        self.assertEqual(top[2], "_ZN12AppMenuModel27removeSearchActionsFromMenuEv (org.kde.plasma.appmenu.so)")
        bash = [r for r in fixtures() if r["COREDUMP_COMM"] == "rpm-crash"][0]
        self.assertEqual(fl.top_frames(bash["MESSAGE"])[0], "kill_builtin (bash)")
        py = [r for r in fixtures() if r["COREDUMP_COMM"] == "python3"][0]
        self.assertNotIn("raise", fl.top_frames(py["MESSAGE"])[0])
        s1 = fl.signature("/usr/bin/plasmashell", "SIGSEGV", top)
        self.assertNotIn(".isra.0", s1)
        self.assertTrue(s1.startswith("plasmashell | SIGSEGV | "))


class EventsAndPrivacy(unittest.TestCase):
    def test_dedupe_with_counts(self):
        d = fresh_dir("dedupe")
        log = fl.EventLog(d)
        t0 = 1790956800
        for i in range(5):
            log.emit("noise", key="plasmashell|x|No signal handler for N", ts=t0 + i, text="x")
        log.emit("restart", key="a", ts=t0, coalesce=False)
        log.emit("restart", key="a", ts=t0 + 1, coalesce=False)
        lines = (d / "events-2026-10-02.jsonl").read_text().splitlines()
        self.assertEqual(len(lines), 3)
        log.flush()
        log2 = fl.EventLog(d)  # a restarted service on the same day
        self.assertFalse(log2.emit("noise", key="plasmashell|x|No signal handler for N", ts=t0 + 9, text="x"))
        log2.flush()
        groups = fl.aggregate(fl.read_events("2026-10-02", d))
        noise = [g for g in groups if g["kind"] == "noise"]
        self.assertEqual(len(noise), 1)
        self.assertEqual(noise[0]["count"], 6)
        self.assertEqual(noise[0]["first"], fl.iso(t0))
        self.assertEqual(noise[0]["last"], fl.iso(t0 + 9))
        self.assertEqual(sum(g["count"] for g in groups if g["kind"] == "restart"), 2)

    def test_scrub(self):
        h = os.environ["HOME"]
        self.assertEqual(fl.scrub(f"open {h}/Documents/x.pdf"), "open ~/Documents/x.pdf")
        s = fl.scrub('Window caption="Bank statement - Okular" stays')
        self.assertNotIn("Bank", s)
        self.assertIn("caption=<redacted>", s)
        self.assertNotIn("Dinner", fl.scrub('notification summary: "Dinner at 8" body="see you there"'))
        self.assertNotIn("see you", fl.scrub('body="see you there"'))
        self.assertEqual(fl.scrub('QML Text: Binding loop detected for property "width"'),
                         'QML Text: Binding loop detected for property "width"')
        self.assertEqual(fl.scrub('no tile for "Some Long Window Title"'), 'no tile for "…"')
        self.assertEqual(fl.normalise('id 42 at 0x7ffd12 "a b"'), 'id N at 0x… "…"')

    def test_crash_event_keeps_no_environment(self):
        d = fresh_dir("noenv")
        log = fl.EventLog(d)
        for r in fixtures()[:2]:
            cls, reason, markers = fl.classify(r)
            fl.crash_event(log, fl_entry(r), r, cls, reason, markers, d, save=False)
        text = (d / "events-2026-10-02.jsonl").read_text()
        for value in ("en_US.UTF-8", "KDE_FULL_SESSION", "/run/user/", "XDG_SESSION_TYPE", "wayland"):
            self.assertNotIn(value, text)
        self.assertIn('"markers":["AI_AGENT","CLAUDECODE","CLAUDE_CODE_ENTRYPOINT"]', text)


def fl_entry(r):
    return entry(r)


def jline(comm, msg, prio=4, ts=1790956900, **fields):
    d = {"__CURSOR": f"s=1;i=1;t={ts * 1000000:x}", "__REALTIME_TIMESTAMP": str(ts * 1000000), "_COMM": comm,
         "SYSLOG_IDENTIFIER": fields.pop("ident", comm), "PRIORITY": str(prio), "MESSAGE": msg}
    d.update(fields)
    return json.dumps(d, separators=(",", ":")).encode()


PF_FILE = "file://{h}/.local/share/plasma/plasmoids/org.plasmafusion.weathercard/contents/ui/ConfigLocation.qml"


def journal_lines(home):
    pf = PF_FILE.format(h=home)
    return [
        jline("plasmashell", f"{pf}:20:1: QML ConfigLocation: Created graphical object was not placed in the graphics scene.",
              CODE_FILE=pf, CODE_LINE="20", QT_CATEGORY="default"),
        jline("plasmashell", f"{pf}:20:1: QML ConfigLocation: Created graphical object was not placed in the graphics scene.",
              ts=1790956960, CODE_FILE=pf, CODE_LINE="20", QT_CATEGORY="default"),
        jline("plasmashell", "file:///usr/share/plasma/plasmoids/org.plasmafusion.dock/contents/ui/main.qml:88: "
              "TypeError: Cannot read property 'width' of null", QT_CATEGORY="qml"),
        jline("plasmashell", 'No signal handler for "dbusactiveChanged"', QT_CATEGORY="org.kde.plasma.workspace.dbus"),
        jline("plasmashell", 'No signal handler for "dbusactiveChanged"', ts=1790956901, QT_CATEGORY="org.kde.plasma.workspace.dbus"),
        jline("plasmashell", 'No signal handler for "dbusactiveChanged"', ts=1790956902, QT_CATEGORY="org.kde.plasma.workspace.dbus"),
        jline("plasmashell", 'Notification replaced: summary="Dinner with Sam" from "Messages"', QT_CATEGORY="org.kde.plasma.notificationmanager"),
        jline("kwin_wayland", 'kwin_core: Window caption="Private Browsing - Firefox" could not be found', QT_CATEGORY="kwin_core"),
        jline("kwin_wayland", "plasmafusion-tablet: posture tablet", prio=6, QT_CATEGORY="qml"),
        jline("kwin_wayland", "plasmafusion-snap: screens changed, 2 window(s) moved into their work area", prio=6, QT_CATEGORY="qml"),
        jline("plasmashell", 'launcher: first results for "chro" after 12 ms', prio=6, QT_CATEGORY="qml"),
        jline("systemd", "plasma-fusion-app-icons.service: Failed with result 'exit-code'.", prio=4,
              USER_UNIT="plasma-fusion-app-icons.service", MESSAGE_ID=fl.MSG_FAILURE_RESULT, UNIT_RESULT="exit-code"),
        jline("systemd", "plasma-plasmashell.service: Main process exited, code=dumped, status=11/SEGV", prio=4,
              USER_UNIT="plasma-plasmashell.service", MESSAGE_ID=fl.MSG_PROCESS_EXIT, EXIT_CODE="dumped", EXIT_STATUS="11"),
        jline("systemd", "Reached target graphical-session.target - Current graphical user session.", prio=6, ts=1790950000,
              USER_UNIT="graphical-session.target", MESSAGE_ID=fl.MSG_STARTED),
        jline("python3", "Traceback (most recent call last):", prio=6, ident="plasma-fusion-app-icons"),
        # Real lines of the tools (2026-09-27..10-02): two routine, one a problem.
        jline("python3", "familiar app icons: built 1, removed 28, failed 0 (); 2 in all", prio=6,
              ident="plasma-fusion-app-icons"),
        jline("bash", "tier saver (on AC, 85 %, warning level 1, profile power-saver): 2 widget setting(s)", prio=6,
              ident="plasma-fusion-powerfx"),
        jline("bash", "tier full (requested): Plasma widgets when plasmashell is back (Call failed: No such object "
              "path '/PlasmaShell')", prio=6, ident="plasma-fusion-powerfx"),
        jline("python3", "TypeError: bad thing in plasma-fusion-fieldlog", prio=3, ident="plasma-fusion-fieldlog"),
        jline("chrome", "something about plasmafusion in a web page", prio=4, ident="google-chrome"),
    ]


class Journal(unittest.TestCase):
    def test_lines(self):
        state = fresh_dir("journal-state")
        os.environ["XDG_STATE_HOME"] = str(state)
        f = fl.FieldLog()
        f.state["last_dump_us"] = 0
        for line in journal_lines(os.environ["HOME"]):
            fl.handle_journal_line(f, line)
        f.log.flush()
        groups = fl.aggregate(fl.read_events("2026-10-02", f.sdir))
        kinds = {}
        for g in groups:
            kinds.setdefault(g["kind"], []).append(g)
        w = kinds["pf-warning"]
        cfg = [g for g in w if "ConfigLocation" in g.get("where", "")]
        self.assertEqual(len(cfg), 1)
        self.assertEqual(cfg[0]["count"], 2)
        self.assertEqual(cfg[0]["where"], "org.plasmafusion.weathercard/contents/ui/ConfigLocation.qml:20")
        self.assertEqual(cfg[0]["src"], "user copy")
        self.assertTrue(any(g["comm"] == "plasma-fusion-app-icons" and "Traceback" in g["text"] for g in w))
        tools = sorted(g["text"] for g in w if g["comm"].startswith("plasma-fusion"))
        self.assertEqual(len(tools), 2, tools)
        self.assertIn("Call failed", tools[1])
        err = kinds["pf-error"]
        self.assertEqual(err[0]["where"], "org.plasmafusion.dock/contents/ui/main.qml:88")
        self.assertIn("TypeError", err[0]["text"])
        noise = {g["text"]: g["count"] for g in kinds["noise"]}
        self.assertEqual(noise['No signal handler for "dbusactiveChanged"'], 3)
        self.assertEqual(kinds["posture"][0]["posture"], "tablet")
        self.assertEqual(kinds["screen"][0]["field"], "screens changed")
        self.assertEqual(kinds["unit-failed"][0]["unit"], "plasma-fusion-app-icons.service")
        self.assertEqual(kinds["unit-exit"][0]["code"], "dumped")
        self.assertTrue(f.poll_at > 0)
        self.assertEqual(len(kinds["login"]), 1)
        everything = "".join(p.read_text() for p in f.sdir.glob("*.jsonl"))
        for private in ("chro", "Dinner", "Private Browsing", "web page", "bad thing"):
            self.assertNotIn(private, everything)
        ring = " ".join(r[5] for r in f.ring)
        self.assertNotIn("chro", ring)
        self.assertIn("launcher: first results for", ring)


class Digest(unittest.TestCase):
    def test_digest(self):
        d = fresh_dir("digest")
        log = fl.EventLog(d)
        recs = fixtures() + [session_record()]
        fl.PROC, fl.CGROOT = str(BASE / "none"), str(BASE / "none")
        for r in recs:
            cls, reason, markers = fl.classify(r)
            fl.crash_event(log, entry(r), r, cls, reason, markers, d, save=False)
        t = 1790956805
        log.emit("restart", key="plasmashell|2078|2101", ts=t, proc="plasmashell", old_pid=2078, new_pid=2101)
        log.emit("pf-error", key="k1", ts=t, comm="plasmashell", prio=4, where="org.plasmafusion.dock/contents/ui/main.qml:88",
                 text="TypeError: Cannot read property 'width' of null")
        log.emit("pf-error", key="k1", ts=t + 60, comm="plasmashell", prio=4, where="x", text="x")
        log.emit("resources", ts=t, coalesce=False, proc="plasmashell", hour="16:00", n=60, rss=[200, 210, 230],
                 anon=[140, 150, 170], cpu=[0.8, 12.0])
        log.emit("memsnap", ts=t, coalesce=False, proc="plasmashell", pid=2101, anon=[150, 260], rss=[210, 320],
                 file="memsnap/20261002T160005Z-plasmashell.txt")
        log.flush()
        text = fl.build_digest("2026-10-02", d)
        self.assertIn("| Session crashes (Plasma, Plasma Fusion) | **1** |", text)
        self.assertIn("| Development crashes (tooling, listed last) | 12 |", text)
        sess = text.index("## Session crashes")
        tooling = text.index("## Development crashes (tooling)")
        self.assertLess(sess, text.index("## Plasma Fusion errors"))
        self.assertGreater(tooling, text.index("## Other plasmashell and KWin warnings"))
        self.assertIn("plasmashell, SIGSEGV (plasma-workspace-6.7.5-1.fc44): 1x at 16:00", text)
        self.assertIn("AppMenuModel", text)
        self.assertIn("Restarted: plasmashell 2078 -> 2101", text)
        self.assertIn("| 2 | 16:00-16:01 | error |", text)
        self.assertIn("plasmashell restarts: 1 (16:00 2078 -> 2101 after its crash)", text)
        self.assertIn("| plasmashell | 1 | 200 / 210 / 230 | 140 / 150 / 170 | 0.80 / 12.0 |", text)
        self.assertIn("RssAnon 150 -> 260 MiB", text)
        tail = text[tooling:]
        self.assertRegex(tail, r"\| 10 \| 15:21-15:38 \| bash \| SIGSEGV \| script in a development directory")
        self.assertRegex(tail, r"\| 2 \| 11:44 \| python3\.14 \| SIGABRT \| script in a development directory")
        self.assertNotIn("rpm-crash", text[:tooling])


class Retention(unittest.TestCase):
    def test_age_and_size(self):
        d = fresh_dir("retention")
        (d / "memsnap").mkdir()
        (d / "crashes").mkdir()
        old = ["events-2026-08-01.jsonl", "digest-2026-08-01.md", "memsnap/20260801T000000Z-plasmashell.txt",
               "crashes/20260801T000000Z-plasmashell-1.txt"]
        new = ["events-2026-10-01.jsonl", "events-2026-10-02.jsonl", "crashes/20261001T000000Z-plasmashell-2.txt",
               "memsnap/20261001T000000Z-plasmashell.txt", "memsnap/20261002T000000Z-kwin_wayland.txt"]
        for n in old + new:
            (d / n).write_bytes(b"x" * 400_000)
        keep_mb = fl.MAX_MB
        try:
            fl.MAX_MB = 1.5
            fl.cleanup(d, "2026-10-02")
        finally:
            fl.MAX_MB = keep_mb
        left = sorted(str(p.relative_to(d)) for p in d.rglob("*") if p.is_file())
        for n in old:
            self.assertNotIn(n, left)
        self.assertIn("events-2026-10-02.jsonl", left)
        self.assertNotIn("memsnap/20261001T000000Z-plasmashell.txt", left)  # oldest snapshots go first
        self.assertLessEqual(sum((d / n).stat().st_size for n in left), 1.5 * 1048576)


FAKE_COREDUMPCTL = r'''#!/usr/bin/python3
import json, os, sys
recs = [json.loads(l) for l in open(os.environ["FAKE_DUMPS"]) if l.strip()]
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write("coredumpctl " + " ".join(a) + "\n")
since = next((int(x.split("@")[1]) for x in a if x.startswith("--since=@")), 0)
if "list" in a:
    out = [{"time": int(r["__REALTIME_TIMESTAMP"]), "pid": int(r["COREDUMP_PID"]), "uid": int(r["COREDUMP_UID"]),
            "gid": 0, "sig": int(r.get("COREDUMP_SIGNAL") or 0), "corefile": "missing", "exe": r["COREDUMP_EXE"],
            "size": None} for r in recs if int(r["__REALTIME_TIMESTAMP"]) >= since * 1000000]
    if not out:
        print("No coredumps found.", file=sys.stderr)
        sys.exit(1)
    print(json.dumps(out))
elif "info" in a:
    pid = a[-1]
    for r in recs:
        if r["COREDUMP_PID"] == pid:
            print(f"           PID: {pid} ({r['COREDUMP_COMM']})\n       Message: " + r.get("MESSAGE", "").replace("\n", "\n                "))
'''

FAKE_JOURNALCTL = r'''#!/usr/bin/python3
import json, os, signal, sys, time
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write("journalctl " + " ".join(a) + "\n")
if "-f" in a:
    signal.signal(signal.SIGTERM, lambda *x: sys.exit(0))
    for l in open(os.environ["FAKE_JOURNAL"], "rb"):
        sys.stdout.buffer.write(l)
    sys.stdout.flush()
    while True:
        time.sleep(1)
pid = next((x.split("=")[1] for x in a if x.startswith("COREDUMP_PID=")), None)
for l in open(os.environ["FAKE_DUMPS"]):
    r = json.loads(l)
    if r["COREDUMP_PID"] == pid:
        print(json.dumps(r))
'''

FAKE_SYSTEMCTL = r'''#!/usr/bin/python3
import os, sys, time
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write("systemctl " + " ".join(a) + "\n")
if "show" in a:
    print("ActiveEnterTimestamp=@%d" % (time.time() - 100))
elif "list-units" in a:
    print("plasma-fusion-powerfx.service loaded failed failed Plasma Fusion power tiers")
elif "is-active" in a:
    print("active")
'''


def write_exe(path, text):
    path.write_text(text)
    path.chmod(0o755)


def fake_proc(root, pid, comm, utime, start, anon_kib, rss_kib):
    p = root / str(pid)
    p.mkdir(parents=True, exist_ok=True)
    (p / "comm").write_text(comm + "\n")
    (p / "cgroup").write_text(f"0::/user.slice/user-{UID}.slice/user@{UID}.service/session.slice/plasma-{comm}.service\n")
    rest = ["S"] + ["0"] * 50
    rest[11], rest[12], rest[19] = str(utime), "0", str(start)
    (p / "stat").write_text(f"{pid} ({comm}) " + " ".join(rest) + "\n")
    (p / "status").write_text(f"Name:\t{comm}\nVmRSS:\t {rss_kib} kB\nRssAnon:\t {anon_kib} kB\nRssFile:\t 50000 kB\n")
    (p / "smaps").write_text("7f0000000000-7f0010000000 rw-p 00000000 00:00 0 \nRss:   262144 kB\nAnonymous:   262144 kB\n"
                             "7f0020000000-7f0020100000 r--p 00000000 00:23 7 /usr/lib64/libQt6Core.so.6\nRss: 2048 kB\nAnonymous: 0 kB\n")
    (p / "fdinfo").mkdir(exist_ok=True)
    (p / "fdinfo" / "12").write_text("pos:\t0\ndrm-driver:\ti915\ndrm-client-id:\t77\ndrm-total-system0:\t120 MiB\n")


class Run(unittest.TestCase):
    def test_run_with_fakes(self):
        d = fresh_dir("run")
        bin_, proc, sys_, cg, share = d / "bin", d / "proc", d / "sys", d / "cg", d / "share"
        for p in (bin_, proc, cg, sys_ / "class/drm/card0-eDP-1", d / "home"):
            p.mkdir(parents=True)
        write_exe(bin_ / "coredumpctl", FAKE_COREDUMPCTL)
        write_exe(bin_ / "journalctl", FAKE_JOURNALCTL)
        write_exe(bin_ / "systemctl", FAKE_SYSTEMCTL)
        dumps = d / "dumps.jsonl"
        recs = fixtures() + [session_record(), app_record()]
        dumps.write_text("".join(json.dumps(r) + "\n" for r in recs))
        journal = d / "journal.jsonl"
        journal.write_bytes(b"\n".join(journal_lines(str(d / "home"))) + b"\n")
        for f, v in (("status", "connected"), ("enabled", "enabled"), ("dpms", "On")):
            (sys_ / "class/drm/card0-eDP-1" / f).write_text(v + "\n")
        (d / "gate.log").write_text("2026-10-02T09:00:14-0400 login: theme=org.plasmafusion.dark.desktop versions=changed; "
                                    "lock screen: stock until the next tested login (31 ms)\n"
                                    "2026-10-02T09:00:14-0400   moved aside plasma-fusion-lockscreen.conf\n")
        fake_proc(proc, 5001, "plasmashell", 100, 1000, 150000, 210000)
        fake_proc(proc, 5002, "kwin_wayland", 500, 900, 25000, 70000)
        env = dict(os.environ, PATH=f"{bin_}:{os.environ['PATH']}", HOME=str(d / "home"), XDG_STATE_HOME=str(d / "state"),
                   PF_FIELDLOG_PROC=str(proc), PF_FIELDLOG_SYS=str(sys_), PF_FIELDLOG_CGROUP_ROOT=str(cg),
                   PF_FIELDLOG_INTERVAL="0.5", PF_FIELDLOG_RUN_SECONDS="8", PF_FIELDLOG_SINCE="2026-10-02",
                   PF_FIELDLOG_SHARE=str(share), PF_FIELDLOG_GATE_LOG=str(d / "gate.log"), TZ="UTC",
                   FAKE_DUMPS=str(dumps), FAKE_JOURNAL=str(journal), FAKE_LOG=str(d / "calls.log"))
        p = subprocess.Popen([sys.executable, str(TOOL), "run"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            time.sleep(2.5)
            fake_proc(proc, 5001, "plasmashell", 100, 1000, 260000, 320000)   # +107 MiB RssAnon: a memsnap
            time.sleep(1.0)
            (sys_ / "class/drm/card0-eDP-1/dpms").write_text("Off\n")
            time.sleep(1.0)
            shutil.rmtree(proc / "5001")                                       # plasmashell restarts
            fake_proc(proc, 5101, "plasmashell", 5, 2000, 140000, 200000)
            out, err = p.communicate(timeout=30)
        finally:
            if p.poll() is None:
                p.kill()
        self.assertEqual(p.returncode, 0, err.decode())
        sdir = d / "state/plasma-fusion/fieldlog"
        today = time.strftime("%Y-%m-%d")
        events = fl.read_events("2026-10-02", sdir) + (fl.read_events(today, sdir) if today != "2026-10-02" else [])
        groups = fl.aggregate(events)
        crashes = {}
        for g in groups:
            if g["kind"] == "crash":
                crashes[g["cls"]] = crashes.get(g["cls"], 0) + g["count"]
        self.assertEqual(crashes, {"tooling": 12, "session": 1, "app": 1})
        saved = sorted(p.name for p in (sdir / "crashes").iterdir())
        self.assertEqual(len(saved), 2, saved)
        self.assertIn("AppMenuModel", (sdir / "crashes" / [n for n in saved if "plasmashell" in n][0]).read_text())
        kinds = {g["kind"] for g in groups}
        for k in ("fieldlog-start", "fieldlog-stop", "restart", "memsnap", "screen", "unit-failed", "pf-warning",
                  "pf-error", "posture", "gate", "login", "resources", "self"):
            self.assertIn(k, kinds)
        restart = [g for g in groups if g["kind"] == "restart"][0]
        self.assertEqual((restart["old_pid"], restart["new_pid"]), (5001, 5101))
        snap = [g for g in groups if g["kind"] == "memsnap"][0]
        snaptext = (sdir / snap["file"]).read_text()
        self.assertIn("anonymous >= 1 MiB", snaptext)
        self.assertIn("drm-client-id: 77", snaptext)
        self.assertTrue(any(g["kind"] == "screen" and g.get("new") == "Off" for g in groups))
        self.assertTrue((sdir / f"digest-{today}.md").exists())
        self.assertTrue((share / f"digest-{today}-{os.uname().nodename}.md").exists())
        r = subprocess.run([sys.executable, str(TOOL), "digest", "2026-10-02"], env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("## Session crashes", r.stdout)
        self.assertIn("crashes/", r.stdout)
        self.assertTrue((share / f"digest-2026-10-02-{os.uname().nodename}.md").exists())
        r = subprocess.run([sys.executable, str(TOOL), "status"], env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("service:  plasma-fusion-fieldlog.service active", r.stdout)
        everything = "".join(p.read_text(errors="replace") for p in sdir.rglob("*") if p.is_file())
        for private in ("chro", "Dinner", "Private Browsing", "KDE_FULL_SESSION", "en_US.UTF-8"):
            self.assertNotIn(private, everything)
        calls = (d / "calls.log").read_text()
        for verb in ("restart", "enable", "start ", "stop", "daemon-reload"):
            self.assertNotIn(f"systemctl --user {verb}", calls.replace("--no-pager ", ""))


class Install(unittest.TestCase):
    def test_install_and_remove(self):
        d = fresh_dir("install")
        bin_ = d / "bin"
        bin_.mkdir()
        write_exe(bin_ / "systemctl", FAKE_SYSTEMCTL)
        env = dict(os.environ, PATH=f"{bin_}:{os.environ['PATH']}", HOME=str(d / "home"),
                   XDG_CONFIG_HOME=str(d / "home/.config"), XDG_STATE_HOME=str(d / "home/.local/state"),
                   FAKE_LOG=str(d / "calls.log"))
        r = subprocess.run([sys.executable, str(TOOL), "install", "--share", str(d / "share")], env=env,
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        unit = (d / "home/.config/systemd/user/plasma-fusion-fieldlog.service").read_text()
        self.assertIn("ExecSearchPath=%h/.local/libexec/plasma-fusion:", unit)
        self.assertIn("ExecStart=plasma-fusion-fieldlog run", unit)
        self.assertIn(f"Environment=PF_FIELDLOG_SHARE={d / 'share'}", unit)
        copy = d / "home/.local/libexec/plasma-fusion/plasma-fusion-fieldlog"
        self.assertEqual(copy.read_bytes(), TOOL.read_bytes())
        self.assertTrue(os.access(copy, os.X_OK))
        calls = (d / "calls.log").read_text().splitlines()
        self.assertEqual(calls, ["systemctl --user daemon-reload", "systemctl --user enable plasma-fusion-fieldlog.service",
                                 "systemctl --user restart plasma-fusion-fieldlog.service"])
        r = subprocess.run([sys.executable, str(copy), "remove"], env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(copy.exists())
        self.assertFalse((d / "home/.config/systemd/user/plasma-fusion-fieldlog.service").exists())
        self.assertIn("systemctl --user disable --now plasma-fusion-fieldlog.service", (d / "calls.log").read_text())


if __name__ == "__main__":
    try:
        unittest.main(verbosity=2 if "-v" in sys.argv else 1, argv=[sys.argv[0]] + [a for a in sys.argv[1:] if a != "-v"])
    finally:
        shutil.rmtree(BASE, ignore_errors=True)
