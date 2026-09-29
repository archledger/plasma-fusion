#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Maintainer tool: derive the file-type icon table (mimetable.json) from shared-mime-info.

For every MIME type installed on this machine it records the icon names Plasma and GTK ask for
(the type name with '/' replaced by '-', or the <icon> element) and picks a category (tag colour
and glyph from FileIcons.dc.html) and a tag label (the main file extension). gen_icons.py reads
the committed table, so the build does not depend on the build host's MIME database.

    python3 generators/icons/make_mimetable.py [/usr/share/mime/packages]
"""
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
NS = '{http://www.freedesktop.org/standards/shared-mime-info}'

GENERIC_CATEGORY = {
    'x-office-document': 'doc', 'x-office-spreadsheet': 'sheet', 'x-office-presentation': 'slides',
    'x-office-drawing': 'image', 'x-office-address-book': 'doc', 'x-office-calendar': 'doc',
    'package-x-generic': 'archive', 'text-x-script': 'code', 'font-x-generic': 'font',
    'image-x-generic': 'image', 'audio-x-generic': 'audio', 'video-x-generic': 'video',
    'application-x-executable': 'exec', 'text-html': 'code', 'media-optical': 'disk',
    'text-x-generic': 'text', 'text-x-generic-template': 'text', 'application-xml': 'code',
    'text-plain': 'text', 'application-x-addon': 'exec', 'video-display': 'generic',
}
DEFAULT_LABEL = {
    'doc': 'DOC', 'sheet': 'XLS', 'slides': 'PPT', 'pdf': 'PDF', 'image': 'IMG', 'audio': 'AUDIO',
    'video': 'VIDEO', 'archive': 'ARC', 'code': 'CODE', 'text': 'TXT', 'font': 'FONT', 'disk': 'DISK',
    'exec': 'APP', 'generic': 'FILE',
}
# Types whose category or label the rules get wrong or that the boards show explicitly.
OVERRIDES = {
    'application/pdf': ('pdf', 'PDF'),
    'application/postscript': ('pdf', 'PS'),
    'image/x-eps': ('pdf', 'EPS'),
    'application/vnd.ms-xpsdocument': ('pdf', 'XPS'),
    'application/oxps': ('pdf', 'OXPS'),
    'image/vnd.djvu': ('pdf', 'DJVU'),
    'application/epub+zip': ('doc', 'EPUB'),
    'application/x-mobipocket-ebook': ('doc', 'MOBI'),
    'application/x-fictionbook+xml': ('doc', 'FB2'),
    'text/markdown': ('doc', 'MD'),
    'text/csv': ('sheet', 'CSV'),
    'text/tab-separated-values': ('sheet', 'TSV'),
    'text/plain': ('text', 'TXT'),
    'text/x-log': ('text', 'LOG'),
    'application/x-desktop': ('exec', 'APP'),
    'application/x-executable': ('exec', 'BIN'),
    'application/x-pie-executable': ('exec', 'BIN'),
    'application/x-sharedlib': ('exec', 'LIB'),
    'application/x-object': ('exec', 'OBJ'),
    'application/vnd.appimage': ('exec', 'APP'),
    'application/x-iso9660-appimage': ('exec', 'APP'),
    'application/x-msdownload': ('exec', 'EXE'),
    'application/x-ms-dos-executable': ('exec', 'EXE'),
    'application/x-msi': ('exec', 'MSI'),
    'application/vnd.flatpak': ('archive', 'PAK'),
    'application/vnd.flatpak.ref': ('exec', 'REF'),
    'application/vnd.flatpak.repo': ('exec', 'REPO'),
    'application/x-rpm': ('archive', 'RPM'),
    'application/x-source-rpm': ('archive', 'SRPM'),
    'application/vnd.debian.binary-package': ('archive', 'DEB'),
    'application/x-compressed-tar': ('archive', 'TGZ'),
    'application/x-xz-compressed-tar': ('archive', 'TXZ'),
    'application/x-zstd-compressed-tar': ('archive', 'TZST'),
    'application/x-bzip2-compressed-tar': ('archive', 'TBZ'),
    'application/x-bzip-compressed-tar': ('archive', 'TBZ'),
    'application/x-lzma-compressed-tar': ('archive', 'TLZ'),
    'application/x-cd-image': ('disk', 'ISO'),
    'application/vnd.efi.iso': ('disk', 'ISO'),
    'application/vnd.efi.img': ('disk', 'IMG'),
    'application/x-raw-disk-image': ('disk', 'IMG'),
    'application/x-qemu-disk': ('disk', 'QCOW'),
    'application/x-virtualbox-vdi': ('disk', 'VDI'),
    'application/x-virtualbox-vmdk': ('disk', 'VMDK'),
    'application/x-apple-diskimage': ('disk', 'DMG'),
    'application/json': ('code', 'JSON'),
    'application/xml': ('code', 'XML'),
    'application/javascript': ('code', 'JS'),
    'text/javascript': ('code', 'JS'),
    'application/x-shellscript': ('code', 'SH'),
    'application/x-yaml': ('code', 'YAML'),
    'application/yaml': ('code', 'YAML'),
    'application/toml': ('code', 'TOML'),
    'text/html': ('code', 'HTML'),
    'text/css': ('code', 'CSS'),
    'text/calendar': ('doc', 'ICS'),
    'text/vcard': ('doc', 'VCF'),
    'text/x-vcard': ('doc', 'VCF'),
    'message/rfc822': ('text', 'EML'),
    'application/mbox': ('text', 'MBOX'),
    'application/x-bittorrent': ('generic', 'TOR'),
    'application/x-font-ttf': ('font', 'TTF'),
    'application/x-font-otf': ('font', 'OTF'),
    'font/ttf': ('font', 'TTF'),
    'font/otf': ('font', 'OTF'),
    'application/vnd.oasis.opendocument.text': ('doc', 'ODT'),
    'application/vnd.oasis.opendocument.spreadsheet': ('sheet', 'ODS'),
    'application/vnd.oasis.opendocument.presentation': ('slides', 'ODP'),
    'application/vnd.oasis.opendocument.graphics': ('image', 'ODG'),
    'application/msword': ('doc', 'DOC'),
    'application/vnd.ms-excel': ('sheet', 'XLS'),
    'application/vnd.ms-powerpoint': ('slides', 'PPT'),
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': ('doc', 'DOCX'),
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': ('sheet', 'XLSX'),
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': ('slides', 'PPTX'),
    'application/rtf': ('doc', 'RTF'),
    'application/x-trash': ('generic', 'BAK'),
    'application/octet-stream': ('blank', None),
    'application/x-zerosize': ('blank', None),
    'text/x-readme': ('text', 'TXT'),
    'text/x-copying': ('text', 'TXT'),
    'text/x-authors': ('text', 'TXT'),
    'text/x-install': ('text', 'TXT'),
    'text/x-credits': ('text', 'TXT'),
    'text/x-changelog': ('text', 'LOG'),
    'text/x-makefile': ('code', 'MAKE'),
    'text/x-cmake': ('code', 'CMAKE'),
    'application/x-kdenlive': ('video', 'KDEN'),
    'image/svg+xml': ('image', 'SVG'),
    'image/svg+xml-compressed': ('image', 'SVGZ'),
    'image/jpeg': ('image', 'JPG'),
}
# Generic names (QMimeType::genericIconName and legacy names) and their drawings.
GENERIC_NAMES = {
    'x-office-document': ('doc', 'DOC'), 'x-office-spreadsheet': ('sheet', 'XLS'),
    'x-office-presentation': ('slides', 'PPT'), 'x-office-drawing': ('image', 'IMG'),
    'x-office-address-book': ('doc', 'VCF'), 'x-office-calendar': ('doc', 'ICS'),
    'x-office-document-template': ('doc', 'DOT'), 'x-office-spreadsheet-template': ('sheet', 'XLT'),
    'x-office-presentation-template': ('slides', 'POT'), 'x-office-drawing-template': ('image', 'OTG'),
    'text-x-generic': ('text', 'TXT'), 'text-x-generic-template': ('text', 'TXT'),
    'text-x-script': ('code', 'CODE'), 'text-x-source': ('code', 'CODE'),
    'image-x-generic': ('image', 'IMG'), 'audio-x-generic': ('audio', 'AUDIO'),
    'video-x-generic': ('video', 'VIDEO'), 'font-x-generic': ('font', 'FONT'),
    'package-x-generic': ('archive', 'ZIP'), 'application-x-archive': ('archive', 'AR'),
    'application-x-executable': ('exec', 'BIN'), 'application-x-generic': ('blank', None),
    'unknown': ('blank', None), 'application-x-addon': ('exec', 'ADD'),
    'text-plain': ('text', 'TXT'),
}
SKIP_MEDIA = ('inode', 'x-content', 'x-epoc', 'multipart')
# Icon names Breeze draws for types that shared-mime-info on Fedora 44 does not define
# (installed later by applications, or older names still used in code).
EXTRA_NAMES = {
    'application-x-kdenlive': ('video', 'KDEN'), 'application-x-kdenlivetitle': ('video', 'KDEN'),
    'image-x-krita': ('image', 'KRA'), 'image-x-psd': ('image', 'PSD'), 'image-x-win-bmp': ('image', 'BMP'),
    'text-x-rust': ('code', 'RS'), 'text-x-shellscript': ('code', 'SH'), 'text-x-javascript': ('code', 'JS'),
    'text-x-python2': ('code', 'PY'), 'text-x-java-source': ('code', 'JAVA'), 'text-csharp': ('code', 'CS'),
    'text-dockerfile': ('code', 'DOCK'), 'text-x-r': ('code', 'R'), 'text-fortran': ('code', 'F'),
    'text-x-objchdr': ('code', 'H'), 'text-x-plain': ('text', 'TXT'), 'text-wiki': ('text', 'WIKI'),
    'text-vcalendar': ('doc', 'ICS'), 'application-x-iso': ('disk', 'ISO'), 'application-x-k3b': ('disk', 'K3B'),
    'application-x-ar': ('archive', 'AR'), 'application-x-audacity-project': ('audio', 'AUP'),
    'application-vnd.oasis.opendocument.drawing': ('image', 'ODG'), 'application-vnd.scribus': ('doc', 'SLA'),
    'application-x-marble': ('generic', 'KML'), 'application-x-kmymoney': ('sheet', 'KMY'),
    'application-x-labplot2': ('sheet', 'LML'), 'application-x-kplato': ('doc', 'PLAN'),
    'application-msonenote': ('doc', 'ONE'), 'application-msoutlook': ('doc', 'MSG'),
    'application-wps-office.doc': ('doc', 'DOC'), 'application-wps-office.docx': ('doc', 'DOCX'),
    'application-wps-office.xls': ('sheet', 'XLS'), 'application-wps-office.xlsx': ('sheet', 'XLSX'),
    'application-wps-office.ppt': ('slides', 'PPT'), 'application-wps-office.pptx': ('slides', 'PPTX'),
    'video-x-wmv': ('video', 'WMV'), 'application-x-executable-script': ('code', 'SH'),
}


def ancestors(t, types, seen=None):
    seen = seen or set()
    for p in types.get(t, {}).get('sub', []):
        if p not in seen:
            seen.add(p)
            ancestors(p, types, seen)
    return seen


def pick_label(globs):
    exts = []
    for g in globs:
        m = re.fullmatch(r'\*\.([A-Za-z0-9+]+)', g)
        if m:
            exts.append(m.group(1))
    for g in globs:
        m = re.fullmatch(r'\*(?:\.[A-Za-z0-9+]+)+\.([A-Za-z0-9+]+)', g)
        if m:
            exts.append(m.group(1))
    for maxlen in (4, 5):
        for e in exts:
            if len(e) <= maxlen and not e.isdigit():
                return e.upper()
    return None


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else '/usr/share/mime/packages'
    types = {}
    for f in sorted(glob.glob(os.path.join(src, '*.xml'))):
        for mt in ET.parse(f).getroot().findall(NS + 'mime-type'):
            t = mt.get('type')
            d = types.setdefault(t, {'globs': [], 'generic': None, 'icon': None, 'sub': [], 'aliases': []})
            d['globs'] += [g.get('pattern') for g in mt.findall(NS + 'glob')]
            d['aliases'] += [a.get('type') for a in mt.findall(NS + 'alias')]
            d['sub'] += [s.get('type') for s in mt.findall(NS + 'sub-class-of')]
            gi, ic = mt.find(NS + 'generic-icon'), mt.find(NS + 'icon')
            if gi is not None:
                d['generic'] = gi.get('name')
            if ic is not None:
                d['icon'] = ic.get('name')
    table = {}
    aliases = {}
    for t, d in sorted(types.items()):
        media = t.split('/')[0]
        if media in SKIP_MEDIA:
            continue
        name = d['icon'] or t.replace('/', '-')
        anc = ancestors(t, types)
        if t in OVERRIDES:
            cat, label = OVERRIDES[t]
        else:
            cat = None
            if d['generic'] in GENERIC_CATEGORY:
                cat = GENERIC_CATEGORY[d['generic']]
            elif media == 'image':
                cat = 'image'
            elif media == 'audio':
                cat = 'audio'
            elif media == 'video':
                cat = 'video'
            elif media == 'font':
                cat = 'font'
            elif media == 'model':
                cat = 'generic'
            elif media == 'message':
                cat = 'text'
            elif media == 'text':
                cat = 'code' if re.search(r'src|hdr|script|source|python|java|perl|ruby|lua|rust|go$|csharp|php|sql|tcl|qml|kotlin|scala|haskell|lisp|pascal|fortran|makefile|patch|diff|x-c', t) else 'text'
            elif 'application/zip' in anc or 'application/x-archive' in anc or re.search(r'compress|zip|tar|archive|x-7z|rar|lz|zstd|xz|bzip|gzip', t):
                cat = 'archive'
            elif 'text/plain' in anc or 'application/xml' in anc:
                cat = 'code'
            elif 'application/x-executable' in anc or 'application/x-sharedlib' in anc:
                cat = 'exec'
            else:
                cat = 'generic'
            label = pick_label(d['globs']) or DEFAULT_LABEL[cat]
        table[name] = {'type': t, 'kind': cat, 'label': label}
        for a in d['aliases']:
            if a and a not in types and a.split('/')[0] not in SKIP_MEDIA:
                aliases[a.replace('/', '-')] = {'type': t, 'kind': cat, 'label': label}
    for name, v in aliases.items():
        table.setdefault(name, v)
    for name, (cat, label) in list(GENERIC_NAMES.items()) + list(EXTRA_NAMES.items()):
        table.setdefault(name, {'type': None, 'kind': cat, 'label': label})
    out = os.path.join(HERE, 'mimetable.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(table, f, sort_keys=True, indent=0)
        f.write('\n')
    kinds = {}
    for v in table.values():
        kinds[v['kind']] = kinds.get(v['kind'], 0) + 1
    print('wrote', out, len(table), 'names', kinds)


if __name__ == '__main__':
    main()
