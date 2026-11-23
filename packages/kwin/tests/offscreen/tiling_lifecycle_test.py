#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The dynamic tiler's native lifecycle, offscreen: the real placement main.qml under the
stand-in org.kde.kwin module and a mock TransientTilingApi facade.

The harness QML drives the toggle, the untoggle, the native teardown and a refused tree, and
asserts the geometry and the facade calls; this driver additionally waits past the settling
timer so the invariant-7 check is honest (a late settle pass must not record managed windows
either) and re-checks the call counts.

    QT_QPA_PLATFORM=offscreen python3 tiling_lifecycle_test.py [PACKAGES_KWIN_DIR]

PACKAGES_KWIN_DIR defaults to this checkout's packages/kwin; the CI lane passes the staged
tree's .local/share/kwin.
"""
import os
import re
import sys

from PySide6.QtCore import QCoreApplication, QEvent, QObject, QTimer, QUrl, Slot, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlContext, QQmlEngine

from render import I18n


class ScriptConfig(QObject):
    """The KWin scripting functions the module exposes to QML scripts, as a context object
    (the stand-in module carries no KWin singleton). MasterFraction is prefilled so the test
    also proves the tiler's settings reach the native tile."""

    def __init__(self):
        super().__init__()
        # MasterFraction exercises the tiler's settings path; IgnoreApps names winB's app in
        # the harness (org.fusion.files), for the ignored-member detach scenario.
        self.settings = {"MasterFraction": 0.4, "IgnoreApps": "org.fusion.files"}
        self.calls = []

    @Slot(str, "QVariant", result="QVariant")
    def readConfig(self, key, fallback):
        return self.settings.get(key, fallback)

    @Slot(str, "QVariant")
    def writeConfig(self, key, value):
        self.settings[key] = value

    @Slot(str, str, str, str)
    def callDBus(self, service, path, interface, method):
        self.calls.append([service, path, interface, method])


class KWinScript(QObject):
    """A declarative script as KWin makes and unloads one (src/scripting/scripting.cpp,
    DeclarativeScript): one object owns, in this order, the script's own context (a child of
    the engine's root context, carrying the KWin context property), the component, the KWin
    object and the script's root object. Unloading is deleteLater() on that object, and its
    children go in the order they came: the context first, so the script's
    Component.onDestruction runs while the context it was made in is being torn down."""

    def __init__(self, engine):
        super().__init__()
        self.context = QQmlContext(engine.rootContext(), self)
        self.component = QQmlComponent(engine, self)
        self.config = ScriptConfig()
        self.config.setParent(self)
        self.context.setContextProperty("KWin", self.config)

    def make(self, url):
        self.component.loadUrl(QUrl(url))
        if self.component.status() != QQmlComponent.Ready:
            print("FAIL tiling_lifecycle_test.py: the script did not load: "
                  + "; ".join(e.toString() for e in self.component.errors()))
            return None
        made = self.component.create(self.context)
        if made is not None:
            made.setParent(self)
        return made


here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
packages_kwin = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(repo, "packages", "kwin")

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


# The script's own journal lines (console.info), kept for the teardown count below and passed on.
messages = []


def keep_message(mode, context, message):
    messages.append(message)
    print(message, file=sys.stderr)


qInstallMessageHandler(keep_message)
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
engine.addImportPath(os.path.join(here, "stubs"))
# The stand-in bus module is this suite's alone: in the shared stubs/ it would hide the system
# org.kde.plasma.workspace.dbus from the other offscreen suites: the snap script and switcher they
# load use more of it (their copies of FusionTablet) than the stand-in has.
engine.addImportPath(os.path.join(here, "lifecycle-stubs"))
# Keep every context QObject referenced for the engine's lifetime: a temporary would be
# garbage-collected by Python while QML still resolves through it (a dangling pointer).
i18n = I18n()
engine.rootContext().setContextObject(i18n)
engine.rootContext().setContextProperty("packagesRoot", packages_kwin)
config = ScriptConfig()
engine.rootContext().setContextProperty("KWin", config)
component = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(here, "tiling-harness.qml")))
if component.status() != QQmlComponent.Ready:
    print("FAIL tiling_lifecycle_test.py: the harness did not load: "
          + "; ".join(e.toString() for e in component.errors()))
    sys.exit(1)
