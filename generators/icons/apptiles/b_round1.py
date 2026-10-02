# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Round 1 of the per-app tiles (the first ten apps, approved direction)."""
from apptiles.kit import *  # noqa: F401,F403

ch = chrome_parts(32, 30, 18, 8.2, 150)

NEW = {
    'chrome': dict(label='Google Chrome', base='#f4f5f9', lip='#d5d9e3',
                   g1=ch[0], c1='#e8453c', g2=ch[1], c2='#f7b928', g3=ch[2], c3='#2fa25a',
                   x=[(ci(32, 30, 8.2), '#ffffff'), (ci(32, 30, 6), '#3b82f0')]),
    'firefox': dict(label='Firefox', base='#5a2ca0', lip='#3e1e70',
                    g1=ci(33, 31, 12.5), c1='#8f63e8',
                    g2=ci(32, 31, 18.5) + 'M' + ci(38, 25, 13.5)[1:], c2='#ff8a1f',
                    g3='M44 17.5l3.5-9 2.5 11z' + 'M18 39c3 5 8 8 14 8.5-7 1-13-2-16-6z', c3='#ffc23d'),
    'kate': dict(label='Kate', base='#2b8be6', lip='#1f68b3',
                 g1='M12 41c9-1 17-6 22-14 4-6 9-11 18-12-5 3-8 7-9 12 5 0 8 2 10 5-6-1-11 0-15 3-7 5-16 8-26 6z',
                 c1='#ffffff',
                 g2='M26 30c-2-7-7-12-14-14 9 0 16 4 20 10z', c2='#d6e8fb'),
    'dolphin': dict(label='Dolphin', base='#3f7fe0', lip='#2b5db5',
                    g1='M13 19a4 4 0 0 1 4-4h9l4 4h17a4 4 0 0 1 4 4v19H13z', c1='#bcd4ff',
                    g2=rr(13, 24, 38, 22, 4), c2='#ffffff',
                    g3='M16.5 44.5c3-7 10-11.5 18.5-12.5 4-.4 7.5.3 10.5 1.6l4.5-.4-3.4 2.8c-4.4-.7-9 0-13 2-3.6 1.8-6.5 4.4-8.5 7.4l-1.9-3.4c-2.4 1.5-4.6 2.3-6.7 2.5zM31.5 32.6l3.6-5.6 2.8 5.1zM37 37.2l-1.8 4.6 5.6-4.1z',
                    c3='#3f7fe0'),
    'elisa': dict(label='Elisa', base='#1aa391', lip='#127a6c',
                  g1=rr(10, 13, 44, 34, 5), c1='#1b2031',
                  g2=rr(14, 17, 36, 15, 3.5), c2='#6fdcc8',
                  g3=rr(20, 21, 24, 8, 4) + 'M20 47l3.5-8h17l3.5 8z', c3='#2c3348',
                  x=[(ci(25, 25, 3) + ci(39, 25, 3), '#ffffff'), (ci(25, 25, 1.2) + ci(39, 25, 1.2), '#2c3348')]),
    'gwenview': dict(label='Gwenview', base='#d6457a', lip='#a8325d',
                     g1='M9 30c8-12 38-12 46 0-8 12-38 12-46 0z', c1='#ffffff',
                     g2=ci(32, 30, 9.5), c2='#f8c6d8',
                     g3='M24.5 35.5l5-6.5 3 3.5 3-4 4.5 7z', c3='#d6457a'),
    'systemsettings': dict(label='System Settings', base='#3b4255', lip='#262b38',
                           g1=rr(13, 20, 38, 4.5, 2.25) + rr(13, 35, 38, 4.5, 2.25), c1='#6b7490',
                           g2=rr(13, 20, 24, 4.5, 2.25) + rr(13, 35, 11, 4.5, 2.25), c2='#5b9dff',
                           g3=ci(37, 22.25, 5.5) + ci(24, 37.25, 5.5), c3='#ffffff'),
    'kmail': dict(label='KMail', base='#2f6fdf', lip='#2152ad',
                  g1=rr(19, 10, 26, 24, 3), c1='#bcd4ff',
                  g2=rr(12, 24, 40, 22, 4), c2='#ffffff',
                  s1='M14.5 26.5 32 38l17.5-11.5M27 15l5 4-5 4', sc='#2f6fdf', sw=3),
    'okular': dict(label='Okular', base='#2b6fd6', lip='#1f52a3',
                   g1=rr(17, 10, 30, 40, 3), c1='#ffffff',
                   g2='M35 14c-8 6-10 18-3 31-2-11 0-21 7-29z', c2='#2b6fd6',
                   s1='M14 36a6 4.2 0 1 0 12 0a6 4.2 0 1 0-12 0M33 34a6 4.2 0 1 0 12 0a6 4.2 0 1 0-12 0M26 35.5c2-1.5 5-1.5 7-1M45 33.5l5-2',
                   sc='#1b2031', sw=2.4),
    'marknote': dict(label='Marknote', base='#2f9e6e', lip='#227650',
                     g1=rr(13, 11, 32, 39, 4), c1='#ffffff',
                     s1='M18 22h22M18 29h22M18 36h16', sc='#2f9e6e', sw=2.6,
                     g3='M40 44l11-17 3.5 2.2-11 17-4.5 1.6z', c3='#f2a65a'),
}


