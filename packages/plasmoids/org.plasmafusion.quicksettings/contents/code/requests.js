.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    openRequest, the key other shell parts write to open quick settings (the tablet script's right
    edge, Meta+N, Meta+V): "<mode>:<nonce>[:<output>]" or "<mode> <nonce>". Every quick settings
    widget sees the write; one acts: the widget on the output named, else the one on KWin's active
    output. When neither is known (an old request without an output and a KWin that did not answer
    or named no output), only the leader acts: before 0.5.0 every widget did, so the sheet opened
    on every screen.
*/

// {mode, output} of a request; mode "" when there is none.
function parse(text) {
    const parts = String(text || "").split(/[: ]/);
    return { mode: parts[0], output: parts.length > 2 ? parts.slice(2).join(":") : "" };
}

// Whether the widget on the output `mine` (its name, "" while unknown) acts on a request for
// `output` ("" unknown); `leader` is whether it is the leader (main.qml, Instances).
function acts(output, mine, leader) {
    if (output === "") {
        return leader;
    }
    return mine === "" || output === mine;
}

// What the widget does with a request now: "act", "skip", or "wait". `settled` is whether its own
// output name comes from its bar's screen geometry; until then (a bar just made for a screen, or
// moved) the name is the window's first guess, which can name another screen. Deciding on that
// guess lost a request for the widget's real output, or acted on another screen's, so a request
// that names an output waits for the name, until `final` (the wait is over: the guess decides).
function decide(output, mine, settled, leader, final) {
    if (output !== "" && !settled && !final) {
        return "wait";
    }
    return acts(output, mine, leader) ? "act" : "skip";
}
