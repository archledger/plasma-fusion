// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The window preview's cards (WindowPreview.qml) as a ListModel kept in step with the windows to
// show: a window that stays keeps its row, and so its card and the card's screencast stream; only
// the roles that changed (a title, the active window) are set. Windows that come, go or move are
// inserted, removed or moved one by one. Replacing the whole list on every task-model change
// recreated every card and restarted every live thumbnail. Tests: tests/previews.test.js.
.pragma library

var ROLES = ["child", "title", "winId", "active", "minimized"];

// model: a ListModel (count, get, setProperty, insert, move, remove); wanted:
// [{child, title, winId, active, minimized}] in card order. Windows are told apart by winId.
function syncCards(model, wanted) {
    for (var i = 0; i < wanted.length; ++i) {
        var w = wanted[i];
        var at = -1;
        for (var j = i; j < model.count; ++j) {
            if (model.get(j).winId === w.winId) {
                at = j;
                break;
            }
        }
        if (at < 0) {
            var row = {};
            for (var r = 0; r < ROLES.length; ++r) {
                row[ROLES[r]] = w[ROLES[r]];
            }
            model.insert(i, row);
            continue;
        }
        if (at !== i) {
            model.move(at, i, 1);
        }
        var have = model.get(i);
        for (var k = 0; k < ROLES.length; ++k) {
            if (have[ROLES[k]] !== w[ROLES[k]]) {
                model.setProperty(i, ROLES[k], w[ROLES[k]]);
            }
        }
    }
    if (model.count > wanted.length) {
        model.remove(wanted.length, model.count - wanted.length);
    }
}
