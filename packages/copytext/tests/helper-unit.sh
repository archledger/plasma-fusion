#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of plasma-fusion-copytext (copy text from the screen in one step), the helper as it is:
#   1. against stand-ins for Spectacle (the area saved, cancelled, a Spectacle already open),
#      Tesseract, kreadconfig6, busctl (the bus, Klipper, the notification server) and wl-copy,
#      with a PATH of only those and the basic tools, a throw-away HOME and runtime directory;
#   2. on a private session bus with the real busctl, fake_session.py owning Klipper's and the
#      notification server's names (the calls' signatures as D-Bus takes them);
#   3. real text recognition: Tesseract reads a line drawn with Pillow in the repository's Manrope.
# Test tooling only, not installed; never touches the caller's session or clipboard.
#
#   helper-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first. Parts 2 and 3 are
# skipped without dbus-run-session and python3-dbus, or Tesseract (with eng) and Pillow;
# PLASMA_FUSION_REQUIRE=bus,ocr makes them fail instead (CI).
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
HELPER=$HERE/../plasma-fusion-copytext
REQUIRE=${PLASMA_FUSION_REQUIRE:-}
[ -f "$HELPER" ] || { echo "FAIL: the helper $HELPER is missing"; exit 1; }
rm -rf "${BASE:?}"
mkdir -p "$BASE"

PASS=0 FAIL=0 SKIP=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
skip() { # NAME PART REASON
  case ",$REQUIRE," in *",$2,"*) bad "$1: $3" ;; *) SKIP=$((SKIP + 1)); echo "SKIP $1: $3" ;; esac
}

# The basic tools the helper and the stand-ins use; nothing else of the system is in PATH.
SYS=$BASE/sys
mkdir -p "$SYS"
for t in cat cp dirname flock id ln mkdir mktemp rm sed sleep stat wc; do
  ln -s "$(command -v "$t")" "$SYS/$t"
done

# Stand-ins. T is the case directory: logs, the image Spectacle "saves" (region.png), the text
# Tesseract "reads" (ocr.txt). Each busctl call is one file of NUL-separated arguments.
fakes() { # DIR
  mkdir -p "$1"
  cat >"$1/spectacle" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$T/spectacle.log"
# The helper's lock must not stay open in Spectacle (a window left open would hold it).
[ ! -e /proc/$$/fd/9 ] || echo "fd 9 open: $*" >>"$T/fd9"
out=
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
case ${FAKE_SPECTACLE:-save} in
  save) [ -z "$out" ] || cp "$T/region.png" "$out" ;;
  # The user takes a while to choose the area.
  slow) sleep 1.5; cp "$T/region.png" "$out" ;;
  cancel) ;;
esac
exit 0
EOF
  cat >"$1/tesseract" <<'EOF'
#!/bin/bash
if [ "${1:-}" = --list-langs ]; then
  set -- $FAKE_LANGS
  printf 'List of available languages in "/fake/tessdata/" (%s):\n' $#
  printf '%s\n' "$@"
  exit 0
fi
printf '%s\n' "$*" >>"$T/tesseract.log"
[ -s "$1" ] && printf 'image %s\n' "$(dirname "$1")" >>"$T/tesseract.log"
cat "$T/ocr.txt"
exit "${FAKE_TESS_RC:-0}"
EOF
  cat >"$1/kreadconfig6" <<'EOF'
#!/bin/bash
[ "$*" = "--file spectaclerc --group General --key ocrLanguages" ] || exit 1
printf '%s\n' "${FAKE_OCRLANGS:-}"
EOF
  cat >"$1/busctl" <<'EOF'
#!/bin/bash
n=$(cat "$T/bus.n" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$T/bus.n"
printf '%s\0' "$@" >"$T/bus.$n"
case " $* " in
  # Spectacle open: its name on the bus.
  *" NameHasOwner s org.kde.spectacle "*) if [ -e "$T/instance" ]; then echo "b true"; else echo "b false"; fi ;;
  *" org.kde.klipper "*) [ "${FAKE_KLIPPER:-1}" = 1 ] || { echo "Unit name org.kde.klipper not found" >&2; exit 1; } ;;
  *" Notify "*) echo "u $n" ;;
esac
exit 0
EOF
  cat >"$1/wl-copy" <<'EOF'
