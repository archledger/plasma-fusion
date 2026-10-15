#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The viewers of Quick Look in the real application, offscreen on a private session bus: sample
# files of every kind (written here, no tools beyond Python's standard library) are shown in turn
# with --test-report, which writes what each viewer showed; the checks read that report.
#
#   run-viewers.sh APP WORKDIR
set -euo pipefail
APP=${1:?usage: run-viewers.sh APP WORKDIR}
WORK=${2:?usage: run-viewers.sh APP WORKDIR}
rm -rf "$WORK"
mkdir -p "$WORK/samples/folder/sub" "$WORK/home/.cache/thumbnails"
S=$WORK/samples

python3 - "$S" <<'PY'
import math, struct, sys, wave, zipfile, zlib
s = sys.argv[1]

def png(path, w, h):
    raw = b"".join(b"\x00" + bytes((40, 120, 200)) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
png(s + "/picture.png", 64, 48)

# Two frames of one pixel (black, then white), looping.
frame = lambda data: bytes.fromhex("21f904000a000000" "2c00000000010001" "0000") + bytes.fromhex(data)
gif = (b"GIF89a" + bytes.fromhex("01000100800000" "000000ffffff")
       + bytes.fromhex("21ff0b") + b"NETSCAPE2.0" + bytes.fromhex("0301000000")
       + frame("0202440100") + frame("02024c0100") + b";")
open(s + "/moving.gif", "wb").write(gif)

open(s + "/drawing.svg", "w").write('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="24">'
                                    '<rect width="32" height="24" fill="#3daee9"/></svg>\n')
open(s + "/notes.txt", "w", encoding="utf-8").write("Hello Plasma Fusion\nsecond line €\n")
open(s + "/script.py", "w").write("def hello():\n    print('hello')\n")

# A one-page PDF with a line of text, its cross-reference table at the right offsets.
objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R "
        b"/Resources << /Font << /F1 5 0 R >> >> >>",
        None,
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
text = b"BT /F1 18 Tf 30 100 Td (Plasma Fusion Quick Look) Tj ET"
objs[3] = b"<< /Length %d >>\nstream\n" % len(text) + text + b"\nendstream"
out, offsets = b"%PDF-1.4\n", []
for i, o in enumerate(objs, 1):
    offsets.append(len(out))
    out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
out += b"".join(b"%010d 00000 n \n" % off for off in offsets)
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
open(s + "/page.pdf", "wb").write(out)

# One second of a 440 Hz tone.
with wave.open(s + "/tone.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
    w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / 8000))) for i in range(8000)))

for name, data in (("folder/a.txt", "a\n"), ("folder/b.txt", "bb\n"), ("folder/sub/c.txt", "ccc\n")):
    open(s + "/" + name, "w").write(data)
with zipfile.ZipFile(s + "/archive.zip", "w") as z:
    z.writestr("inside.txt", "inside\n")

# A text document with the picture of its first page inside (what an office suite saves): KIO's
# OpenDocument thumbnailer (kio-extras) shows it.
def png_bytes(w, h):
    raw = b"".join(b"\x00" + bytes((200, 60, 60)) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
with zipfile.ZipFile(s + "/letter.odt", "w") as z:
    z.writestr(zipfile.ZipInfo("mimetype"), "application/vnd.oasis.opendocument.text")
    z.writestr("Thumbnails/thumbnail.png", png_bytes(96, 128))
    z.writestr("content.xml", '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"/>')
    z.writestr("META-INF/manifest.xml", '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"/>')
PY

FILES=(picture.png moving.gif drawing.svg notes.txt script.py page.pdf tone.wav folder archive.zip letter.odt gone.txt)
args=()
for f in "${FILES[@]}"; do args+=("$S/$f"); done

# A HOME of its own (KIO's thumbnail cache, the configuration) and no sound device needed.
env HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" XDG_CACHE_HOME="$WORK/home/.cache" \
  XDG_DATA_HOME="$WORK/home/.local/share" QT_QPA_PLATFORM=offscreen LANG=C.UTF-8 QT_FORCE_STDERR_LOGGING=1 \
  dbus-run-session -- timeout 120 "$APP" --test-report "$WORK/report.json" "${args[@]}" >"$WORK/app.log" 2>&1 || {
  echo "the application failed:"; cat "$WORK/app.log"; exit 1; }

first=0
python3 - "$WORK/report.json" <<'PY' || first=1
import json, sys
r = {e["name"]: e for e in json.load(open(sys.argv[1]))}
failed = 0
def check(ok, what):
    global failed
    print(("PASS " if ok else "FAIL ") + what)
    failed += not ok

