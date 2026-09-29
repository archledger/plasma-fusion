# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Xcursor file writer and reader (standard library only).

File layout (libXcursor, xcursorgen): a 16-byte header ("Xcur", header size 16, version
0x00010000, number of TOC entries), the table of contents (type, subtype = nominal size, file
position; 12 bytes each), then one chunk per image: a 36-byte chunk header (header size 36,
type 0xfffd0002, nominal size, version 1, width, height, xhot, yhot, delay in ms) followed by
width*height little-endian CARD32 pixels in premultiplied ARGB. Frames of an animated cursor are
consecutive images with the same nominal size.
"""
import struct

MAGIC = b'Xcur'
FILE_HEADER = 16
FILE_VERSION = 0x00010000
IMAGE_TYPE = 0xfffd0002
IMAGE_HEADER = 36
IMAGE_VERSION = 1
MAX_DIM = 0x7fff


class Image:
    __slots__ = ('size', 'width', 'height', 'xhot', 'yhot', 'delay', 'pixels')

    def __init__(self, size, width, height, xhot, yhot, delay, pixels):
        self.size, self.width, self.height = size, width, height
        self.xhot, self.yhot, self.delay, self.pixels = xhot, yhot, delay, pixels


def encode(images):
    """Serialise a list of Image objects (grouped by nominal size, frames in order)."""
    for im in images:
        if not (0 < im.width <= MAX_DIM and 0 < im.height <= MAX_DIM):
            raise ValueError(f'bad image size {im.width}x{im.height}')
        if not (0 <= im.xhot < im.width and 0 <= im.yhot < im.height):
            raise ValueError(f'hotspot {im.xhot},{im.yhot} outside {im.width}x{im.height}')
        if len(im.pixels) != im.width * im.height * 4:
            raise ValueError('pixel buffer does not match the image size')
    out = [struct.pack('<4sIII', MAGIC, FILE_HEADER, FILE_VERSION, len(images))]
    pos = FILE_HEADER + 12 * len(images)
    for im in images:
        out.append(struct.pack('<III', IMAGE_TYPE, im.size, pos))
        pos += IMAGE_HEADER + len(im.pixels)
    for im in images:
        out.append(struct.pack('<9I', IMAGE_HEADER, IMAGE_TYPE, im.size, IMAGE_VERSION,
                               im.width, im.height, im.xhot, im.yhot, im.delay))
        out.append(im.pixels)
    return b''.join(out)


def decode(data):
    """Parse an Xcursor file into Image objects; raises ValueError on any inconsistency."""
    if len(data) < FILE_HEADER:
        raise ValueError('short file')
    magic, header, version, ntoc = struct.unpack_from('<4sIII', data, 0)
    if magic != MAGIC or header < FILE_HEADER:
        raise ValueError('not an Xcursor file')
    if header + 12 * ntoc > len(data):
        raise ValueError('table of contents runs past the end of the file')
    images = []
    for i in range(ntoc):
        typ, subtype, pos = struct.unpack_from('<III', data, header + 12 * i)
        if typ != IMAGE_TYPE:
            continue
        if pos + IMAGE_HEADER > len(data):
            raise ValueError('image chunk outside the file')
        hsize, ctype, size, cver, w, h, xh, yh, delay = struct.unpack_from('<9I', data, pos)
        if hsize != IMAGE_HEADER or ctype != IMAGE_TYPE or size != subtype or cver != IMAGE_VERSION:
            raise ValueError(f'chunk header mismatch at {pos}')
        if not (0 < w <= MAX_DIM and 0 < h <= MAX_DIM) or xh >= w or yh >= h:
            raise ValueError(f'bad geometry at {pos}')
        start = pos + hsize
        end = start + w * h * 4
        if end > len(data):
            raise ValueError('pixels run past the end of the file')
        images.append(Image(size, w, h, xh, yh, delay, data[start:end]))
    if not images:
        raise ValueError('no images')
    return images


def nominal_sizes(images):
    return sorted({im.size for im in images})