#!/bin/bash
# It stays in the background to serve the clipboard: it must not hold the helper's lock.
[ ! -e /proc/$$/fd/9 ] || echo "fd 9 open: wl-copy" >>"$T/fd9"
cat >"$T/wlcopy.txt"
EOF
  chmod +x "$1"/*
}

setup_case() { # NAME
  CASE=$BASE/$1
  mkdir -p "$CASE/home" "$CASE/run"
  chmod 0700 "$CASE/run"
  fakes "$CASE/bin"
  printf 'PNG' >"$CASE/region.png"
  printf '  Hello Plasma Fusion  \n\n second line\n\f\n' >"$CASE/ocr.txt"
}
# Runs the helper in the case; FAKE_* and PLASMA_FUSION_* settings as arguments (NAME=VALUE).
run_helper() {
  env -i PATH="$CASE/bin:$SYS" HOME="$CASE/home" XDG_RUNTIME_DIR="$CASE/run" T="$CASE" \
    FAKE_LANGS="eng osd" "$@" /bin/bash "$HELPER" >>"$CASE/out" 2>&1
}
# The text given to Klipper (setClipboardContents), the notifications as SUMMARY|BODY|HINTS.
calls() { # METHOD: the matching busctl calls, one argument list per line, fields joined by |
  local f a i
  for f in "$CASE"/bus.[0-9]*; do
    [ -e "$f" ] || continue
    mapfile -d '' -t a <"$f"
    for i in "${!a[@]}"; do
      [ "${a[$i]}" = "$1" ] || continue
      case $1 in
        setClipboardContents) printf '%s\n' "${a[$((i + 2))]}" ;;
        Notify) printf '%s|%s|%s|%s\n' "${a[$((i + 5))]}" "${a[$((i + 6))]}" "${a[*]:$((i + 8))}" "${a[$((i + 2))]}" ;;
      esac
    done
  done
}
# Anything in the runtime directory but the lock.
leftover() { find "$CASE/run" -mindepth 1 ! -name plasma-fusion-copytext.lock | head -1; }

# 1a. The area is saved: its text goes to Klipper (lines trimmed, empty ones dropped), a transient
#     notification says so, and no image is left behind.
setup_case copied
rc=0; run_helper || rc=$?
[ "$rc" = 0 ] && ok "a selected area: the helper succeeds" || bad "a selected area: exit $rc ($(cat "$CASE/out"))"
args=$(head -1 "$CASE/spectacle.log")
case $args in "-b -n -r -o $CASE/run/plasma-fusion-copytext."*/region.png) ok "Spectacle captures a region in background mode into the runtime directory" ;;
  *) bad "Spectacle's arguments: $args" ;; esac
[ "$(head -1 "$CASE/tesseract.log")" = "$(sed -n 's/^-b -n -r -o //p' "$CASE/spectacle.log") stdout -l eng --psm 3" ] &&
  grep -q '^image ' "$CASE/tesseract.log" && ok "Tesseract reads the saved area (eng, automatic page segmentation)" ||
  bad "Tesseract's arguments: $(cat "$CASE/tesseract.log")"
[ "$(calls setClipboardContents)" = "$(printf 'Hello Plasma Fusion\nsecond line')" ] &&
  ok "Klipper gets the text: lines trimmed, empty lines and the page break dropped" || bad "the clipboard text: $(calls setClipboardContents | cat -A)"
[ "$(calls Notify)" = "Text copied|Hello Plasma Fusion (and 1 more line)|1 transient b true -1|Plasma Fusion" ] &&
  ok "a notification says so, with the first line, transient" || bad "the notification: $(calls Notify)"
[ -z "$(leftover)" ] && ok "no image or directory is left behind" || bad "left behind: $(leftover)"

# 1b. Cancelled (Esc): nothing read, copied or said.
setup_case cancel
rc=0; run_helper FAKE_SPECTACLE=cancel || rc=$?
[ "$rc" = 0 ] && [ ! -e "$CASE/tesseract.log" ] && [ -z "$(calls setClipboardContents)$(calls Notify)" ] && [ -z "$(leftover)" ] &&
  ok "cancelled: no text recognition, clipboard or notification, nothing left" || bad "cancelled: exit $rc, $(cat "$CASE/out") $(calls Notify)"

# 1c. Spectacle already open (a screenshot being edited; org.kde.spectacle on the bus): not taken
#     over, its own region capture.
setup_case open
: >"$CASE/instance"
rc=0; run_helper || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$CASE/spectacle.log")" = "--region" ] && [ ! -e "$CASE/tesseract.log" ] && [ -z "$(calls Notify)" ] &&
  ok "with Spectacle open: spectacle --region there, no background capture" || bad "Spectacle open: exit $rc, $(cat "$CASE/spectacle.log")"
