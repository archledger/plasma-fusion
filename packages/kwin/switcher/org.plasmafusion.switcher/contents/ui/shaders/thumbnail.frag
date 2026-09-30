// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// The rounded box of a window preview (BACKLOG S3): the preview's layer is drawn through this
// one shader, which cuts the corners. Compiled to thumbnail.frag.qsb by tools/build.d/80-kwin.sh
// when qsb is installed (the compiled file is kept in the repository for builds without it).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;      // corner radius in px
    vec2 boxSize;      // the box in px
};
layout(binding = 1) uniform sampler2D source;

void main()
{
    vec2 p = qt_TexCoord0 * boxSize;
    vec2 q = abs(p - boxSize * 0.5) - (boxSize * 0.5 - vec2(radius));
    float d = length(max(q, 0.0)) - radius;
    fragColor = texture(source, qt_TexCoord0) * clamp(0.5 - d, 0.0, 1.0) * qt_Opacity;
}