def run_harness(initial=None):
    """One harness instance run to its end, past the script's 1 s settling timer."""
    instance = component.createWithInitialProperties(initial) if initial else component.create()

    def poll():
        if instance.property("done"):
            QTimer.singleShot(1300, app.quit)
        else:
            QTimer.singleShot(50, poll)

    QTimer.singleShot(50, poll)
    app.exec()
    return instance


provider_labels = {}

# The layout provider's lines for a read and a publication that came back: what each found or
# carried, then its length from call to answer and, when its script's start lies within the call,
# its length from that start (decision 1's time limit); a call over the limit is said on a line
# of its own, with the length it was judged by - from its script's start when there is one, else
# from its call.
LENGTH = r", in (\d+) ms(?: \((\d+) ms from its script's start\))?"
READ_LINE = re.compile(r"plasmafusion-placement: layout provider: read (\d+) request\(s\), (\d+) refused" + LENGTH)
PUBLISHED_LINE = re.compile(r"plasmafusion-placement: layout provider: published (\d+) frame\(s\), (\d+) written"
                            + LENGTH)
OVER_LINE = re.compile(r"plasmafusion-placement: layout provider: a (read|publication) took (\d+) ms from its"
                       r" (script's start|call) to its answer, over the 50 ms limit")


def call_lines(journal, pattern, marker):
    """The journal's lines holding `marker`, parsed with `pattern`, as (found, carried or written,
    length, length from the script's start or None); a line that does not parse, or whose length
    from the script's start is longer than the call, is None."""
    lines = []
    for message in journal:
        if marker not in message:
            continue
        match = pattern.fullmatch(message)
        shell = None if not match or match.group(4) is None else int(match.group(4))
        if not match or (shell is not None and shell > int(match.group(3))):
            lines.append(None)
            continue
        lines.append((int(match.group(1)), int(match.group(2)), int(match.group(3)), shell))
    return lines


def check_provider(instance, name):
    """The run's layout provider (LayoutProvider.qml), as the harness recorded it: revisions
    1, 2, ... one per state, each a change of what a bar would be told, and a lifetime label
    no earlier run had."""
    states = [dict(state) for state in instance.property("providerStates").toVariant() or []]
    check(bool(states), "%s: the run followed the script's layout provider" % name)
    for index, state in enumerate(states):
        check(state.get("revision") == index + 1,
              "%s: the provider's revisions run 1, 2, ... (state %d has %s)" % (name, index, state.get("revision")))
        if index:
            check(dict(state, revision=0) != dict(states[index - 1], revision=0),
                  "%s: revision %s moved with nothing changed (%s)" % (name, state.get("revision"), state))
    label = str(instance.property("providerLabel") or "")
    check(label != "" and label not in provider_labels.values(),
          "%s: the provider's lifetime label is its own (%r, earlier runs %r)" % (name, label, provider_labels))
    provider_labels[name] = label


def retire(instance, name):
    """End a run whose results have been read. The stand-in Workspace is one object for the
    whole engine, so a script left alive answers the next run's windows as well: with its
    own session, its own mock facade and its own lines in the journal.

    The script goes with a session live or just ended (its own untoggle on destruction): a
    throw on that path shows only as the engine's message, so the lines of the retirement
    are read for one. (Until 2026-11-14 one such line was let through, a readConfig of the
    engine's teardown: it was the script's own handler answering its teardown's writes, the
    path that crashed KWin, and no teardown reads a setting now.)

    The layout provider's record is read first (check_provider), while the run is alive."""
    check_provider(instance, name)
    before_retire = len(messages)
    instance.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    app.processEvents()
    thrown = [message for message in messages[before_retire:] if "TypeError" in message]
    check(not thrown, "%s: the script went without a throw, got %s" % (name, thrown))