[ ! -e "$CASE/fd9" ] && [ ! -e "$BASE/copied/fd9" ] && ok "Spectacle never holds the helper's lock (capture and --region)" ||
  bad "the lock reached Spectacle: $(cat "$CASE/fd9" "$BASE/copied/fd9" 2>/dev/null)"

# 1d. A second press while the area is being chosen does nothing; the first goes on.
setup_case twice
run_helper FAKE_SPECTACLE=slow &
first=$!
sleep 0.5
start=$SECONDS; rc=0; run_helper FAKE_SPECTACLE=slow || rc=$?
second=$((SECONDS - start))
wait "$first" || true
[ "$rc" = 0 ] && [ "$second" -le 1 ] && [ "$(grep -c '^-b ' "$CASE/spectacle.log")" = 1 ] &&
  [ "$(calls setClipboardContents)" = "$(printf 'Hello Plasma Fusion\nsecond line')" ] &&
  ok "a second press while choosing the area: no second capture; the first one copies its text" ||
  bad "twice: exit $rc after $second s, $(cat "$CASE/spectacle.log") / $(calls setClipboardContents)"

# 1e. Languages as Spectacle chooses them.
lang_of() { sed -n '1s/.* -l \([^ ]*\) .*/\1/p' "$CASE/tesseract.log"; }
setup_case langs
run_helper FAKE_LANGS="deu eng fra ita osd spa" FAKE_OCRLANGS="deu,osd,jpn,fra,eng,deu,spa,ita" || true
[ "$(lang_of)" = deu+fra+eng+spa ] && ok "Spectacle's languages: installed ones in its order, no osd or repeats, at most four" ||
  bad "languages: $(lang_of)"
setup_case langs-default
run_helper FAKE_LANGS="osd fra eng" FAKE_OCRLANGS="jpn" || true
[ "$(lang_of)" = fra ] && ok "none of Spectacle's languages installed: the first installed one that is not osd" || bad "default language: $(lang_of)"

# 1f. No language data: a hint (kept in the history), no capture.
setup_case nolang
rc=0; run_helper FAKE_LANGS="osd" || rc=$?
case $(calls Notify) in "No text recognition languages|Install Tesseract's data"*"tesseract-langpack-eng (Fedora)"*"|0 -1|Plasma Fusion")
  [ "$rc" = 1 ] && [ ! -e "$CASE/spectacle.log" ] && ok "no language data: a notification names the package, nothing is captured" ||
    bad "no language data: exit $rc, $(cat "$CASE/spectacle.log" 2>/dev/null)" ;;
  *) bad "no language data: $(calls Notify)" ;; esac

# 1g. No tesseract command: Spectacle's region capture as before (Extract Text there).
setup_case notesseract
rm "$CASE/bin/tesseract"
rc=0; run_helper || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$CASE/spectacle.log")" = "--region" ] && [ -z "$(calls Notify)" ] &&
  ok "without the tesseract command: spectacle --region, as before" || bad "without tesseract: exit $rc, $(cat "$CASE/spectacle.log" 2>/dev/null)"

# 1h. Nothing found; Tesseract fails.
setup_case notext
printf '\f\n   \n\n' >"$CASE/ocr.txt"
rc=0; run_helper || rc=$?
[ "$rc" = 0 ] && [ -z "$(calls setClipboardContents)" ] &&
  [ "$(calls Notify)" = "No text found|No text was found in the selected area.|1 transient b true -1|Plasma Fusion" ] &&
  ok "no text in the area: the clipboard is left alone, a notification says so" || bad "no text: exit $rc, $(calls Notify)"
setup_case tessfail
rc=0; run_helper FAKE_TESS_RC=1 || rc=$?
[ "$rc" = 1 ] && [ -z "$(calls setClipboardContents)" ] && case $(calls Notify) in "Could not read the text|"*) true ;; *) false ;; esac &&
  [ -z "$(leftover)" ] && ok "Tesseract fails: the clipboard is left alone, a notification says so" || bad "tesseract fails: exit $rc, $(calls Notify)"

