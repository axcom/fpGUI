{
    This unit is part of the fpGUI Toolkit project.

    Copyright (c) 2026 by Graeme Geldenhuys.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    Description:
      HarmonyOS native_drawing API Pascal bindings.
      Translated from native_drawing C headers.
      Extended with font metrics, blend modes, and text measurement support.
}

unit fpg_ohos_drawing;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  CTypes;

const
  LIB_DRAWING = 'libnative_drawing.so';

  { Blend modes - match OH_Drawing_BlendMode enum }
  BLEND_MODE_CLEAR      = 0;
  BLEND_MODE_SRC        = 1;
  BLEND_MODE_DST        = 2;
  BLEND_MODE_SRC_OVER   = 3;
  BLEND_MODE_DST_OVER   = 4;
  BLEND_MODE_SRC_IN     = 5;
  BLEND_MODE_DST_IN     = 6;
  BLEND_MODE_SRC_OUT    = 7;
  BLEND_MODE_DST_OUT    = 8;
  BLEND_MODE_SRC_ATOP   = 9;
  BLEND_MODE_DST_ATOP   = 10;
  BLEND_MODE_XOR        = 11;
  BLEND_MODE_PLUS       = 12;
  BLEND_MODE_MODULATE   = 13;
  BLEND_MODE_SCREEN     = 14;
  BLEND_MODE_OVERLAY    = 15;
  BLEND_MODE_DARKEN     = 16;
  BLEND_MODE_LIGHTEN    = 17;
  BLEND_MODE_COLOR_DODGE = 18;
  BLEND_MODE_COLOR_BURN = 19;
  BLEND_MODE_HARD_LIGHT = 20;
  BLEND_MODE_SOFT_LIGHT = 21;
  BLEND_MODE_DIFFERENCE = 22;
  BLEND_MODE_EXCLUSION  = 23;
  BLEND_MODE_MULTIPLY   = 24;
  BLEND_MODE_HUE        = 25;
  BLEND_MODE_SATURATION = 26;
  BLEND_MODE_COLOR      = 27;
  BLEND_MODE_LUMINOSITY = 28;