harness = run_harness()
teardowns = sum("tiling: off (native teardown)" in message for message in messages)

problems = list(harness.property("problems").toVariant() or [])
facade_calls = list(harness.property("facadeCalls").toVariant() or [])
for problem in problems:
    failures.append(str(problem))

counts = {}
snapshot = harness.property("snapshot")
snapshot = snapshot.toVariant() if hasattr(snapshot, "toVariant") else snapshot
for key in ("createTile", "admitTile", "releaseTile", "registerProvider", "trackWindow"):
    counts[key] = (snapshot or {}).get(key)
# Seven accepted sessions (toggle, post-teardown toggle, teardown-proof toggle, the session whose
# admission lands the master, the first-desktop session, the invoked-view toggle, the
# ignored-member toggle) plus one refused create and one tree whose admission was refused; eight
# admissions, one of them refused; six releases (the run's own un-toggles, the invocation's
# teardown included, and the refused admission's tree - the native teardown releases nothing,
# the last session is left standing for the settle pass, and the destruction-time untoggle is
# outside the snapshot). Seven windows tracked: the three open at the start and the four the
# script saw open (the second desktop's master appears only as the tiler's target).
check(counts.get("registerProvider") == 1, "registerProvider once")
check(counts.get("createTile") == 9, "createTile nine times (7 sessions + 1 refused + 1 refused admission), got %s" % counts.get("createTile"))
check(counts.get("admitTile") == 8, "admitTile eight times, got %s" % counts.get("admitTile"))
check(counts.get("releaseTile") == 6, "releaseTile six times, got %s" % counts.get("releaseTile"))
check(counts.get("trackWindow") == 7, "trackWindow for the seven windows, got %s" % counts.get("trackWindow"))
# The mock's releaseTile reports the tree's end before it returns, as the compositor's does. The
# untoggle has ended its session by then: the run has one native teardown (the scenario that
# ends the tree behind the script's back), not one more for every release the script asked for.
check(teardowns == 1, "one native teardown in the run, got %s" % teardowns)

# Invariant 7, the ignore policy and the float record, after the settling pass fired: the only
# records are the live-joined windows' saved floats (c, d and g at their open geometries) and
# the master's own floating frame, recorded by its first toggle (the native layer admits a
# window from the place the memory has for its app) - never a cell or the tile's rectangle,
# nothing for the adopted stack windows, and nothing at all for the ignored app's second
# window (e) or the reflow-starved member's late cell commit (a).
recorded = [c for c in facade_calls if c["op"] == "record"]
expected_floats = {("c", 300, 500, 260, 260), ("d", 200, 300, 240, 200), ("g", 430, 150, 260, 300),
                   ("master", 40, 80, 620, 420)}
got_floats = {(c["window"], c["x"], c["y"], c["width"], c["height"]) for c in recorded}
check(got_floats == expected_floats,
      "only the joined windows' floats and the master's own were recorded (a cell, the tile, an ignored app and a late commit"
      " never were): got %s" % sorted(got_floats))

retire(harness, "first run")

# A second run against the facade of a fork build from before restoreWindow: the tiler stays off
# (it could start a session and never end it) and says so, and the placement memory keeps its
# native transport.
older = run_harness({"legacyFacade": True})
for problem in list(older.property("problems").toVariant() or []):
    failures.append("older facade: " + str(problem))
older_counts = older.property("snapshot")
older_counts = older_counts.toVariant() if hasattr(older_counts, "toVariant") else older_counts
check((older_counts or {}).get("createTile") == 0, "older facade: no tree was created")
check((older_counts or {}).get("trackWindow") == 3, "older facade: the three open windows were tracked natively")
check(any("the native facade has no restoreWindow" in message for message in messages),
      "older facade: the tiler said why it stays off")

retire(older, "older facade")

