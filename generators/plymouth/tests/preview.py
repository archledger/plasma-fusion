#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline preview of the Plymouth theme: composes a screen from the built images the way
plasma-fusion.script places them (same arithmetic, re-implemented here), for quick comparison
with the board render before the real test in a VM.

    preview.py THEME_DIR META_JSON OUT.png [--size 1440x900] [--state password|splash|question]
               [--prompt TEXT] [--bullets N] [--answer TEXT] [--message TEXT] [--layout EN]
               [--capslock] [--progress P] [--frame F] [--mode boot|shutdown|reboot|updates|...]
               [--boot FRACTION] [--retry]

--progress is a system update's percentage (-1: none), --boot the boot progress the bar shows
in the splash state, --frame the refresh count (orbit position, fade-in).

Only a preview: the real script runs in plymouth (tests/vmtest.sh on the test device).
"""
import argparse
import json
import math
import os

import numpy as np
from PIL import Image

FPS = 30


def ply_crop(img):
    """What plymouth's Image.Crop does to translucent pixels: premultiply on load (truncating),
    then blend into a transparent buffer, which multiplies the colour by alpha once more."""
    a = np.asarray(img, dtype=np.int64)
    alpha = a[..., 3:4]
    prem = np.where(alpha != 255, (a[..., :3] * alpha) // 255, a[..., :3])
    v = prem * alpha
    prem2 = np.minimum((v + (v >> 8) + 0x80) >> 8, 255)
    straight = np.where(alpha > 0, np.minimum(prem2 * 255 // np.maximum(alpha, 1), 255), 0)
    return Image.fromarray(np.dstack([straight, alpha]).astype(np.uint8), "RGBA")


class Screen:
    def __init__(self, theme, meta, w, h):
        self.theme, self.meta = theme, meta
        self.canvas = Image.new("RGBA", (w, h), (0, 0, 0, 255))
        fit = min(w / 1440, h / 900)
        k = 0
        for i, (sid, s) in enumerate(meta["scales"]):
            if s <= fit + 0.06:
                k = i
        self.sid, self.s = meta["scales"][k]
        self.L = meta["layout"][self.sid]
        self.A = meta["atlas"][self.sid]
        self.fx = math.floor((w - round(1440 * self.s)) / 2)
        self.fy = math.floor((h - round(900 * self.s)) / 2)
        self.w, self.h = w, h
        self._img = {}
        self.sprites = []  # (z, order, image, x, y, opacity)

    def img(self, fn):
        if fn not in self._img:
            self._img[fn] = Image.open(os.path.join(self.theme, fn)).convert("RGBA")
        return self._img[fn]

    def put(self, image, x, y, z, opacity=1.0):
        if opacity < 0.011:
            return
        self.sprites.append((z, len(self.sprites), image, int(math.floor(x)) if isinstance(x, float) else x, y, opacity))

    def flush(self):
        for z, _, image, x, y, o in sorted(self.sprites, key=lambda t: (t[0], t[1])):
            if o < 1:
                a = image.getchannel("A").point(lambda v: round(v * o))
                image = image.copy()
                image.putalpha(a)
            self.canvas.alpha_composite(image, (x, y)) if x >= 0 and y >= 0 else self._paste_clip(image, x, y)
        return self.canvas

    def _paste_clip(self, image, x, y):
        cx, cy = max(0, -x), max(0, -y)
        image = image.crop((cx, cy, image.width, image.height))
        self.canvas.alpha_composite(image, (x + cx, y + cy))

    # Text runs, as pf_keys/pf_fit/pf_text.
    def keys(self, text, charset):
        cs = self.meta["charset"][charset]
        out, unknown = [], False
        for ch in text:
            ch = " " if ch in "\n\t" else ch
            if ch in cs:
                out.append(ch)
                unknown = False
            elif not unknown:
                out.append("?")
                unknown = True
        return out

    def run_width(self, role, keys):
        r = self.meta["roles"][role]
        adv, kern = self.meta["adv"][str(r["weight"])], self.meta["kern"][str(r["weight"])]
        k = r["size"] * self.s / 1000
        w, prev = 0.0, ""
        for key in keys:
            w += (kern.get(prev + key, 0) + adv.get(key, 0)) * k
            prev = key
        return w

    def fit(self, role, keys, maxw, from_start=False):
        if self.run_width(role, keys) <= maxw:
            return keys
        ell = "…" if "…" in self.meta["charset"][self.meta["roles"][role]["charset"]] else "-"
        r = self.meta["roles"][role]
        ew = self.meta["adv"][str(r["weight"])][ell] * r["size"] * self.s / 1000
        if from_start:
            first = 0
            while first < len(keys) and self.run_width(role, keys[first:]) + ew > maxw:
                first += 1
            return [ell] + keys[first:]
        n = len(keys)
        while n > 0 and self.run_width(role, keys[:n]) + ew > maxw:
            n -= 1
        while n > 0 and keys[n - 1] == " ":
            n -= 1
        return keys[:n] + [ell]

    def text(self, role, text, x, baseline, maxw, centred, from_start=False, opacity=1.0):
        r = self.meta["roles"][role]
        A = self.A[role]
        adv, kern = self.meta["adv"][str(r["weight"])], self.meta["kern"][str(r["weight"])]
        charset = self.meta["charset"][r["charset"]]
        keys = self.fit(role, self.keys(text, r["charset"]), maxw, from_start)
        k = r["size"] * self.s / 1000
        w = self.run_width(role, keys)
        pen = x - w / 2 if centred else x
        atlas = self.img(A["file"])
        prev = ""
        for key in keys:
            pen += kern.get(prev + key, 0) * k
            if key != " ":
                ix = math.floor(pen)
                ph = math.floor((pen - ix) * A["phases"] + 0.5)
                if ph >= A["phases"]:
                    ph, ix = 0, ix + 1
                idx = charset.index(key)
                g = ply_crop(atlas.crop((idx * A["cellw"], ph * A["cellh"], (idx + 1) * A["cellw"], (ph + 1) * A["cellh"])))
                self.put(g, ix - A["ox"], baseline - A["base"], 30, opacity)
            pen += adv.get(key, 0) * k
            prev = key
        return w


def parse_prompt(prompt):
    """As pf_parse_prompt."""
    def trim(t):
        t = t.rstrip(" ")
        if t.endswith(":"):
            t = t[:-1]
        return t.rstrip(" ")
    r = dict(title=None, text=trim(prompt), hint=None, disk=False)
    p = prompt.find(" for disk ")
    if p >= 0:
        r["disk"] = True
        head, name = prompt[:p], trim(prompt[p + 10:])
        if name.endswith(" (verification)"):
            name, r["title"] = name[:-15], "t-verify"
        elif "passphrase or recovery key" in head:
            r["title"] = "t-either"
        elif "recovery key" in head:
            r["title"] = "t-recovery"
        else:
            r["title"] = "t-passphrase"
        mount = desc = None
        q = name.find(") on ")
        if q >= 0:
            mount, name = name[q + 5:], name[:q + 1]
        else:
            q = name.find(" on ")
            if q >= 0 and " (" not in name:
                mount, name = name[q + 4:], name[:q]
        if name.endswith(")"):
            q = name.rfind(" (")
            if q > 0:
                desc = name[:q]
        if desc and " " not in desc and "_" in desc:
            desc = desc.replace("_", " ")
        if desc and mount:
            r["hint"] = f"{desc} · {mount}"
        elif desc:
            r["hint"] = desc
        elif mount:
            r["hint"] = f"Encrypted disk · {mount}"
    elif "token PIN" in prompt or "TPM2 PIN" in prompt:
        r["title"], r["disk"] = "t-pin", True
    elif r["text"] == "":
        r["title"], r["disk"] = "t-passphrase", True
    return r


HEADINGS = {"shutdown": "h-shutdown", "reboot": "h-reboot", "system-upgrade": "h-upgrade",
            "firmware-upgrade": "h-firmware", "system-reset": "h-reset", "updates": "h-updates"}


def heading(mode, update):
    """As pf_heading."""
    if mode in HEADINGS and mode != "updates":
        return HEADINGS[mode]
    if mode == "updates" or update >= 0:
        return "h-updates"
    return "greeting"


def background(S, theme, meta, w, h):
    """As pf_background (single display): scaled to cover, centred; portrait keeps the sun."""
    bg = meta["bg"]
    k = max(w / bg["w"], h / bg["h"])
    bw, bh = math.floor(bg["w"] * k + 0.999), math.floor(bg["h"] * k + 0.999)
    image = S.img(bg["file"])
    if (bw, bh) != (bg["w"], bg["h"]):
        image = image.resize((bw, bh), Image.BILINEAR)
    x = math.floor((w - bw) / 2)
    if h > w:
        x = -math.floor(min(max(bg["sunx"] * k - 0.68 * w, 0), bw - w))
    return image, x, math.floor((h - bh) / 2)


def compose(theme, meta, w, h, state="password", prompt="", bullets=0, answer="", message="",
            layout=None, capslock=False, progress=-1, frame=0, mode="boot", boot=0.62, retry=False):
    S = Screen(theme, meta, w, h)
    L, fx, fy, bottom = S.L, S.fx, S.fy, h
    fade = 1.0
    if frame and frame < 15 and mode in ("boot", "shutdown", "reboot"):
        fade = 1 - (1 - frame / 15) ** 3
    image, bx, by = background(S, theme, meta, w, h)
    S.put(image, bx, by, 1, fade)
    S.put(S.img(L["rings"]["file"]), fx + L["rings"]["x"], fy + L["rings"]["y"], 5, fade)
    S.put(S.img(L["logo"]["file"]), fx + L["logo"]["x"], fy + L["logo"]["y"], 10, fade)
    # Orbit dots, as pf_orbit.
    t = frame / FPS
    O = L["orbit"]
    n = O["phases"]
    for i, angle in enumerate(meta["orbit"]["angles"]):
        D = L[f"dot{i}"]
        a = math.radians(angle + 360 * t / meta["orbit"]["period"])
        x = fx + O["cx"] + O["r"] * math.sin(a) - D["d"] / 2
        y = fy + O["cy"] - O["r"] * math.cos(a) - D["d"] / 2
        ix, iy = math.floor(x), math.floor(y)
        px, py = math.floor((x - ix) * n + 0.5), math.floor((y - iy) * n + 0.5)
        if px >= n:
            px, ix = 0, ix + 1
        if py >= n:
            py, iy = 0, iy + 1
        S.put(S.img(D[f"file{px}{py}"]), ix - D["pad"], iy - D["pad"], 6, fade)
    form = state in ("password", "question")
    lines = L["lines"]
    if not form:
        # The column: heading, bar, status line; the mark bottom left.
        key = heading(mode, progress)
        e = L[key]
        S.put(S.img(e["file"]), fx + e["x"], fy + e["y"], 30, fade)
        value = max(0, min(100, progress)) / 100 if progress >= 0 else (boot if key == "greeting" else -1)
        if value >= 0:
            tr = L["track"]
            S.put(S.img(tr["file"]), fx + tr["x"], fy + tr["y"], 20, fade)
            B = L["bar"]
            end = min(math.floor(B["x0"] + value * B["w"] + 0.5), B["end"])
            if end - B["left"] >= B["minw"]:
                S.put(S.img(L["head"]["file"]), fx + L["head"]["x"], fy + L["head"]["y"], 21, fade)
                bw = end - B["tail"] - L["body"]["x"]
                if bw > 0:
                    body = S.img(L["body"]["file"]).resize((bw, L["body"]["h"]), Image.NEAREST)
                    S.put(body, fx + L["body"]["x"], fy + L["body"]["y"], 21, fade)
                S.put(S.img(L["tail"]["file"]), fx + end - B["tail"], fy + L["tail"]["y"], 21, fade)
        line = ""
        if progress >= 0:
            line = f"{math.floor(progress + 0.5)} %" + (f" · {message}" if message else "")
        elif message:
            line = message
        if line:
            S.text("status", line, fx + lines["cx"], fy + lines["status"], lines["maxw"], True, opacity=fade)
        elif key == "greeting":
            e = L["t-starting"]
            S.put(S.img(e["file"]), fx + e["x"], fy + e["y"], 30, fade)
        if progress >= 0:
            e = L["t-dontoff"]
            S.put(S.img(e["file"]), fx + e["x"], fy + e["y"], 30, fade)
        e = L["mark"]
        S.put(S.img(e["file"]), e["x"], bottom + e["y"], 30, fade)
    else:
        r = parse_prompt(prompt)
        title = r["title"]
        if state == "password":
            S.put(S.img(L["pill"]["file"]), fx + L["pill"]["x"], fy + L["pill"]["y"], 20)
        else:
            S.put(S.img(L["pillq"]["file"]), fx + L["pillq"]["x"], fy + L["pillq"]["y"], 20)
        if not title:
            if r["text"] == "" and state == "question":
                title = "t-answer"
            else:
                S.text("prompt", r["text"], fx + lines["cx"], fy + lines["prompt"], lines["maxw"], True)
        if title:
            e = L[title]
            S.put(S.img(e["file"]), fx + e["x"], fy + e["y"], 30)
        caps = state == "password" and capslock
        if caps:
            e = L["t-capslock"]
            S.put(S.img(e["file"]), fx + e["x"], fy + e["y"], 30)
        elif state == "password" and retry:
            e = L[{"t-recovery": "t-wrong-recovery", "t-pin": "t-wrong-pin"}.get(title, "t-wrong")]
            S.put(S.img(e["file"]), fx + e["x"], fy + e["y"], 30)
        elif r["hint"]:
            S.text("status", r["hint"], fx + lines["cx"], fy + lines["hint"], lines["hintmaxw"], True)
        elif r["disk"]:
            e = L["t-encrypted"]
            S.put(S.img(e["file"]), fx + e["x"], fy + e["y"], 30)
        B = L["bullet"]
        n = min(bullets, B["max"]) if state == "password" else 0
        for i in range(n):
            pen = B["x0"] + i * B["pitch"]
            ix = math.floor(pen)
            ph = math.floor((pen - ix) * B["phases"] + 0.5)
            if ph >= B["phases"]:
                ph, ix = 0, ix + 1
            S.put(S.img(B[f"file{ph}"]), fx + ix + B["x"], fy + B["base"] + B["y"], 30)
        cx = L["caret"]["x0"]
        if n:
            cx = B["x0"] + n * B["pitch"] + L["caret"]["after"]
        if state == "question":
            aw = S.text("prompt", answer, fx + L["answer"]["x0"], fy + L["answer"]["base"], L["answer"]["maxw"], False, True)
            cx = L["answer"]["x0"] + (aw + L["caret"]["gap"] if answer else 0)
        S.put(S.img(L["caret"]["file"]), fx + math.floor(cx + 0.5), fy + L["caret"]["y"], 30)
        e = L["esc"]
        S.put(S.img(e["file"]), e["x"], bottom + e["y"], 30)
        if layout:
            K = L["kbd"]
            keys = S.keys(layout, "chip")
            left = w + K["right"] - S.run_width("chip", keys)
            S.text("chip", layout, left, bottom + K["base"], 200 * S.s, False)
            S.put(S.img(K["file"]), math.floor(left - K["gap"] - K["size"] + 0.5) + K["x"], bottom + K["y"], 30)
        if message:
            S.text("prompt", message, fx + lines["cx"], fy + lines["message"], lines["maxw"], True)
    return S.flush().convert("RGB"), S


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("theme")
    ap.add_argument("meta")
    ap.add_argument("out")
    ap.add_argument("--size", default="1440x900")
    ap.add_argument("--state", default="password")
    ap.add_argument("--prompt", default="Please enter passphrase for disk Internal drive (luks-0b1c):")
    ap.add_argument("--bullets", type=int, default=10)
    ap.add_argument("--answer", default="")
    ap.add_argument("--message", default="")
    ap.add_argument("--layout", default="EN")
    ap.add_argument("--capslock", action="store_true")
    ap.add_argument("--progress", type=float, default=-1)
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--mode", default="boot",
                    choices=["boot", "shutdown", "reboot", "updates", "system-upgrade", "firmware-upgrade",
                             "system-reset"])
    ap.add_argument("--boot", type=float, default=0.62, help="boot progress 0..1 (the board shows 62 %%)")
    ap.add_argument("--retry", action="store_true", help="the prompt is asked again (wrong passphrase)")
    a = ap.parse_args()
    w, h = map(int, a.size.split("x"))
    with open(a.meta, encoding="utf-8") as f:
        meta = json.load(f)
    img, S = compose(a.theme, meta, w, h, a.state, a.prompt, a.bullets, a.answer, a.message, a.layout,
                     a.capslock, a.progress, a.frame, a.mode, a.boot, a.retry)
    img.save(a.out)
    print(f"{a.out}: scale {S.s:.4g} ({S.sid}), frame origin {S.fx},{S.fy}")


if __name__ == "__main__":
    main()