type
  { Opaque type declarations }
  POH_Drawing_Canvas = type Pointer;
  POH_Drawing_Bitmap = type Pointer;
  POH_Drawing_Pen = type Pointer;
  POH_Drawing_Brush = type Pointer;
  POH_Drawing_Path = type Pointer;
  POH_Drawing_Rect = type Pointer;
  POH_Drawing_RoundRect = type Pointer;
  POH_Drawing_Region = type Pointer;
  POH_Drawing_Point = type Pointer;
  POH_Drawing_Point2D = type Pointer;
  POH_Drawing_Point3D = type Pointer;
  POH_Drawing_Font = type Pointer;
  POH_Drawing_TextBlob = type Pointer;
  POH_Drawing_Matrix = type Pointer;
  POH_Drawing_Image = type Pointer;
  POH_Drawing_Image_Info = type Pointer;
  POH_Drawing_SamplingOptions = type Pointer;
  POH_Drawing_PixelMap = type Pointer;
  POH_Drawing_Typeface = type Pointer;
  POH_Drawing_FontMgr = type Pointer;
  POH_Drawing_FontStyleSet = type Pointer;
  POH_Drawing_PathEffect = type Pointer;

  TOH_Drawing_ErrorCode = Int32;
  TOH_Drawing_BlendMode = Int32;

  TOH_Drawing_ColorFormat = (
    COLOR_FORMAT_UNKNOWN,
    COLOR_FORMAT_ALPHA_8,
    COLOR_FORMAT_RGB_565,
    COLOR_FORMAT_ARGB_4444,
    COLOR_FORMAT_RGBA_8888,
    COLOR_FORMAT_BGRA_8888
  );

  TOH_Drawing_AlphaFormat = (
    ALPHA_FORMAT_UNKNOWN,
    ALPHA_FORMAT_OPAQUE,
    ALPHA_FORMAT_PREMUL,
    ALPHA_FORMAT_UNPREMUL
  );

  TOH_Drawing_BitmapFormat = record
    colorFormat: TOH_Drawing_ColorFormat;
    alphaFormat: TOH_Drawing_AlphaFormat;
  end;
  POH_Drawing_BitmapFormat = ^TOH_Drawing_BitmapFormat;

  TOH_Drawing_SrcRectConstraint = (
    STRICT_SRC_RECT_CONSTRAINT,
    FAST_SRC_RECT_CONSTRAINT
  );

  TOH_Drawing_PointMode = (
    POINT_MODE_POINTS,
    POINT_MODE_LINES,
    POINT_MODE_POLYGON
  );

  TOH_Drawing_CanvasClipOp = (
    DIFFERENCE,
    INTERSECT
  );

  TOH_Drawing_TextEncoding = (
    TEXT_ENCODING_UTF8,
    TEXT_ENCODING_UTF16,
    TEXT_ENCODING_UTF32,
    TEXT_ENCODING_GLYPH_ID
  );

  { Font metrics structure matching OH_Drawing_Font_Metrics (API 12+) }
  TOH_Drawing_FontMetrics = record
    fFlags: Single;              // bit flags
    fTop: Single;                // maximum extent above baseline
    fAscent: Single;             // recommended distance above baseline (negative, toward top)
    fDescent: Single;            // recommended distance below baseline (positive, toward bottom)
    fBottom: Single;             // maximum extent below baseline
    fLeading: Single;            // recommended interline spacing
    fAvgCharWidth: Single;       // average character width
    fMaxCharWidth: Single;       // maximum character width
    fXMin: Single;               // minimum x bounding box
    fXMax: Single;               // maximum x bounding box
    fXHeight: Single;            // x-height
    fCapHeight: Single;          // cap height
    fUnderlineThickness: Single; // underline thickness
    fUnderlinePosition: Single;  // underline position (negative = above baseline)
    fStrikethroughThickness: Single;
    fStrikethroughPosition: Single;
  end;
  POH_Drawing_FontMetrics = ^TOH_Drawing_FontMetrics;

  { TextBlob bounds rectangle (for text measurement) }
  TOH_Drawing_TextBlobBounds = record
    left, top, right, bottom: Single;
  end;

