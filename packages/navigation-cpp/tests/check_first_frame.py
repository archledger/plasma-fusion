# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check each initial native view and its first composed non-owner output."""
import json
import math
from pathlib import Path
import re
import sys

from PIL import Image


class CaptureError(AssertionError):
    """The capture cannot support a product-behavior verdict."""


def validate_captures(directory):
    before = json.loads((directory / 'before.json').read_text())
    owner = json.loads((directory / 'target.json').read_text())['output']
    outputs = {item['name']: item['geo'] for item in before['outputs']}
    events = [json.loads(line) for line in (directory / 'probe.jsonl').read_text().splitlines()]
    assert owner in outputs, 'owner missing from baseline outputs'
    assert all(event['event'] in ('completed', 'first-frame', 'owner-change', 'gesture') for event in events), 'native probe error'
    for event in events:
        assert isinstance(event['owner'], str), 'invalid owner field'
        if event['event'] == 'owner-change':
            assert type(event['closeTimerActive']) is bool and type(event['remainingMs']) is int, 'invalid close timer fields'
            continue
        if event['event'] == 'gesture':
            assert type(event['inProgress']) is bool, 'invalid gesture state'
            assert type(event['squaredVelocity']) in (int, float) and math.isfinite(event['squaredVelocity']), 'invalid velocity'
            assert type(event['flickThreshold']) in (int, float) and math.isfinite(event['flickThreshold']), 'invalid threshold'
            assert event['squaredVelocity'] >= 0 and event['flickThreshold'] > 0, 'invalid gesture magnitude'
            continue
        assert type(event['id']) is int and event['id'] > 0, 'invalid view identity'
        assert isinstance(event['output'], str) and event['output'], 'invalid output field'
        assert event['owner'] in outputs, 'unknown owner field'
        assert type(event['visible']) is bool, 'invalid visibility field'
        assert type(event['opacity']) in (int, float) and math.isfinite(event['opacity']), 'invalid opacity field'
        if event['event'] == 'first-frame':
            assert isinstance(event['image'], str), 'invalid image field'
            assert type(event['width']) is int and event['width'] > 0, 'invalid width field'
            assert type(event['height']) is int and event['height'] > 0, 'invalid height field'
    completed = [event for event in events if event['event'] == 'completed']
    ids = [event['id'] for event in completed]
    assert len(set(ids)) == len(ids), 'duplicate completion identity'
    frames = [event for event in events if event['event'] == 'first-frame']
    assert all(event['id'] in ids for event in frames), 'unregistered first-frame identity'
    assert len({event['id'] for event in frames}) == len(frames), 'duplicate first-frame identity'
    for completion in completed:
        matching = [frame for frame in frames if frame['id'] == completion['id']]
        assert len(matching) == 1, 'missing or duplicate first composed frame'
        frame = matching[0]
        assert frame['output'] == completion['output'] and frame['owner'] == completion['owner'], 'first-frame identity changed'
        image = frame.get('image', '')
        assert image == f"first-{completion['id']}.png", 'missing or invalid first-frame capture'
        with Image.open(directory / image) as captured:
            assert captured.size == (frame['width'], frame['height']), 'wrong native frame dimensions'
            captured.load()
    first = {name: next((event for event in completed if event['output'] == name), None) for name in outputs}
    assert all(first.values()), 'missing initial view completion'
    for name, completion in first.items():
        frame = next(event for event in frames if event['id'] == completion['id'])
        with Image.open(directory / frame['image']) as captured:
            assert captured.size == (outputs[name]['w'], outputs[name]['h']), 'wrong initial frame dimensions'
    left = min(item['x'] for item in outputs.values())
    top = min(item['y'] for item in outputs.values())
    right = max(item['x'] + item['w'] for item in outputs.values())
    bottom = max(item['y'] + item['h'] for item in outputs.values())
    with Image.open(directory / 'before.png') as baseline:
        assert baseline.size == (right - left, bottom - top), 'wrong baseline dimensions'
        for name, geo in outputs.items():
            if name != owner:
                assert geo['w'] > 64 and geo['h'] > 144, 'empty baseline comparison region'
                region = baseline.crop((geo['x'] - left + 32, geo['y'] - top + 48,
                                        geo['x'] - left + geo['w'] - 32, geo['y'] - top + geo['h'] - 96)).convert('RGB')
                assert any(high > 0 for _, high in region.getextrema()), 'black baseline interior'
    return owner, outputs, completed, frames, first, left, top


def check(directory):
    directory = Path(directory)
    try:
        owner, outputs, completed, frames, first, left, top = validate_captures(directory)
    except (AssertionError, OSError, ValueError, TypeError, KeyError) as error:
        raise CaptureError(str(error)) from error
    for completion in completed:
        expected = 1 if completion['output'] == completion['owner'] else 0
        assert completion['opacity'] == expected, 'wrong opacity at completion'
        assert completion['visible'] is True, 'view hidden at completion'
        frame = next(event for event in frames if event['id'] == completion['id'])
        assert frame['opacity'] == expected and frame['visible'] is True, 'wrong first-frame state'
        # A newly added output has no prior desktop image to preserve. Its view state
        # remains checked above; the hotplug scenario separately waits for its desktop.
        if not expected and completion['output'] in outputs:
            with Image.open(directory / frame['image']) as captured:
                interior = captured.crop((32, 48, captured.width - 32, captured.height - 96)).convert('RGB')
                assert any(high > 0 for _, high in interior.getextrema()), 'black non-owner first frame'
    checked = 0
    with Image.open(directory / 'before.png') as baseline:
        for name, completion in first.items():
            expected = 1 if name == owner else 0
            assert completion['owner'] == owner, 'wrong owner at completion'
            assert completion['opacity'] == expected, 'wrong opacity at completion'
            assert completion['visible'] is True, 'view hidden at completion'
            frame = next(event for event in frames if event['id'] == completion['id'])
            assert frame['output'] == name and frame['owner'] == owner, 'first-frame identity changed'
            assert frame['opacity'] == expected and frame['visible'] is True, 'wrong first-frame state'
            image = frame.get('image', '')
            assert re.fullmatch(r'first-\d+\.png', image), 'missing or invalid first-frame capture'
            if name == owner:
                with Image.open(directory / image) as captured:
                    assert captured.size == (outputs[name]['w'], outputs[name]['h']), 'wrong owner frame dimensions'
                    captured.load()
                continue
            geo = outputs[name]
            box = (32, 48, geo['w'] - 32, geo['h'] - 96)
            assert box[2] > box[0] and box[3] > box[1], 'empty comparison region'
            original = baseline.crop((geo['x'] - left + box[0], geo['y'] - top + box[1],
                                      geo['x'] - left + box[2], geo['y'] - top + box[3])).convert('RGB')
            assert any(high > 0 for _, high in original.getextrema()), 'black baseline interior'
            with Image.open(directory / image) as captured:
                assert captured.size == (geo['w'], geo['h']), 'wrong first-frame dimensions'
                actual = captured.crop(box).convert('RGB')
                assert actual.tobytes() == original.tobytes(), f'first frame changed non-owner {name}'
            checked += 1
    return checked


if __name__ == '__main__':
    try:
        print(f'PASS: {check(sys.argv[1])} non-owner first frames unchanged')
    except CaptureError as error:
        print(f'CAPTURE ERROR: {error}', file=sys.stderr)
        raise SystemExit(2)
    except AssertionError as error:
        print(f'FAIL: {error}', file=sys.stderr)
        raise SystemExit(1)