# A run against the facade of a fork build that restores but has neither floatingFrame nor
# settleWindow: the toggle records nothing of the window (the harness checks it), and a session
# starts and ends where the memory has the window's own place.
interim = run_harness({"interimFacade": True})
for problem in list(interim.property("problems").toVariant() or []):
    failures.append("interim facade: " + str(problem))
interim_counts = interim.property("snapshot")
interim_counts = interim_counts.toVariant() if hasattr(interim_counts, "toVariant") else interim_counts
check((interim_counts or {}).get("createTile") == 2 and (interim_counts or {}).get("admitTile") == 2
      and (interim_counts or {}).get("restoreWindow") == 1,
      "interim facade: one refused admission, one session started and restored, got %s" % interim_counts)
retire(interim, "interim facade")

# A run against a writer that refuses the provider registration as the fork does while another
# provider holds its slot or the writer is busy (a null QUuid's text): the memory stays disabled
# for the session and takes no other transport, and a toggle starts no tree. The harness checks
# the calls past the script's longest delayed call; the journal says the refusal once and never
# claims the registration.
before = len(messages)
refused_provider = run_harness({"scenario": "refused-provider"})
for problem in list(refused_provider.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
check(sum("the writer refused the provider registration" in message for message in journal) == 1,
      "refused-provider: the refusal was said once")
check(not any("registered as the placement provider" in message for message in journal),
      "refused-provider: a null UUID is not a registration")
thrown = [message for message in journal if "TypeError" in message or "ReferenceError" in message]
check(not thrown, "refused-provider: a refused provider throws nothing, got %s" % thrown)
# Read again run_harness's 1.3 s after the run, which ends 2.5 s after its toggle: the
# registration is the only thing a refused provider asks of the writer, read-only calls included.
refused_calls = refused_provider.property("facadeCalls").toVariant() or []
refused_ops = [call.get("op") for call in refused_calls]
check(refused_ops == ["registerProvider"],
      "refused-provider: registerProvider is the only recorded facade call, got %s" % refused_ops)
refused_reads = [call.get("op") for call in refused_provider.property("readCalls").toVariant() or []]
check(not refused_reads, "refused-provider: a refused provider reads nothing of the writer, got %s"
      % refused_reads)
retire(refused_provider, "refused-provider")

# A writer with no answer for the memory's first read, as at load time before its snapshot is
# ready: the layout provider starts incapable and turns capable when the read retry finds the
# memory, one revision later; a toggle before that starts nothing (the harness checks).
late_memory = run_harness({"scenario": "late-memory"})
for problem in list(late_memory.property("problems").toVariant() or []):
    failures.append(str(problem))
retire(late_memory, "late-memory")

# The read side of the layout provider's pipeline on the real script: the wake shortcut, one read
# once the identity is ready, the wakes during a read coalesced, the shell side's bounds and the
# provider's own checks of every row, each failure, and the limit on an answer's length (the
# harness checks). A failed read and each of the eight malformed answers - one of them a
# well-formed answer one character over the limit - are said once each; the three reads that came
# back - one of them exactly the limit long - say what they found and how long they took; nothing
# throws.
before = len(messages)
read_pipeline = run_harness({"scenario": "read-pipeline"})
for problem in list(read_pipeline.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
check(sum("the bars' requests could not be read" in message for message in journal) == 1,
      "read-pipeline: a failed read is said once")
check(sum("the bars' requests came back malformed" in message for message in journal) == 8,
      "read-pipeline: each malformed answer is said once")
reads = call_lines(journal, READ_LINE, "layout provider: read ")
check(None not in reads and [read[:2] for read in reads] == [(2, 5)] * 3,
      "read-pipeline: each of the three reads that came back says what it found and how long it took, got %s" % reads)
thrown = [message for message in journal if "TypeError" in message or "ReferenceError" in message]
check(not thrown, "read-pipeline: nothing threw, got %s" % thrown)
retire(read_pipeline, "read-pipeline")

# The publication side of the pipeline on the real script: the frames, each bar's own view and its
# changes, where and when they go, what is not written again, a short count and a failure (each
# confirming none of its frames), a new shell, the changes coalesced, and the retirement's offline
# frame before the name's release (the harness checks).
# Each publication that came back says once how many frames it carried, how many the shell wrote
# and how long it took; the failed one is said once, and so are the offline frames; the thirteen
# reads say what they found and how long they took; nothing throws.
before = len(messages)
publication = run_harness({"scenario": "publication"})
for problem in list(publication.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
published = call_lines(journal, PUBLISHED_LINE, "layout provider: published ")
counts = [line[:2] for line in published if line]
check(None not in published and counts == [(5, 4), (5, 5), (2, 2), (1, 1), (1, 1), (5, 5), (2, 2), (2, 2), (1, 1), (1, 1), (2, 2), (3, 3),
                  (3, 3), (1, 1), (1, 1), (1, 1), (1, 1)],
      "publication: each publication that came back before the retirement says its frames and what the shell wrote"
      " once, got %s" % counts)
check(sum("the bars' layout state could not be published" in message for message in journal) == 1,
      "publication: the failed publication is said once")
check(sum(message == "plasmafusion-placement: layout provider: sent 5 offline frame(s)" for message in journal) == 1,
      "publication: the offline frames are said once")
reads = call_lines(journal, READ_LINE, "layout provider: read ")
five, four = (4, 1), (3, 1)
check(None not in reads and [read[:2] for read in reads] == [five] * 3 + [four] + [five] * 6 + [four] + [five] * 2,
      "publication: each of the thirteen reads that came back says what it found and how long it took, got %s" % reads)
thrown = [message for message in journal if "TypeError" in message or "ReferenceError" in message]
check(not thrown, "publication: nothing threw, got %s" % thrown)
check(not [message for message in journal if OVER_LINE.fullmatch(message)],
      "publication: no call there is over the limit")
retire(publication, "publication")

# Two bars on the session's view, whose session's start went out in a publication that failed:
# the session's end, which brings each bar's frame back to what the shell confirmed last, goes
# out to both (the harness checks). The two publications that came back say their two frames
# each, the failed one is said once, and nothing throws.
before = len(messages)
unconfirmed_run = run_harness({"scenario": "unconfirmed"})
for problem in list(unconfirmed_run.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
published = call_lines(journal, PUBLISHED_LINE, "layout provider: published ")
check(None not in published and [line[:2] for line in published] == [(2, 2), (2, 2)],
      "unconfirmed: each publication that came back says its frames and what the shell wrote, got %s" % published)
check(sum("the bars' layout state could not be published" in message for message in journal) == 1,
      "unconfirmed: the failed publication is said once")
thrown = [message for message in journal if "TypeError" in message or "ReferenceError" in message]
check(not thrown, "unconfirmed: nothing threw, got %s" % thrown)
retire(unconfirmed_run, "unconfirmed")

# Decision 1's time limit on the real script, the harness setting each call's timing: a read and a
# publication answered at once, and a read whose owner lookup took 70 ms, measured from its own
# call; two whose script ran from the call's start for 70 ms - over the 50 ms limit by their
# length from that start, said right after their lines - two that waited 70 ms but whose script
# started 1 ms before the answer, not over - and two whose start lies outside the call, so their
# 70 ms from call to answer puts them over; a short one of those is not over; then a malformed
# read and five malformed publications - the first with a wake during it - each said once and
# each followed by the read that sends the frame again, one the shell wrote none of, which the
# next read sends again too, and the frame told at last; then a session's start whose publication
# failed, and one answered malformed, each followed by the session's end, which goes out though
# its frame says what the shell confirmed last (answered a step after it went out, not at once);
# then a publication whose answer is longer than the limit, malformed, and the read that sends
# its frame again. Nothing throws.
before = len(messages)
time_limit = run_harness({"scenario": "time-limit"})
for problem in list(time_limit.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
events = []
for message in journal:
    for kind, pattern, marker in (("read", READ_LINE, "layout provider: read "),
                                  ("published", PUBLISHED_LINE, "layout provider: published ")):
        if marker in message:
            # A line that does not parse is an event of its own kind, as an over line is below:
            # the order check then fails with it, and the length checks never read its text.
            line = call_lines([message], pattern, marker)[0]
            events.append(((kind,) + line[2:]) if line else ("unparsed " + kind, message))
    over = OVER_LINE.fullmatch(message)
    if over:
        events.append(("over " + over.group(1), over.group(3), int(over.group(2))))
    if "layout provider: a " in message and "over the 50 ms limit" in message and not over:
        events.append(("unparsed over", message))
    if "the bars' requests came back malformed" in message:
        events.append(("malformed read",))
    if "the bars' layout state came back malformed" in message:
        events.append(("malformed state",))
kinds = [event[0] for event in events]
wanted = (["read", "published", "read"]
          + ["read", "over read", "published", "over publication"]
          + ["read", "published"]
          + ["read", "over read", "published", "over publication"]
          + ["read", "malformed read"]
          + ["malformed state", "read"] * 5
          + ["published", "read", "published", "read"]
          + ["published", "malformed state", "published"]
          + ["malformed state", "read", "published"])
check(kinds == wanted, "time-limit: the calls' lines and the limit's, in order, got %s" % events)
if kinds == wanted:
    def at_once(event):
        return event[1:] == (0, 0)

    def held(event, over):
        return event[1:] == (70, 70) and over[1:] == ("script's start", 70)

    def waited(event):
        return event[1:] == (70, 1)

    def outside(event, over):
        return event[1:] == (70, None) and over[1:] == ("call", 70)

    for index in (0, 1, 2, 16, 18, 20, 22, 24, 25, 26, 27, 28, 33, 34):
        check(at_once(events[index]), "time-limit: a call answered at once, from its own call, has its length from"
              " the script's start, under 50 ms (%s)" % (events[index],))
    check(held(events[3], events[4]) and held(events[5], events[6]),
          "time-limit: a call whose script ran 70 ms is over the limit by its length from that start (%s)"
          % (events[3:7],))
    check(waited(events[7]) and waited(events[8]),
          "time-limit: a call with 70 ms elapsed but only 1 ms from script start stays under the limit (%s)"
          % (events[7:9],))
    check(outside(events[9], events[10]) and outside(events[11], events[12]),
          "time-limit: a start outside the call leaves the length from call to answer to decide (%s)"
          % (events[9:13],))
    check(events[13][1:] == (0, None),
          "time-limit: a short call whose start lies outside it is not over the limit (%s)" % (events[13],))
thrown = [message for message in journal if "TypeError" in message or "ReferenceError" in message]
check(not thrown, "time-limit: nothing threw, got %s" % thrown)
retire(time_limit, "time-limit")

# The layout provider's own rules, without the script: what start(), setSession() and retire()
# move and what they leave alone, and its identity name refused, denied, unread and dropped by
# an early retirement (the harness checks). Each name that is no identity is said once.
before = len(messages)
provider_rules = run_harness({"scenario": "provider-rules"})
for problem in list(provider_rules.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
check(sum("the identity name was not granted" in message for message in journal) == 2,
      "provider-rules: a refused name and a bus error are each said once")
check(sum("the identity name's owner could not be read" in message for message in journal) == 1,
      "provider-rules: an owner that cannot be read is said once")
# The answers arrive in signal handlers, where a throw shows only in the journal.
thrown = [message for message in journal if "TypeError" in message or "ReferenceError" in message]
check(not thrown, "provider-rules: nothing threw, got %s" % thrown)
retire(provider_rules, "provider-rules")

# P5's prepared target on a provider of its own (the harness checks each decision, frame and end):
# its revisions each a change of what a bar is told, each fresh decision said once - 38 ready and
# 21 refused, the later lifetimes' refusals and prepares among them - and each end of a
# preparation said with its reason, a holder's widget gone among them; a read again or a
# conflicting payload decides nothing new and says nothing, and a malformed prepare is a refusal
# of the read's, not a decision.
before = len(messages)
prepare_run = run_harness({"scenario": "prepare"})
for problem in list(prepare_run.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
ready_lines = sum("layout provider: a prepare is ready" in message for message in journal)
refused_lines = sum("layout provider: a prepare was refused" in message for message in journal)
check(ready_lines == 38 and refused_lines == 21,
      "prepare: each fresh decision is said once, 38 ready and 21 refused, got %s and %s" % (ready_lines, refused_lines))
ends = {}
for message in journal:
    if "layout provider: a preparation ended, " in message:
        reason = message.split("a preparation ended, ", 1)[1].strip().strip('"')
        ends[reason] = ends.get(reason, 0) + 1
check(ends == {"focus-changed": 11, "target-departed": 11, "view-changed": 3, "shell-replaced": 1,
              "consumer-retired": 1},
      "prepare: each preparation's end is said with its reason, got %s" % ends)
thrown = [message for message in journal if "TypeError" in message or "ReferenceError" in message]
check(not thrown, "prepare: nothing threw, got %s" % thrown)
retire(prepare_run, "prepare")

# P5's desired mode on the real script (the harness checks each set, its completion and what the
# tiler did). Each set whose start is retried is said under way once and decided once later -
# five done (three of them beside another payload or a query under their identity), and one each
# cancelled by the shortcut, refused for a target gone, for an admission refused for good, for its
# desktop removed, for its activity removed, for its output unplugged, under a new shell, and
# for a throwing admission. No exception escapes the retry handler.
before = len(messages)
set_run = run_harness({"scenario": "set"})
for problem in list(set_run.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
under_way = sum("layout provider: a set (" in message and ") is under way" in message for message in journal)
later = sorted(message.split("layout provider: a set ", 1)[1] for message in journal
               if "layout provider: a set is done" in message or "layout provider: a set was refused, " in message)
check(under_way == 13 and later == ["is done"] * 5 + ["was refused, admission-refused", "was refused, cancelled",
                                                       "was refused, shell-replaced", "was refused, target-departed",
                                                       "was refused, unavailable",
                                                       "was refused, view-changed", "was refused, view-changed",
                                                       "was refused, view-changed"],
      "set: each retried set is under way once and decided once later, got %s under way and %s" % (under_way, later))
thrown = [message for message in journal if "TypeError" in message or "ReferenceError" in message]
check(not thrown, "set: nothing threw, got %s" % thrown)
retire(set_run, "set")

# A third run: the master a native teardown released without restoring it (a removed desktop, a
# second window of its app, a move of the master). The harness asserts the geometry, the settle
# answers and the records step by step; the journal lines are checked here.
before = len(messages)
released = run_harness({"scenario": "released"})
for problem in list(released.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
settled = sum("a released master's record is settled" in message for message in journal)
held = sum("a released master has not settled; its record is held" in message for message in journal)
refused = sum("the admission was refused (7)" in message for message in journal)
check(settled == 13, "released: thirteen records were settled (returned, moved, re-checked, unresized, unmaximized, at the toggle, left alone,"
      " after its app's second window, in its quiet second, released in the gap, transferred, the display back, after a closed one),"
      " got %s" % settled)
check(held == 4, "released: four records were held (a drag held still, maximized, unanswered, no float to return to), got %s" % held)
check(refused == 1, "released: one admission stayed refused, after its retries, got %s" % refused)
check(sum("the tree was refused" in message for message in journal) == 1,
      "released: the newer press was refused once and the dropped retry asked for nothing")
# No TypeError in the run. The script was destroyed with a master's record held, then the
# master's drag ended and a tree ended: a callback left connected to the window or to the facade
# runs in a context that is gone and says so. And a reference to a destroyed window handed to
# the facade does not convert: the mock throws as the compositor does, from inside a signal
# handler, where only the engine's message shows it.
errors = [message for message in journal if "TypeError" in message]
check(not errors, "released: no call into a destroyed script and no destroyed window handed to the facade, got %s" % errors)
retire(released, "released")

# A fourth run: the script unloaded mid-session as KWin unloads a declarative script
# (KWinScript): its own context goes first, and the script's Component.onDestruction runs while
# that context is being torn down. In KWin a handler of the dying script that ran then and read
# a setting through the KWin context property crashed the compositor (2026-11-14); here the same
# read throws (KWin is gone), or the process crashes. Nothing of the script may run there but
# its own teardown: no TypeError and no ReferenceError at all, a readConfig one included. The
# harness checks that the session ended all the same and that nothing answers afterwards.
# The same with the master released by the native layer in between (unloadVacated): the
# teardown goes through the released master's settle, which records once it is settled.


def run_unload(name, initial):
    before = len(messages)
    holder = KWinScript(engine)
    unload = component.createWithInitialProperties(initial)
    state = {"made": False, "gone": False}

    def drive():
        if not state["made"] and unload.property("scriptWanted"):
            state["made"] = True
            unload.setProperty("kwinScript", holder.make(unload.property("scriptWanted")))
        if state["made"] and not state["gone"] and unload.property("unloadWanted"):
            state["gone"] = True
            holder.deleteLater()
            QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
            app.processEvents()
            unload.setProperty("unloaded", True)
        if unload.property("done"):
            QTimer.singleShot(300, app.quit)
        else:
            QTimer.singleShot(20, drive)

    QTimer.singleShot(20, drive)
    app.exec()
    for problem in list(unload.property("problems").toVariant() or []):
        failures.append(str(problem))
    check(state["gone"], "%s: the harness asked for the unload and the driver unloaded the script" % name)
    thrown = [message for message in messages[before:] if "TypeError" in message or "ReferenceError" in message]
    check(not thrown, "%s: nothing of the script ran in its dying context but its own teardown, got %s" % (name, thrown))
    retire(unload, name)


run_unload("unload", {"scenario": "unload"})
run_unload("unload (vacated)", {"scenario": "unload", "unloadVacated": True})

# Windows an earlier instance left with a native record (plasma-fusion#175), found when the
# script starts: where the fork lets the current provider end the record, it does - back to
# the floating frame unless the user put the window where it stands - and the window is
# tileable again; where it does not, the window is left alone and stays out of the tiling.
for name, initial, settled in (
        ("stranded", {"strandedSuccessor": True, "strandedPlaced": False}, True),
        ("stranded (placed by the user)", {"strandedSuccessor": True, "strandedPlaced": True}, True),
        ("stranded (old fork)", {"strandedSuccessor": False, "strandedPlaced": False}, False)):
    before = len(messages)
    initial = dict(initial, scenario="stranded")
    instance = run_harness(initial)
    for problem in list(instance.property("problems").toVariant() or []):
        failures.append("%s: %s" % (name, problem))
    journal = messages[before:]
    check(sum("still held by an earlier instance" in m for m in journal) == 1
          and any("tiling: 1 window(s) still held by an earlier instance" in m for m in journal),
          "%s: the start says it found the one window, once" % name)
    if settled:
        check(sum("a released master's record is settled" in m for m in journal) == 1,
              "%s: the record is settled once" % name)
    else:
        check(sum("a released master's record was not settled (2)" in m for m in journal) == 1,
              "%s: the old fork's refusal is said once" % name)
    thrown = [m for m in journal if "TypeError" in m or "ReferenceError" in m]
    check(not thrown, "%s: nothing threw, got %s" % (name, thrown))
    retire(instance, name)

if failures:
    for failure in failures:
        print("FAIL tiling_lifecycle_test.py: " + failure)
    sys.exit(1)
print("tiling_lifecycle_test.py: ok")