{ Canvas API }
function OH_Drawing_CanvasCreate: POH_Drawing_Canvas; cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDestroy(canvas: POH_Drawing_Canvas); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasBind(canvas: POH_Drawing_Canvas; bitmap: POH_Drawing_Bitmap); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasAttachPen(canvas: POH_Drawing_Canvas; pen: POH_Drawing_Pen); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDetachPen(canvas: POH_Drawing_Canvas); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasAttachBrush(canvas: POH_Drawing_Canvas; brush: POH_Drawing_Brush); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDetachBrush(canvas: POH_Drawing_Canvas); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasSave(canvas: POH_Drawing_Canvas); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasSaveLayer(canvas: POH_Drawing_Canvas; rect: POH_Drawing_Rect; brush: POH_Drawing_Brush); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasRestore(canvas: POH_Drawing_Canvas); cdecl; external LIB_DRAWING;
function OH_Drawing_CanvasGetSaveCount(canvas: POH_Drawing_Canvas): UInt32; cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasRestoreToCount(canvas: POH_Drawing_Canvas; saveCount: UInt32); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawLine(canvas: POH_Drawing_Canvas; x1, y1, x2, y2: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawPath(canvas: POH_Drawing_Canvas; path: POH_Drawing_Path); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawBackground(canvas: POH_Drawing_Canvas; brush: POH_Drawing_Brush); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawRegion(canvas: POH_Drawing_Canvas; region: POH_Drawing_Region); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawPoint(canvas: POH_Drawing_Canvas; point: POH_Drawing_Point2D); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawPoints(canvas: POH_Drawing_Canvas; mode: TOH_Drawing_PointMode; count: UInt32; points: POH_Drawing_Point2D); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawBitmap(canvas: POH_Drawing_Canvas; bitmap: POH_Drawing_Bitmap; left, top: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawBitmapRect(canvas: POH_Drawing_Canvas; bitmap: POH_Drawing_Bitmap; src, dst: POH_Drawing_Rect; sampling: POH_Drawing_SamplingOptions); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawRect(canvas: POH_Drawing_Canvas; rect: POH_Drawing_Rect); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawCircle(canvas: POH_Drawing_Canvas; point: POH_Drawing_Point; radius: Single); cdecl; external LIB_DRAWING;
function OH_Drawing_CanvasDrawColor(canvas: POH_Drawing_Canvas; color: UInt32; blendMode: TOH_Drawing_BlendMode): TOH_Drawing_ErrorCode; cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawOval(canvas: POH_Drawing_Canvas; rect: POH_Drawing_Rect); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawArc(canvas: POH_Drawing_Canvas; rect: POH_Drawing_Rect; startAngle, sweepAngle: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawRoundRect(canvas: POH_Drawing_Canvas; roundRect: POH_Drawing_RoundRect); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasDrawTextBlob(canvas: POH_Drawing_Canvas; textBlob: POH_Drawing_TextBlob; x, y: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasClipRect(canvas: POH_Drawing_Canvas; rect: POH_Drawing_Rect; clipOp: TOH_Drawing_CanvasClipOp; doAntiAlias: Boolean); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasRotate(canvas: POH_Drawing_Canvas; degrees, px, py: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasTranslate(canvas: POH_Drawing_Canvas; dx, dy: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasScale(canvas: POH_Drawing_Canvas; sx, sy: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasSkew(canvas: POH_Drawing_Canvas; sx, sy: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasClear(canvas: POH_Drawing_Canvas; color: UInt32); cdecl; external LIB_DRAWING;
function OH_Drawing_CanvasGetWidth(canvas: POH_Drawing_Canvas): Int32; cdecl; external LIB_DRAWING;
function OH_Drawing_CanvasGetHeight(canvas: POH_Drawing_Canvas): Int32; cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasSetMatrix(canvas: POH_Drawing_Canvas; matrix: POH_Drawing_Matrix); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasResetMatrix(canvas: POH_Drawing_Canvas); cdecl; external LIB_DRAWING;
procedure OH_Drawing_CanvasConcatMatrix(canvas: POH_Drawing_Canvas; matrix: POH_Drawing_Matrix); cdecl; external LIB_DRAWING;

{ Bitmap API }
function OH_Drawing_BitmapCreate: POH_Drawing_Bitmap; cdecl; external LIB_DRAWING;
procedure OH_Drawing_BitmapDestroy(bitmap: POH_Drawing_Bitmap); cdecl; external LIB_DRAWING;
procedure OH_Drawing_BitmapBuild(bitmap: POH_Drawing_Bitmap; width, height: UInt32; format: POH_Drawing_BitmapFormat); cdecl; external LIB_DRAWING;
function OH_Drawing_BitmapGetPixels(bitmap: POH_Drawing_Bitmap): Pointer; cdecl; external LIB_DRAWING;
function OH_Drawing_BitmapGetWidth(bitmap: POH_Drawing_Bitmap): UInt32; cdecl; external LIB_DRAWING;
function OH_Drawing_BitmapGetHeight(bitmap: POH_Drawing_Bitmap): UInt32; cdecl; external LIB_DRAWING;
function OH_Drawing_BitmapGetRowBytes(bitmap: POH_Drawing_Bitmap): UInt32; cdecl; external LIB_DRAWING;

{ Pen API }
function OH_Drawing_PenCreate: POH_Drawing_Pen; cdecl; external LIB_DRAWING;
procedure OH_Drawing_PenDestroy(pen: POH_Drawing_Pen); cdecl; external LIB_DRAWING;
procedure OH_Drawing_PenSetColor(pen: POH_Drawing_Pen; color: UInt32); cdecl; external LIB_DRAWING;
procedure OH_Drawing_PenSetWidth(pen: POH_Drawing_Pen; width: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_PenSetAntiAlias(pen: POH_Drawing_Pen; aa: Boolean); cdecl; external LIB_DRAWING;
function OH_Drawing_PenGetColor(pen: POH_Drawing_Pen): UInt32; cdecl; external LIB_DRAWING;
function OH_Drawing_PenGetWidth(pen: POH_Drawing_Pen): Single; cdecl; external LIB_DRAWING;

{ Path Effect API (dash etc.) }
function  OH_Drawing_CreateDashPathEffect(intervals: PSingle; count: Int32; phase: Single): POH_Drawing_PathEffect; cdecl; external LIB_DRAWING;
procedure OH_Drawing_PathEffectDestroy(pathEffect: POH_Drawing_PathEffect); cdecl; external LIB_DRAWING;
procedure OH_Drawing_PenSetPathEffect(pen: POH_Drawing_Pen; pathEffect: POH_Drawing_PathEffect); cdecl; external LIB_DRAWING;

{ Brush API }
function OH_Drawing_BrushCreate: POH_Drawing_Brush; cdecl; external LIB_DRAWING;
procedure OH_Drawing_BrushDestroy(brush: POH_Drawing_Brush); cdecl; external LIB_DRAWING;
procedure OH_Drawing_BrushSetColor(brush: POH_Drawing_Brush; color: UInt32); cdecl; external LIB_DRAWING;
function OH_Drawing_BrushGetColor(brush: POH_Drawing_Brush): UInt32; cdecl; external LIB_DRAWING;
procedure OH_Drawing_BrushSetAntiAlias(brush: POH_Drawing_Brush; antiAlias: Boolean); cdecl; external LIB_DRAWING;

{ Path API }
function OH_Drawing_PathCreate: POH_Drawing_Path; cdecl; external LIB_DRAWING;
procedure OH_Drawing_PathDestroy(path: POH_Drawing_Path); cdecl; external LIB_DRAWING;
procedure OH_Drawing_PathMoveTo(path: POH_Drawing_Path; x, y: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_PathLineTo(path: POH_Drawing_Path; x, y: Single); cdecl; external LIB_DRAWING;
procedure OH_Drawing_PathClose(path: POH_Drawing_Path); cdecl; external LIB_DRAWING;

{ Rect API }
function OH_Drawing_RectCreate(left, top, right, bottom: Single): POH_Drawing_Rect; cdecl; external LIB_DRAWING;
procedure OH_Drawing_RectDestroy(rect: POH_Drawing_Rect); cdecl; external LIB_DRAWING;
function OH_Drawing_RectGetWidth(rect: POH_Drawing_Rect): Single; cdecl; external LIB_DRAWING;
function OH_Drawing_RectGetHeight(rect: POH_Drawing_Rect): Single; cdecl; external LIB_DRAWING;

{ Font API }
function OH_Drawing_FontCreate: POH_Drawing_Font; cdecl; external LIB_DRAWING;
procedure OH_Drawing_FontDestroy(font: POH_Drawing_Font); cdecl; external LIB_DRAWING;
procedure OH_Drawing_FontSetTypeface(font: POH_Drawing_Font; typeface: POH_Drawing_Typeface); cdecl; external LIB_DRAWING;
procedure OH_Drawing_FontSetTextSize(font: POH_Drawing_Font; size: Single); cdecl; external LIB_DRAWING;
{ 合成粗体（加粗描边）：系统无独立 Bold 字体文件时兜底 }
procedure OH_Drawing_FontSetFakeBoldText(font: POH_Drawing_Font; isFakeBoldText: Boolean); cdecl; external LIB_DRAWING;
function OH_Drawing_FontGetTextSize(font: POH_Drawing_Font): Single; cdecl; external LIB_DRAWING;
function OH_Drawing_FontGetMetrics(font: POH_Drawing_Font; metrics: POH_Drawing_FontMetrics): Int32; cdecl; external LIB_DRAWING;
function OH_Drawing_FontMeasureText(font: POH_Drawing_Font; text: Pointer; byteLength: QWord;
  encoding: TOH_Drawing_TextEncoding; bounds: POH_Drawing_Rect; textWidth: PSingle): Int32; cdecl; external LIB_DRAWING;

{ TextBlob API }
function OH_Drawing_TextBlobCreateFromText(text: PChar; length: QWord;
  font: POH_Drawing_Font; encoding: TOH_Drawing_TextEncoding): POH_Drawing_TextBlob; cdecl; external LIB_DRAWING;
procedure OH_Drawing_TextBlobDestroy(textBlob: POH_Drawing_TextBlob); cdecl; external LIB_DRAWING;

{ Matrix API }
function OH_Drawing_MatrixCreate: POH_Drawing_Matrix; cdecl; external LIB_DRAWING;
procedure OH_Drawing_MatrixDestroy(matrix: POH_Drawing_Matrix); cdecl; external LIB_DRAWING;

{ Typeface API }
function OH_Drawing_TypefaceCreateFromFile(path: PChar; index: Int32): POH_Drawing_Typeface; cdecl; external LIB_DRAWING;
procedure OH_Drawing_TypefaceDestroy(typeface: POH_Drawing_Typeface); cdecl; external LIB_DRAWING;

{ Text path API - API 18+ }
function OH_Drawing_FontGetTextPath(font: POH_Drawing_Font; text: PChar; byteLength: QWord;
  encoding: TOH_Drawing_TextEncoding; x, y: Single; path: POH_Drawing_Path): Int32; cdecl; external LIB_DRAWING;

{ FontMgr API - API 12+ }
function OH_Drawing_FontMgrCreate: POH_Drawing_FontMgr; cdecl; external LIB_DRAWING;
procedure OH_Drawing_FontMgrDestroy(drawingFontMgr: POH_Drawing_FontMgr); cdecl; external LIB_DRAWING;
function OH_Drawing_FontMgrGetFamilyCount(drawingFontMgr: POH_Drawing_FontMgr): Int32; cdecl; external LIB_DRAWING;function OH_Drawing_FontMgrGetFamilyName(drawingFontMgr: POH_Drawing_FontMgr; index: Int32): PChar; cdecl; external LIB_DRAWING;
procedure OH_Drawing_FontMgrDestroyFamilyName(familyName: PChar); cdecl; external LIB_DRAWING;
function OH_Drawing_FontMgrCreateFontStyleSet(drawingFontMgr: POH_Drawing_FontMgr; index: Int32): POH_Drawing_FontStyleSet; cdecl; external LIB_DRAWING;
procedure OH_Drawing_FontMgrDestroyFontStyleSet(drawingFontStyleSet: POH_Drawing_FontStyleSet); cdecl; external LIB_DRAWING;
function OH_Drawing_FontMgrMatchFamily(drawingFontMgr: POH_Drawing_FontMgr; familyName: PChar): POH_Drawing_FontStyleSet; cdecl; external LIB_DRAWING;
function OH_Drawing_FontStyleSetCount(fontStyleSet: POH_Drawing_FontStyleSet): Int32; cdecl; external LIB_DRAWING;
function OH_Drawing_FontStyleSetCreateTypeface(fontStyleSet: POH_Drawing_FontStyleSet; index: Int32): POH_Drawing_Typeface; cdecl; external LIB_DRAWING;

{ 系统字体配置信息（drawing_text_typography.h，API 12+）：
  fontDirSet（权威字体目录）、fontGenericInfoSet（通用字体集，含默认家族名）、
  fallbackGroupSet（系统 fallback 组）。仅声明所需子集。 }
type
  POH_Drawing_FontConfigInfo = ^TOH_Drawing_FontConfigInfo;
  TOH_Drawing_FontGenericInfo = record
    familyName: PChar;
    aliasInfoSize: QWord;
    adjustInfoSize: QWord;
    aliasInfoSet: Pointer;     { OH_Drawing_FontAliasInfo* }
    adjustInfoSet: Pointer;    { OH_Drawing_FontAdjustInfo* }
  end;
  POH_Drawing_FontGenericInfo = ^TOH_Drawing_FontGenericInfo;
  TOH_Drawing_FontConfigInfo = record
    fontDirSize: QWord;
    fontGenericInfoSize: QWord;
    fallbackGroupSize: QWord;
    fontDirSet: ^PChar;                    { char** }
    fontGenericInfoSet: POH_Drawing_FontGenericInfo;
    fallbackGroupSet: Pointer;             { OH_Drawing_FontFallbackGroup* }
  end;

function OH_Drawing_GetSystemFontConfigInfo(errorCode: PInteger): POH_Drawing_FontConfigInfo; cdecl; external LIB_DRAWING;
procedure OH_Drawing_DestroySystemFontConfigInfo(info: POH_Drawing_FontConfigInfo); cdecl; external LIB_DRAWING;

{ FontStyle 结构与字体匹配 API（字符 fallback 用，API 12+） }
type
  TOH_Drawing_FontWeight = (
    FONT_WEIGHT_100, FONT_WEIGHT_200, FONT_WEIGHT_300, FONT_WEIGHT_400,
    FONT_WEIGHT_500, FONT_WEIGHT_600, FONT_WEIGHT_700, FONT_WEIGHT_800,
    FONT_WEIGHT_900);
  TOH_Drawing_FontWidth = (
    FONT_WIDTH_ULTRA_CONDENSED = 1,
    FONT_WIDTH_EXTRA_CONDENSED = 2,
    FONT_WIDTH_CONDENSED = 3,
    FONT_WIDTH_SEMI_CONDENSED = 4,
    FONT_WIDTH_NORMAL = 5,
    FONT_WIDTH_SEMI_EXPANDED = 6,
    FONT_WIDTH_EXPANDED = 7,
    FONT_WIDTH_EXTRA_EXPANDED = 8,
    FONT_WIDTH_ULTRA_EXPANDED = 9);
  TOH_Drawing_FontStyle = (
    FONT_STYLE_NORMAL, FONT_STYLE_ITALIC, FONT_STYLE_OBLIQUE);
  TOH_Drawing_FontStyleStruct = record
    weight: TOH_Drawing_FontWeight;
    width: TOH_Drawing_FontWidth;
    slant: TOH_Drawing_FontStyle;
  end;

function OH_Drawing_FontMgrMatchFamilyStyle(fontMgr: POH_Drawing_FontMgr;
  familyName: PChar; fontStyle: TOH_Drawing_FontStyleStruct): POH_Drawing_Typeface;
  cdecl; external LIB_DRAWING;
function OH_Drawing_FontMgrMatchFamilyStyleCharacter(fontMgr: POH_Drawing_FontMgr;
  familyName: PChar; fontStyle: TOH_Drawing_FontStyleStruct;
  bcp47: PChar; bcp47Count: Int32; character: Int32): POH_Drawing_Typeface;
  cdecl; external LIB_DRAWING;
function OH_Drawing_FontStyleSetGetStyle(fontStyleSet: POH_Drawing_FontStyleSet;
  index: Int32; styleName: PPChar): TOH_Drawing_FontStyleStruct;
  cdecl; external LIB_DRAWING;
function OH_Drawing_FontStyleSetMatchStyle(fontStyleSet: POH_Drawing_FontStyleSet;
  fontStyle: TOH_Drawing_FontStyleStruct): POH_Drawing_Typeface;
  cdecl; external LIB_DRAWING;

implementation

end.
