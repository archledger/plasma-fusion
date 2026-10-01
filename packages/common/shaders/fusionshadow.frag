// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// FusionShadow.qml: the soft shadow of a rounded box. The effect item is the box grown by `blur`
// on every side; the alpha is full inside the box and falls off over `blur` px outside it
// (squared, for a soft edge). Compiled to fusionshadow.frag.qsb by tools/build-lib/shared-qml.sh
// when qsb is installed (the compiled file is kept in the repository for builds without it).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;       // premultiplied (ShaderEffect passes colors premultiplied)
    vec2 itemSize;    // the effect item in px
    vec2 halfBox;     // half the shadowed box in px
    float radius;     // its corner radius in px
    float blur;       // falloff width in px
};

void main()
{
    // signed distance from the rounded box (negative inside)
    vec2 p = abs(qt_TexCoord0 * itemSize - 0.5 * itemSize) - halfBox + vec2(radius);
    float d = length(max(p, 0.0)) + min(max(p.x, p.y), 0.0) - radius;
    float a = 1.0 - smoothstep(0.0, max(blur, 0.0001), d);
    fragColor = color * (a * a * qt_Opacity);
}
