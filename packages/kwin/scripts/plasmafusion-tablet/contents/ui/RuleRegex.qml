/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    A window rule's regular expression matched as KWin matches it, by QRegularExpression (PCRE), for
    the tablet policy's reading of the user's rules (Rules.js, docs/parts/kwin-tablet.md "Windows
    opened in tablet posture get their title bar back"). JavaScript's RegExp reads some of PCRE
    otherwise (\A as "A", [[:alpha:]] as a class and a "]", \w beyond ASCII), but a RegExp handed to
    a RegularExpressionValidator becomes a QRegularExpression with its source unchanged and its i
    and m flags as options. Tested by packages/kwin/tests/tablet_regex_test.py (PySide6).
*/
import QtQuick

import "Rules.js" as Rules

Item {
    id: ruleRegex
    visible: false

    RegularExpressionValidator {
        id: pcre
    }
    TextInput {
        id: subject
        visible: false
        readOnly: true
        validator: pcre
    }

    // true or false as KWin's QRegularExpression(pattern).match(text).hasMatch(), or undefined for a
    // pattern Qt's JavaScript cannot read (lookbehind, possessive quantifiers, options other than a
    // leading (?i) or (?m), parentheses that do not pair up on their own). The validator wants the
    // whole text, so the pattern goes between "any text" ([\s\S]*, and a \E for a \Q left open).
    function matches(pattern: string, text: string): var {
        const p = Rules.regexForQt(pattern);
        let re;
        try {
            new RegExp(p.source, p.flags); // the pattern on its own: the wrapping must not balance it
            re = new RegExp("[\\s\\S]*(?:" + p.source + "\\E)[\\s\\S]*", p.flags);
        } catch (e) {
            return undefined;
        }
        pcre.regularExpression = re;
        subject.text = text;
        return subject.acceptableInput;
    }
}
