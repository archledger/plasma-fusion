# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Per-app tiles: every listed app's own mark, drawn as a Plasma Fusion tile.

The 2026-10-02 redesign: 336 apps (the KDE apps in Fedora 44's catalogue and the installed core
apps, plus 99 common Linux apps), designed per category batch from each app's real icon and
reviewed as one set (style guide and review: docs/parts/icons.md, "Per-app tiles").

  TILES        key -> tile dict (kit.tile_svg draws it)
  APPS         the apps (apps.json): id, name, batch, tile ('<key>', 'board:<key>' or 'round1:<key>'),
               icons (the Icon= names that lead to the app)
  APP_NAMES    tile key -> icon names drawn with that tile
  BOARD_NAMES  board tile key -> icon names of apps that use a board tile as it is
  CONFLICTS    icon names two apps claimed (the first app in apps.json keeps it)
"""
import importlib
import json
import pathlib

from apptiles import kit

_HERE = pathlib.Path(__file__).resolve().parent
_BATCHES = ['b_common_a', 'b_common_b', 'b_common_c', 'b_common_d', 'b_development', 'b_education',
            'b_games_a', 'b_games_b', 'b_graphics_media', 'b_office_network_1', 'b_office_network_2',
            'b_system_utility_1', 'b_system_utility_2']

TILES = {}
ROUND1 = importlib.import_module('apptiles.b_round1').NEW
for _k, _v in ROUND1.items():
    TILES[_k] = _v
for _m in _BATCHES:
    for _k, _v in importlib.import_module('apptiles.' + _m).TILES.items():
        if _k in TILES:
            raise ValueError(f'tile key {_k} defined twice ({_m})')
        TILES[_k] = _v

APPS = json.loads((_HERE / 'apps.json').read_text())
APP_NAMES, BOARD_NAMES, CONFLICTS = {}, {}, []
_owner = {}
for _a in APPS:
    _t = _a['tile']
    if _t.startswith('board:'):
        _dest, _key = BOARD_NAMES, _t[6:]
        if _key not in kit.BOARD:
            raise ValueError(f"{_a['id']}: unknown board tile {_key}")
    else:
        _dest, _key = APP_NAMES, _t[7:] if _t.startswith('round1:') else _t
        if _key not in TILES:
            raise ValueError(f"{_a['id']}: unknown tile {_key}")
    for _n in _a['icons']:
        if _n in _owner and _owner[_n] != (_dest is BOARD_NAMES, _key):
            CONFLICTS.append((_n, _owner[_n], _key))
            continue
        _owner[_n] = (_dest is BOARD_NAMES, _key)
        if _n not in _dest.setdefault(_key, []):
            _dest[_key].append(_n)


def tile_svg(key):
    return kit.tile_svg(TILES[key])
