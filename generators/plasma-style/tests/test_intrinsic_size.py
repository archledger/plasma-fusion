#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""QT_QPA_PLATFORM=offscreen python3 generators/plasma-style/tests/test_intrinsic_size.py"""
import os
from pathlib import Path
import re
import sys
import unittest
from xml.etree import ElementTree as ET

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PySide6.QtCore import QByteArray, QRectF, QSize
from PySide6.QtGui import QGuiApplication, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer

import gen_plasma_style as generator
from svgkit import Doc, Fill, Frame, RGBA, add_element, add_frame

APP = QGuiApplication.instance() or QGuiApplication([])


class IntrinsicSizeTest(unittest.TestCase):
    def test_first_frame_sets_intrinsic_size_not_atlas_extent(self):
        doc = Doc("test")
        add_frame(doc, Frame("first", 6, [Fill(0, RGBA(0, 0, 0, 1))]))
        add_frame(doc, Frame("large", 80, [Fill(0, RGBA(255, 255, 255, 1))]))
        add_element(doc, "large-extra", 1400, 900, lambda x, y: "")
        root = ET.fromstring(doc.render())
        self.assertEqual((float(root.attrib["width"]), float(root.attrib["height"])), (28, 28))
        self.assertGreater(float(root.attrib["viewBox"].split()[2]), 1400)
        self.assertGreater(float(root.attrib["viewBox"].split()[3]), 900)

    def test_non_frame_document_retains_its_natural_size(self):
        doc = Doc("standalone")
        add_element(doc, "art", 80, 40, lambda x, y: "")
        root = ET.fromstring(doc.render())
        self.assertEqual(float(root.attrib["width"]), doc.width)
        self.assertEqual(float(root.attrib["height"]), doc.y + doc.row_h + 12)

    def test_asymmetric_frames_preserve_cells_insets_and_stretch(self):
        cases = [
            (Frame("insets", 6, [Fill(0, RGBA(0, 0, 0, 1))],
                   insets=(1, 2, 3, 4), stretch=11), (29, 27)),
            (Frame("cells", 2, [Fill(0, RGBA(0, 0, 0, 1))],
                   cells=(3, 5, 7, 9), stretch=13), (27, 23)),
        ]
        for frame, expected in cases:
            with self.subTest(frame=frame.prefix):
                doc = Doc(frame.prefix)
                add_frame(doc, frame)
                root = ET.fromstring(doc.render())
                self.assertEqual((float(root.attrib["width"]), float(root.attrib["height"])), expected)

    def assert_named_equivalent(self, data):
        root = ET.fromstring(data)
        width, height = root.attrib["viewBox"].split()[2:]
        reference = re.sub(r'(<svg\b[^>]*\bwidth=")[^"]+("[^>]*\bheight=")[^"]+',
                           lambda m: m[1] + width + m[2] + height, data, count=1)
        small = QSvgRenderer(QByteArray(data.encode()))
        atlas = QSvgRenderer(QByteArray(reference.encode()))
        self.assertTrue(small.isValid() and atlas.isValid())
        self.assertNotEqual(small.defaultSize(), atlas.defaultSize())
        ids = [element.attrib["id"] for element in root.iter() if "id" in element.attrib]
        for ident in ids:
            self.assertEqual(small.boundsOnElement(ident), atlas.boundsOnElement(ident), ident)
            self.assertEqual(small.transformForElement(ident), atlas.transformForElement(ident), ident)
            for size in (48, 160):
                pixels = []
                for renderer in (small, atlas):
                    image = QImage(size, size, QImage.Format.Format_ARGB32_Premultiplied)
                    image.fill(0)
                    painter = QPainter(image)
                    renderer.render(painter, ident, QRectF(0, 0, size, size))
                    painter.end()
                    pixels.append(bytes(image.constBits()))
                self.assertEqual(*pixels, msg=ident)

    def test_panel_named_elements_keep_geometry_and_pixels(self):
        data = generator.panel_background(generator.VARIANTS["dark"], None, generator.DEFAULT_OPTS)
        self.assertEqual(QSvgRenderer(QByteArray(data.encode())).defaultSize(), QSize(28, 28))
        self.assert_named_equivalent(data)

    def test_controls_keep_named_geometry_and_pixels(self):
        for variant in generator.VARIANTS.values():
            for builder in (generator.button, generator.slider, generator.switch):
                with self.subTest(variant=variant["id"], builder=builder.__name__):
                    self.assert_named_equivalent(builder(variant))
            with self.subTest(variant=variant["id"], builder="stylesheet tooltip"):
                self.assert_named_equivalent(generator.tooltip(variant, 1.0, solid=True))


if __name__ == "__main__":
    unittest.main()
