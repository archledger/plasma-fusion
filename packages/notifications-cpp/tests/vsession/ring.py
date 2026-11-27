#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
"""The focus ring of a notification banner as a screenshot shows it.

    ring.py IMAGE X Y WIDTH HEIGHT LEFT TOP RIGHT BOTTOM COLOUR

The banner's window is the rectangle X, Y, WIDTH, HEIGHT in the pixels of the image; its content
(the text) is that rectangle inset by the window's padding, LEFT, TOP, RIGHT and BOTTOM. COLOUR is
the theme's focus colour, #rrggbb. The applet reports all of it for a banner it has focused.

Prints "on the frame, none in the content" when the focus colour is on the frame's edge, one pixel
in from each of the four sides, and on no pixel of the content; otherwise what was found instead.

Reads the PNG with the standard library only, so that it runs wherever the scenario does: 8 bits a
channel, RGB or RGBA, not interlaced, as the screenshots are written.
"""

import struct
import sys
import zlib


def read_png(path):
    """The image as (width, height, rows), each row a bytes object of RGB triplets."""
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    width = height = depth = colour = None
    compressed = b""
    position = 8
    while position < len(data):
        (length,) = struct.unpack(">I", data[position : position + 4])
        kind = data[position + 4 : position + 8]
        body = data[position + 8 : position + 8 + length]
        position += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            compressed += body
        elif kind == b"IEND":
            break
    if depth != 8 or colour not in (2, 6) or interlace != 0:
        raise ValueError("an 8-bit RGB or RGBA PNG, not interlaced, was expected")
    channels = 3 if colour == 2 else 4
    stride = width * channels
    raw = zlib.decompress(compressed)
    rows = []
    previous = bytes(stride)
    for y in range(height):
        start = y * (stride + 1)
        filter_type = raw[start]
        line = bytearray(raw[start + 1 : start + 1 + stride])
        if filter_type == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 255
        elif filter_type == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 255
        elif filter_type == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 255
        elif filter_type == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = previous[i]
                c = previous[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    prediction = a
                elif pb <= pc:
                    prediction = b
                else:
                    prediction = c
                line[i] = (line[i] + prediction) & 255
        elif filter_type != 0:
            raise ValueError("unknown PNG filter %d" % filter_type)
        # The next row is unfiltered against the row as it was in the file, alpha included.
        previous = bytes(line)
        if channels == 4:
            line = bytes(line[i] for i in range(stride) if i % 4 != 3)
        rows.append(bytes(line))
    return width, height, rows


def main(argv):
    if len(argv) != 11:
        sys.exit(__doc__.strip().splitlines()[0] if argv else "ring.py")
    path = argv[1]
    x, y, width, height, left, top, right, bottom = (int(value) for value in argv[2:10])
    colour = argv[10]
    try:
        target = tuple(int(colour[i : i + 2], 16) for i in (1, 3, 5))
    except ValueError:
        sys.exit("ring.py: not a colour: %s" % colour)

    image_width, image_height, rows = read_png(path)
    if x < 0 or y < 0 or x + width > image_width or y + height > image_height or width <= 0 or height <= 0:
        print("the banner is not inside the picture")
        return

    def pixel(px, py):
        offset = px * 3
        return rows[py][offset], rows[py][offset + 1], rows[py][offset + 2]

    def is_focus(px, py):
        # A tolerance of a few units a channel: the ring is drawn solid, the picture may be scaled.
        return all(abs(value - wanted) <= 12 for value, wanted in zip(pixel(px, py), target))

    # One pixel in from each side, half way along it: on the frame's edge, never in a corner.
    middle_x, middle_y = x + width // 2, y + height // 2
    on_frame = [is_focus(x + 1, middle_y), is_focus(x + width - 2, middle_y), is_focus(middle_x, y + 1), is_focus(middle_x, y + height - 2)]
    inside = 0
    for py in range(y + top, y + height - bottom):
        row = rows[py]
        for px in range(x + left, x + width - right):
            offset = px * 3
            if all(abs(row[offset + i] - target[i]) <= 12 for i in range(3)):
                inside += 1
    found = sum(on_frame)
    if found == 4 and inside == 0:
        print("on the frame, none in the content")
    else:
        print("focus colour on %d of 4 sides of the frame, on %d pixels of the content" % (found, inside))


if __name__ == "__main__":
    main(sys.argv)