def entry(name, viewer):
    e = r.get(name)
    check(e is not None and e["viewer"] == viewer and e["ready"],
          "%s: %s, ready (%s)" % (name, viewer, json.dumps(e)[:400] if e else "no entry"))
    return (e or {}).get("report", {}), e or {}

rep, _ = entry("picture.png", "imageViewer")
check(rep.get("status") == "ready" and rep.get("width") == 64 and rep.get("height") == 48, "picture.png: decoded at 64 x 48")
rep, _ = entry("moving.gif", "imageViewer")
check(rep.get("status") == "ready" and rep.get("animated") is True, "moving.gif: plays as an animation")
rep, _ = entry("drawing.svg", "imageViewer")
check(rep.get("status") == "ready" and rep.get("paintedWidth", 0) > 0, "drawing.svg: drawn")
rep, e = entry("notes.txt", "textViewer")
check(e.get("copied") == "Hello Plasma Fusion\nsecond line \u20ac\n", "notes.txt: Copy puts the selected text on the clipboard (%r)" % e.get("copied"))
check(rep.get("length") == len("Hello Plasma Fusion\nsecond line €\n") and rep.get("truncated") is False, "notes.txt: all of its text")
check(rep.get("lines") == 2 and e.get("extra") == "2 lines", "notes.txt: 2 lines (%s, %s)" % (rep.get("lines"), e.get("extra")))
rep, _ = entry("script.py", "textViewer")
check(rep.get("definition") == "Python", "script.py: highlighted as Python (%s)" % rep.get("definition"))
rep, e = entry("page.pdf", "pdfViewer")
check(rep.get("status") == "ready" and rep.get("pages") == 1 and e.get("extra") == "1 page", "page.pdf: one page")
for phase, r2 in (("shown", rep), ("wider", e.get("resized", {}))):
    check(r2.get("width", 0) > 0 and abs(r2.get("pageWidth", 0) - r2.get("width", 0)) < 1,
          "page.pdf %s: the page as wide as the window (%s of %s, scale %s)" % (phase, r2.get("pageWidth"), r2.get("width"), r2.get("scale")))
z = e.get("zoomed", {})
check(abs(z.get("scale", 0) - 1.5 * e.get("resized", {}).get("scale", 0)) < 1e-6 and z.get("width", 0) < e.get("resized", {}).get("width", 0),
      "page.pdf zoomed: the zoom kept when the window is narrower again (scale %s)" % z.get("scale"))
rep, e = entry("tone.wav", "mediaViewer")
check(rep.get("status") == "ready" and 900 <= rep.get("duration", 0) <= 1100 and rep.get("hasAudio") is True,
      "tone.wav: a second of sound (%s ms)" % rep.get("duration"))
rep, e = entry("folder", "folderViewer")
check("3 items" in e.get("details", ""), "folder: 3 items (%s)" % e.get("details"))
rep, e = entry("archive.zip", "fileViewer")
check(e.get("kind") == "file", "archive.zip: the file view (thumbnail %s)" % rep.get("thumbnail"))
rep, e = entry("letter.odt", "fileViewer")
check(e.get("kind") == "file" and rep.get("thumbnail") is True, "letter.odt: KIO's thumbnail of its first page (%s)" % rep.get("thumbnail"))
rep, e = entry("gone.txt", "fileViewer")
check(e.get("kind") == "missing" and "no longer there" in e.get("details", ""), "gone.txt: said to be gone")
check(len(r) == 11, "every file had its turn (%d)" % len(r))
print("quicklook-viewers: %d failed" % failed)
sys.exit(1 if failed else 0)
PY

# The text viewer taken as missing (as without its Qt module): the file view shows the text file's
# KIO thumbnail instead (kio-extras' text thumbnailer).
env HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" XDG_CACHE_HOME="$WORK/home/.cache" \
  XDG_DATA_HOME="$WORK/home/.local/share" QT_QPA_PLATFORM=offscreen LANG=C.UTF-8 QT_FORCE_STDERR_LOGGING=1 \
  dbus-run-session -- timeout 120 "$APP" --test-report "$WORK/fallback.json" --test-unavailable text "$S/notes.txt" \
  >"$WORK/fallback.log" 2>&1 || { echo "the application failed (fallback):"; cat "$WORK/fallback.log"; exit 1; }
python3 - "$WORK/fallback.json" <<'PY' || first=1
import json, sys
e = json.load(open(sys.argv[1]))[0]
ok = e["viewer"] == "fileViewer" and e["ready"] and e["report"].get("thumbnail") is True
print(("PASS " if ok else "FAIL ") + "notes.txt without its viewer: the file view with KIO's thumbnail (%s)" % json.dumps(e)[:300])
PY
exit "$first"