# 1i. Text that looks like an option and markup: Klipper gets it as it is, the notification escaped.
setup_case markup
printf -- '- <b>R&D</b> --help\n' >"$CASE/ocr.txt"
run_helper || true
[ "$(calls setClipboardContents)" = "- <b>R&D</b> --help" ] && ok "text starting with a dash or holding markup reaches Klipper as it is" ||
  bad "the clipboard text: $(calls setClipboardContents)"
case $(calls Notify) in
  "Text copied|- &lt;b&gt;R&amp;D&lt;/b&gt; --help|"*) ok "the notification shows it escaped" ;;
  *) bad "the notification: $(calls Notify)" ;;
esac
setup_case long
{ printf '%090d\n' 0; printf 'b\nc\n'; } >"$CASE/ocr.txt"
run_helper || true
case $(calls Notify) in "Text copied|$(printf '%079d' 0)… (and 2 more lines)|"*) ok "a long first line is cut at 80 characters; more lines are counted" ;;
  *) bad "a long text's notification: $(calls Notify)" ;; esac

# ... in characters, also without a UTF-8 locale (a D-Bus string must be valid UTF-8).
setup_case utf8
python3 -c 'print("é" * 90)' >"$CASE/ocr.txt"
run_helper || true
case $(calls Notify) in "Text copied|$(python3 -c 'print("é" * 79 + "…")')|"*) ok "a line of non-ASCII letters is cut in characters, not bytes" ;;
  *) bad "a non-ASCII line's notification: $(calls Notify)" ;; esac

# 1j. No Klipper: wl-copy; neither: a notification.
setup_case wlcopy
run_helper FAKE_KLIPPER=0 || true
[ "$(cat "$CASE/wlcopy.txt" 2>/dev/null)" = "$(printf 'Hello Plasma Fusion\nsecond line')" ] &&
  case $(calls Notify) in "Text copied|"*) true ;; *) false ;; esac &&
  ok "no Klipper: wl-copy takes the text" || bad "no Klipper: $(cat "$CASE/wlcopy.txt" 2>/dev/null) / $(calls Notify)"
[ ! -e "$CASE/fd9" ] && ok "wl-copy, which stays to serve the clipboard, does not hold the helper's lock" || bad "wl-copy: $(cat "$CASE/fd9")"
setup_case noclipboard
rm "$CASE/bin/wl-copy"
rc=0; run_helper FAKE_KLIPPER=0 || rc=$?
[ "$rc" = 1 ] && case $(calls Notify) in "Could not copy the text|"*) true ;; *) false ;; esac &&
  ok "no Klipper and no wl-copy: a notification says the text was not copied" || bad "no clipboard: exit $rc, $(calls Notify)"

