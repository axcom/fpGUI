{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      Shader sources and the full-screen quad used by the OHOS GL presenter.
      Both GLES 3.0 (#version 300 es) and GLES 2.0 (#version 100) variants
      are provided because TfpgOhosGLDisplay falls back to ES2 when an ES3
      config/context is unavailable.
}

unit fpg_ohos_gl_shaders;

{$mode objfpc}{$H+}

interface

type
  TPresentVertex = packed record
    X, Y: Single;
    U, V: Single;
  end;

const
  { Triangle strip: bottom-left, bottom-right, top-left, top-right.
    aUV is 0..1; the shader scales it by uUVMax and optionally flips Y. }
  PRESENT_VERTS: array[0..3] of TPresentVertex = (
    (X: -1.0; Y: -1.0; U: 0.0; V: 0.0),
    (X:  1.0; Y: -1.0; U: 1.0; V: 0.0),
    (X: -1.0; Y:  1.0; U: 0.0; V: 1.0),
    (X:  1.0; Y:  1.0; U: 1.0; V: 1.0)
  );

  PRESENT_VERT_SRC_ES3 =
    '#version 300 es'#10 +
    'layout(location = 0) in vec2 aPos;'#10 +
    'layout(location = 1) in vec2 aUV;'#10 +
    'uniform vec2 uUVMax;'#10 +
    'uniform float uFlipY;'#10 +
    'out vec2 vUV;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    vec2 uv = aUV * uUVMax;'#10 +
    '    if (uFlipY > 0.5)'#10 +
    '        uv.y = uUVMax.y - uv.y;'#10 +
    '    vUV = uv;'#10 +
    '    gl_Position = vec4(aPos, 0.0, 1.0);'#10 +
    '}'#10;

  PRESENT_FRAG_SRC_ES3 =
    '#version 300 es'#10 +
    'precision mediump float;'#10 +
    'in vec2 vUV;'#10 +
    'uniform sampler2D uTex;'#10 +
    'uniform float uSwizzleRB;'#10 +
    'out vec4 oColor;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    vec4 c = texture(uTex, vUV);'#10 +
    '    if (uSwizzleRB > 0.5)'#10 +
    '        c = vec4(c.b, c.g, c.r, c.a);'#10 +
    '    oColor = c;'#10 +
    '}'#10;

  PRESENT_VERT_SRC_ES2 =
    '#version 100'#10 +
    'attribute vec2 aPos;'#10 +
    'attribute vec2 aUV;'#10 +
    'uniform vec2 uUVMax;'#10 +
    'uniform float uFlipY;'#10 +
    'varying vec2 vUV;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    vec2 uv = aUV * uUVMax;'#10 +
    '    if (uFlipY > 0.5)'#10 +
    '        uv.y = uUVMax.y - uv.y;'#10 +
    '    vUV = uv;'#10 +
    '    gl_Position = vec4(aPos, 0.0, 1.0);'#10 +
    '}'#10;

  PRESENT_FRAG_SRC_ES2 =
    '#version 100'#10 +
    'precision mediump float;'#10 +
    'varying vec2 vUV;'#10 +
    'uniform sampler2D uTex;'#10 +
    'uniform float uSwizzleRB;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    vec4 c = texture2D(uTex, vUV);'#10 +
    '    if (uSwizzleRB > 0.5)'#10 +
    '        c = vec4(c.b, c.g, c.r, c.a);'#10 +
    '    gl_FragColor = c;'#10 +
    '}'#10;

  { ── Phase 2 solid / textured primitives ─────────────────────────── }

  SOLID_VERT_SRC_ES3 =
    '#version 300 es'#10 +
    'layout(location = 0) in vec2 aPos;'#10 +
    'layout(location = 1) in vec4 aColor;'#10 +
    'out vec4 vColor;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    gl_Position = vec4(aPos, 0.0, 1.0);'#10 +
    '    vColor = aColor;'#10 +
    '}'#10;

  SOLID_FRAG_SRC_ES3 =
    '#version 300 es'#10 +
    'precision mediump float;'#10 +
    'in vec4 vColor;'#10 +
    'out vec4 oColor;'#10 +
    'void main() { oColor = vColor; }'#10;

  TEX_VERT_SRC_ES3 =
    '#version 300 es'#10 +
    'layout(location = 0) in vec2 aPos;'#10 +
    'layout(location = 1) in vec2 aUV;'#10 +
    'layout(location = 2) in vec4 aColor;'#10 +
    'out vec2 vUV;'#10 +
    'out vec4 vColor;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    gl_Position = vec4(aPos, 0.0, 1.0);'#10 +
    '    vUV = aUV;'#10 +
    '    vColor = aColor;'#10 +
    '}'#10;

  TEX_FRAG_SRC_ES3 =
    '#version 300 es'#10 +
    'precision mediump float;'#10 +
    'in vec2 vUV;'#10 +
    'in vec4 vColor;'#10 +
    'uniform sampler2D uTex;'#10 +
    'uniform float uSwizzleRB;'#10 +
    'uniform float uPremultiply;'#10 +
    'out vec4 oColor;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    vec4 t = texture(uTex, vUV);'#10 +
    '    if (uSwizzleRB > 0.5)'#10 +
    '        t = vec4(t.b, t.g, t.r, t.a);'#10 +
    '    if (uPremultiply > 0.5)'#10 +
    '        t.rgb *= t.a;'#10 +
    '    oColor = t * vColor;'#10 +
    '}'#10;

  SOLID_VERT_SRC_ES2 =
    '#version 100'#10 +
    'attribute vec2 aPos;'#10 +
    'attribute vec4 aColor;'#10 +
    'varying vec4 vColor;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    gl_Position = vec4(aPos, 0.0, 1.0);'#10 +
    '    vColor = aColor;'#10 +
    '}'#10;

  SOLID_FRAG_SRC_ES2 =
    '#version 100'#10 +
    'precision mediump float;'#10 +
    'varying vec4 vColor;'#10 +
    'void main() { gl_FragColor = vColor; }'#10;

  TEX_VERT_SRC_ES2 =
    '#version 100'#10 +
    'attribute vec2 aPos;'#10 +
    'attribute vec2 aUV;'#10 +
    'attribute vec4 aColor;'#10 +
    'varying vec2 vUV;'#10 +
    'varying vec4 vColor;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    gl_Position = vec4(aPos, 0.0, 1.0);'#10 +
    '    vUV = aUV;'#10 +
    '    vColor = aColor;'#10 +
    '}'#10;

  TEX_FRAG_SRC_ES2 =
    '#version 100'#10 +
    'precision mediump float;'#10 +
    'varying vec2 vUV;'#10 +
    'varying vec4 vColor;'#10 +
    'uniform sampler2D uTex;'#10 +
    'uniform float uSwizzleRB;'#10 +
    'uniform float uPremultiply;'#10 +
    'void main()'#10 +
    '{'#10 +
    '    vec4 t = texture2D(uTex, vUV);'#10 +
    '    if (uSwizzleRB > 0.5)'#10 +
    '        t = vec4(t.b, t.g, t.r, t.a);'#10 +
    '    if (uPremultiply > 0.5)'#10 +
    '        t.rgb *= t.a;'#10 +
    '    gl_FragColor = t * vColor;'#10 +
    '}'#10;

type
  TGLDrawVertex = packed record
    X, Y: Single;
    U, V: Single;
    R, G, B, A: Single;
  end;

implementation

end.