# 2. A private session bus, the real busctl: Klipper and the notification server take the calls.
bus_case() { # NAME [--no-klipper]: the helper on a private bus; LOG has the services' calls.
  # BUS_TEXT: what Tesseract "reads" instead of the default.
  setup_case "$1"
  rm "$CASE/bin/busctl"
  ln -s "$(command -v busctl)" "$CASE/bin/busctl"
  [ "${2:-}" = --no-klipper ] && rm "$CASE/bin/wl-copy"
  [ -z "${BUS_TEXT:-}" ] || printf '%s' "$BUS_TEXT" >"$CASE/ocr.txt"
  LOG=$CASE/session.jsonl
  : >"$LOG"
  env -i PATH="$CASE/bin:$SYS" HOME="$CASE/home" XDG_RUNTIME_DIR="$CASE/run" T="$CASE" FAKE_LANGS="eng osd" \
    PY="$(command -v python3)" SESSION="$HERE/fake_session.py" LOG="$LOG" HELPER="$HELPER" \
    ${OCR_IMAGE:+REAL_TESSERACT="$(command -v tesseract)"} \
    "$(command -v dbus-run-session)" --dbus-daemon="$(command -v dbus-daemon)" \
    --config-file="$ROOT/packages/kwin/tests/offscreen/session-bus.conf" -- /bin/bash -c '
      coproc SVC { "$PY" "$SESSION" "$LOG" "$@"; }
      read -r -t 20 ready <&"${SVC[0]}" && [ "$ready" = ready ] || exit 9
      [ -z "${REAL_TESSERACT:-}" ] || ln -sf "$REAL_TESSERACT" "$T/bin/tesseract"
      rc=0; /bin/bash "$HELPER" || rc=$?
      eval "exec ${SVC[1]}>&-"
      wait
      exit "$rc"' _ "${2:-}" >"$CASE/out" 2>&1
}
logged() { # PYTHON EXPRESSION over the calls (c: a list of dicts)
  python3 -c 'import json,sys; c=[json.loads(l) for l in open(sys.argv[1])]; print(eval(sys.argv[2]))' "$LOG" "$1"
}
have_bus() {
  command -v dbus-run-session >/dev/null 2>&1 && command -v dbus-daemon >/dev/null 2>&1 && command -v busctl >/dev/null 2>&1 &&
    python3 -c 'import dbus, gi' 2>/dev/null
}
if have_bus; then
  rc=0; bus_case bus || rc=$?
  [ "$rc" = 0 ] && [ "$(logged '[x["text"] for x in c if x["call"] == "setClipboardContents"]')" = "['Hello Plasma Fusion\\nsecond line']" ] &&
    ok "private bus: Klipper's setClipboardContents takes the text" || bad "private bus: exit $rc, $(cat "$LOG") $(cat "$CASE/out")"
  [ "$(logged '[(x["app"], x["icon"], x["summary"], x["body"], x["hints"], x["timeout"]) for x in c if x["call"] == "Notify"]')" = \
    "[('Plasma Fusion', 'document-scan', 'Text copied', 'Hello Plasma Fusion (and 1 more line)', {'transient': True}, -1)]" ] &&
    ok "private bus: the notification server takes the notification (app, icon, transient hint)" || bad "private bus, notification: $(cat "$LOG")"
  # Text that starts like an option reaches Klipper (busctl reads options up to "--").
  rc=0; BUS_TEXT=$'-v Hello & <you>\n--help\n' bus_case bus-dash || rc=$?
  [ "$rc" = 0 ] && [ "$(logged '[x["text"] for x in c if x["call"] == "setClipboardContents"]')" = "['-v Hello & <you>\\n--help']" ] &&
    [ "$(logged '[x["body"] for x in c if x["call"] == "Notify"]')" = "['-v Hello &amp; &lt;you&gt; (and 1 more line)']" ] &&
    ok "private bus: text that starts like an option reaches Klipper, escaped in the notification" ||
    bad "private bus, a dash: exit $rc, $(cat "$LOG") $(cat "$CASE/out")"
  rc=0; bus_case bus-noklipper --no-klipper || rc=$?
  [ "$rc" = 1 ] && [ "$(logged '[x["summary"] for x in c]')" = "['Could not copy the text']" ] &&
    ok "private bus without Klipper: the failed call is noticed" || bad "private bus without Klipper: exit $rc, $(cat "$LOG") $(cat "$CASE/out")"
else
  skip "private bus" bus "needs dbus-run-session, busctl, python3-dbus and python3-gobject"
fi

# 3. Real text recognition: a line drawn in Manrope at 14 px on a dark surface, as on a screen.
WORDS="Plasma Fusion copies 4812 words"
if command -v tesseract >/dev/null 2>&1 && tesseract --list-langs 2>/dev/null | grep -qx eng &&
  python3 -c 'import PIL' 2>/dev/null && have_bus; then
  OCR_IMAGE=$BASE/screen.png
  python3 - "$ROOT/fonts/manrope/static/Manrope-Regular.ttf" "$WORDS" "$OCR_IMAGE" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFont
font = ImageFont.truetype(sys.argv[1], 14)
image = Image.new("RGB", (360, 60), (32, 33, 38))
ImageDraw.Draw(image).text((16, 20), sys.argv[2], font=font, fill=(232, 233, 238))
image.save(sys.argv[3])
PY
  rc=0
  (setup_case() { CASE=$BASE/$1; mkdir -p "$CASE/home" "$CASE/run"; chmod 0700 "$CASE/run"; fakes "$CASE/bin"; cp "$OCR_IMAGE" "$CASE/region.png"; }
   bus_case ocr) || rc=$?
  CASE=$BASE/ocr LOG=$BASE/ocr/session.jsonl
  got=$(logged '"".join(x["text"] for x in c if x["call"] == "setClipboardContents")' 2>/dev/null || true)
  [ "$rc" = 0 ] && [ "$got" = "$WORDS" ] && ok "real Tesseract reads a 14 px screen line: \"$got\"" ||
    bad "real Tesseract: exit $rc, \"$got\" ($(cat "$CASE/out"))"
else
  skip "real text recognition" ocr "needs tesseract with eng, Pillow, dbus-run-session and python3-dbus"
fi

echo "helper-unit: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" = 0 ]
