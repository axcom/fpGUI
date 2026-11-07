{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (c) 2026 See the file AUTHORS.txt, included in this
    distribution, for details about the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Description:
      轻量 JSON 工具（不依赖 fpjson / jsonparser）。

      面向固定 schema 的桥接与配置场景，提供三组能力：

        * 序列化：JsonEscape / JsonQuote / JsonArrayOfStrings /
                  JsonErrorObject
        * 解析：  JsonSkipWhitespace / JsonReadString / JsonReadScalar /
                  JsonSkipValue / JsonValueKind
        * 取值：  JsonFindKeyValue / JsonGetString / JsonGetInt /
                  JsonGetInt64 / JsonGetBool / JsonGetStringArray
        * 扁平化：JsonFlatten —— 对象键用 '.' 连接，数组元素用 '.0'
                  '.1' …，生成 key=value 行（OHOS 启动参数使用）。

      编码约定：
        所有解析/拼接都按原始字节处理（RawByteString + RawAppend*），
        不经过宿主代码页转换，因此 UTF-8 不会被破坏；\uXXXX 解码支持
        UTF-16 代理对。输入的 JSON 数据应为 UTF-8。

      解析器是容错的：遇到畸形的 JSON 时返回 False（并给出出错位置），
      不抛异常，调用方可以决定记录日志还是忽略。

      原分散在 fpg_ohos.pas / fpg_ohos_dispatch.pas /
      fpg_ohos_filepicker.pas / fpg_ohos_filestream.pas /
      fpg_ohos_invoke.pas 中的 JSON 辅助代码已统一到这里。
}

unit fpg_jsonutil;

{$I fpg_defines.inc}

interface

uses
  Classes;

const
  { 递归深度上限（防止畸形载荷导致栈溢出）。 }
  JSON_MAX_DEPTH = 64;

type
  { JSON 值类型（用于 schema 校验等场景）。 }
  TJsonKind = (jkNone, jkNull, jkBoolean, jkNumber, jkString, jkObject, jkArray);

  { 字符串动态数组（与 Classes.TStringDynArray 等价，避免可见性问题）。 }
  TJsonStringArray = array of string;

{ ── 序列化 ─────────────────────────────────────────────────────────── }

{ 转义 JSON 字符串内容（不含首尾引号）。非 ASCII 字节原样保留。 }
function JsonEscape(const S: string): string;

{ 把字符串序列化为带引号的 JSON 字符串。 }
function JsonQuote(const S: string): string;

{ 把字符串数组序列化为 JSON 数组。 }
function JsonArrayOfStrings(const AValues: array of string): string;

{ 桥接错误信封：ok=false + code + error }
function JsonErrorObject(const ACode, AMessage: string): string;

{ ── 词法 ───────────────────────────────────────────────────────────── }

{ 跳过空白。P 为 1 基下标；返回 False 表示已到串尾。 }
function JsonSkipWhitespace(const S: string; var P: Integer): Boolean;

{ 读取字符串字面量（S[P] 必须是开引号）。成功时 P 移到闭引号之后，
  AValue 为解码后的内容（UTF-8 字节原样）。 }
function JsonReadString(const S: string; var P: Integer; out AValue: string): Boolean;

{ 读取 true / false / null / 数字等标量原文。成功时 P 移到 token 之后。 }
function JsonReadScalar(const S: string; var P: Integer; out AValue: string): Boolean;

{ 跳过一个任意 JSON 值（标量/对象/数组），用于容错扫描。 }
function JsonSkipValue(const S: string; var P: Integer): Boolean;

{ 返回 APos 处值的类型（会先跳过空白）。 }
function JsonValueKind(const S: string; APos: Integer): TJsonKind;

{ ── 按键取值 ───────────────────────────────────────────────────────── }

{ 查找首个对象成员 AKey，APos 返回其值的起始下标（已跳过空白）。
  字符串内容整体解码后比较，不会把值里的同名字样误判为键。 }
function JsonFindKeyValue(const S, AKey: string; out APos: Integer): Boolean;

function JsonGetString(const S, AKey: string; out AValue: string): Boolean;
function JsonGetInt64(const S, AKey: string; out AValue: Int64): Boolean;
function JsonGetInt(const S, AKey: string): Integer;
function JsonGetBool(const S, AKey: string; out AValue: Boolean): Boolean;
function JsonGetStringArray(const S, AKey: string): TJsonStringArray;

{ ── 扁平化 ─────────────────────────────────────────────────────────── }

{ 把 JSON 扁平化为 key=value 行追加到 ADest。
  对象键用 '.' 连接，数组元素用 '.0' '.1' …；空对象/空数组不产生行。
  失败时返回 False，AErrorPos 为出错位置（1 基）；输入没有 JSON 结构
  时返回 True 且不产生任何行。 }
function JsonFlatten(const S, APrefix: string; ADest: TStrings;
  out AErrorPos: Integer): Boolean;

implementation

uses
  SysUtils;

{ ═══════════════════════════════════════════════════════════════
  字节写入工具
  FPC 的 AnsiString 在部分编译配置下会对拼接/函数返回值做代码页
  转换，因此 UTF-8 输出全部按原始字节追加，不经过编码转换。
  ═══════════════════════════════════════════════════════════════ }

procedure RawAppendBuf(var S: RawByteString; ABuf: PChar; ACount: Integer);
var
  N: Integer;
begin
  if ACount <= 0 then Exit;
  N := Length(S);
  SetLength(S, N + ACount);
  Move(ABuf^, S[N + 1], ACount);
end;

procedure RawAppendByte(var S: RawByteString; AByte: Byte);
var
  N: Integer;
begin
  N := Length(S);
  SetLength(S, N + 1);
  S[N + 1] := AnsiChar(AByte);
end;

procedure RawAppendText(var S: RawByteString; const AText: RawByteString);
begin
  RawAppendBuf(S, PChar(AText), Length(AText));
end;

procedure RawAppendCodePoint(var S: RawByteString; ACodePoint: Cardinal);
begin
  if ACodePoint < $80 then
    RawAppendByte(S, Byte(ACodePoint))
  else if ACodePoint < $800 then
  begin
    RawAppendByte(S, Byte($C0 or (ACodePoint shr 6)));
    RawAppendByte(S, Byte($80 or (ACodePoint and $3F)));
  end
  else if ACodePoint < $10000 then
  begin
    RawAppendByte(S, Byte($E0 or (ACodePoint shr 12)));
    RawAppendByte(S, Byte($80 or ((ACodePoint shr 6) and $3F)));
    RawAppendByte(S, Byte($80 or (ACodePoint and $3F)));
  end
  else
  begin
    RawAppendByte(S, Byte($F0 or (ACodePoint shr 18)));
    RawAppendByte(S, Byte($80 or ((ACodePoint shr 12) and $3F)));
    RawAppendByte(S, Byte($80 or ((ACodePoint shr 6) and $3F)));
    RawAppendByte(S, Byte($80 or (ACodePoint and $3F)));
  end;
end;

{ JSON 数字词法（宽松：允许前导零，够用即可）。 }
function IsJsonNumberToken(const S: string): Boolean;
var
  I, L: Integer;
  HasDigit: Boolean;
begin
  Result := False;
  L := Length(S);
  if L = 0 then Exit;
  I := 1;
  if S[I] = '-' then Inc(I);
  HasDigit := False;
  while (I <= L) and (S[I] in ['0'..'9']) do
  begin
    Inc(I);
    HasDigit := True;
  end;
  if not HasDigit then Exit;
  if (I <= L) and (S[I] = '.') then
  begin
    Inc(I);
    HasDigit := False;
    while (I <= L) and (S[I] in ['0'..'9']) do
    begin
      Inc(I);
      HasDigit := True;
    end;
    if not HasDigit then Exit;
  end;
  if (I <= L) and (S[I] in ['e', 'E']) then
  begin
    Inc(I);
    if (I <= L) and (S[I] in ['+', '-']) then Inc(I);
    HasDigit := False;
    while (I <= L) and (S[I] in ['0'..'9']) do
    begin
      Inc(I);
      HasDigit := True;
    end;
    if not HasDigit then Exit;
  end;
  Result := I > L;
end;

{ ═══════════════════════════════════════════════════════════════
  序列化
  ═══════════════════════════════════════════════════════════════ }

function JsonEscape(const S: string): string;
var
  I: Integer;
  B: Byte;
  R, Tmp: RawByteString;
begin
  R := '';
  for I := 1 to Length(S) do
  begin
    B := Byte(S[I]);
    case S[I] of
      '"':  RawAppendText(R, '\"');
      '\':  RawAppendText(R, '\\');
      #8:   RawAppendText(R, '\b');
      #9:   RawAppendText(R, '\t');
      #10:  RawAppendText(R, '\n');
      #12:  RawAppendText(R, '\f');
      #13:  RawAppendText(R, '\r');
    else
      if B < 32 then
      begin
        Tmp := LowerCase(IntToHex(B, 4));
        RawAppendText(R, '\u');
        RawAppendText(R, Tmp);
      end
      else
        RawAppendByte(R, B);
    end;
  end;
  Result := R;
end;

function JsonQuote(const S: string): string;
var
  R, Tmp: RawByteString;
begin
  R := '';
  Tmp := JsonEscape(S);
  RawAppendByte(R, Ord('"'));
  RawAppendText(R, Tmp);
  RawAppendByte(R, Ord('"'));
  Result := R;
end;

function JsonArrayOfStrings(const AValues: array of string): string;
var
  I: Integer;
  R, Tmp: RawByteString;
begin
  R := '';
  RawAppendByte(R, Ord('['));
  for I := Low(AValues) to High(AValues) do
  begin
    if I > Low(AValues) then
      RawAppendByte(R, Ord(','));
    Tmp := JsonEscape(AValues[I]);
    RawAppendByte(R, Ord('"'));
    RawAppendText(R, Tmp);
    RawAppendByte(R, Ord('"'));
  end;
  RawAppendByte(R, Ord(']'));
  Result := R;
end;

function JsonErrorObject(const ACode, AMessage: string): string;
var
  R, Tmp: RawByteString;
begin
  R := '';
  RawAppendText(R, '{"ok":false,"code":"');
  Tmp := JsonEscape(ACode);
  RawAppendText(R, Tmp);
  RawAppendText(R, '","error":"');
  Tmp := JsonEscape(AMessage);
  RawAppendText(R, Tmp);
  RawAppendText(R, '"}');
  Result := R;
end;

{ ═══════════════════════════════════════════════════════════════
  词法
  ═══════════════════════════════════════════════════════════════ }

function JsonSkipWhitespace(const S: string; var P: Integer): Boolean;
begin
  while (P <= Length(S)) and (S[P] in [' ', #9, #10, #13]) do
    Inc(P);
  Result := P <= Length(S);
end;

function JsonReadHex4(const S: string; var P: Integer; out AValue: Cardinal): Boolean;
var
  I, D: Integer;
begin
  AValue := 0;
  Result := False;
  for I := 1 to 4 do
  begin
    if P > Length(S) then Exit;
    case S[P] of
      '0'..'9': D := Ord(S[P]) - Ord('0');
      'a'..'f': D := Ord(S[P]) - Ord('a') + 10;
      'A'..'F': D := Ord(S[P]) - Ord('A') + 10;
    else
      Exit;
    end;
    AValue := (AValue shl 4) or Cardinal(D);
    Inc(P);
  end;
  Result := True;
end;

function JsonReadString(const S: string; var P: Integer; out AValue: string): Boolean;
var
  Start: Integer;
  CP, CP2: Cardinal;
  R, Tmp: RawByteString;
begin
  AValue := '';
  Result := False;
  if (P > Length(S)) or (S[P] <> '"') then Exit;
  Inc(P);

  R := '';
  while P <= Length(S) do
  begin
    { 普通字符：整段按字节拷贝（UTF-8 原样） }
    Start := P;
    while (P <= Length(S)) and (S[P] <> '"') and (S[P] <> '\') do
      Inc(P);
    if P > Start then
    begin
      Tmp := Copy(S, Start, P - Start);
      RawAppendText(R, Tmp);
    end;

    if P > Length(S) then Exit;           { 字符串未闭合 }

    if S[P] = '"' then
    begin
      Inc(P);
      AValue := R;
      Exit(True);
    end;

    { 转义序列 }
    Inc(P);
    if P > Length(S) then Exit;
    case S[P] of
      '"': begin RawAppendByte(R, Ord('"'));  Inc(P); end;
      '\': begin RawAppendByte(R, Ord('\'));  Inc(P); end;
      '/': begin RawAppendByte(R, Ord('/'));  Inc(P); end;
      'b': begin RawAppendByte(R, 8);   Inc(P); end;
      'f': begin RawAppendByte(R, 12);  Inc(P); end;
      'n': begin RawAppendByte(R, 10);  Inc(P); end;
      'r': begin RawAppendByte(R, 13);  Inc(P); end;
      't': begin RawAppendByte(R, 9);   Inc(P); end;
      'u':
        begin
          Inc(P);
          if not JsonReadHex4(S, P, CP) then Exit;
          { UTF-16 代理对：\uD800-\uDBFF 后跟 \uDC00-\uDFFF }
          if (CP >= $D800) and (CP <= $DBFF) and
             (P + 1 <= Length(S)) and (S[P] = '\') and (S[P + 1] = 'u') then
          begin
            Inc(P, 2);
            if not JsonReadHex4(S, P, CP2) then Exit;
            if (CP2 < $DC00) or (CP2 > $DFFF) then Exit;
            CP := $10000 + ((CP - $D800) shl 10) + (CP2 - $DC00);
          end;
          RawAppendCodePoint(R, CP);
        end;
    else
      Exit;                               { 非法转义 }
    end;
  end;
end;

function JsonReadScalar(const S: string; var P: Integer; out AValue: string): Boolean;
var
  Start: Integer;
  Tmp: RawByteString;
begin
  AValue := '';
  Result := False;
  Start := P;
  while (P <= Length(S)) and not (S[P] in [#0, ',', '}', ']', ' ', #9, #10, #13]) do
    Inc(P);
  if P = Start then Exit;
  Tmp := Copy(S, Start, P - Start);
  AValue := Tmp;
  Result := (AValue = 'true') or (AValue = 'false') or
            (AValue = 'null') or IsJsonNumberToken(AValue);
end;

function JsonSkipValueAt(const S: string; var P: Integer; ADepth: Integer): Boolean; forward;

function JsonSkipObject(const S: string; var P: Integer; ADepth: Integer): Boolean;
var
  Key: string;
begin
  Result := False;
  if ADepth > JSON_MAX_DEPTH then Exit;
  if (P > Length(S)) or (S[P] <> '{') then Exit;
  Inc(P);
  JsonSkipWhitespace(S, P);
  if (P <= Length(S)) and (S[P] = '}') then
  begin
    Inc(P);
    Exit(True);
  end;
  while True do
  begin
    JsonSkipWhitespace(S, P);
    if not JsonReadString(S, P, Key) then Exit;
    JsonSkipWhitespace(S, P);
    if (P > Length(S)) or (S[P] <> ':') then Exit;
    Inc(P);
    if not JsonSkipValueAt(S, P, ADepth + 1) then Exit;
    JsonSkipWhitespace(S, P);
    if P > Length(S) then Exit;
    case S[P] of
      ',': Inc(P);
      '}': begin Inc(P); Exit(True); end;
    else
      Exit;
    end;
  end;
end;

function JsonSkipArray(const S: string; var P: Integer; ADepth: Integer): Boolean;
begin
  Result := False;
  if ADepth > JSON_MAX_DEPTH then Exit;
  if (P > Length(S)) or (S[P] <> '[') then Exit;
  Inc(P);
  JsonSkipWhitespace(S, P);
  if (P <= Length(S)) and (S[P] = ']') then
  begin
    Inc(P);
    Exit(True);
  end;
  while True do
  begin
    if not JsonSkipValueAt(S, P, ADepth + 1) then Exit;
    JsonSkipWhitespace(S, P);
    if P > Length(S) then Exit;
    case S[P] of
      ',': Inc(P);
      ']': begin Inc(P); Exit(True); end;
    else
      Exit;
    end;
  end;
end;

function JsonSkipValueAt(const S: string; var P: Integer; ADepth: Integer): Boolean;
var
  Dummy: string;
begin
  Result := False;
  if ADepth > JSON_MAX_DEPTH then Exit;
  JsonSkipWhitespace(S, P);
  if P > Length(S) then Exit;
  case S[P] of
    '{': Result := JsonSkipObject(S, P, ADepth);
    '[': Result := JsonSkipArray(S, P, ADepth);
    '"': Result := JsonReadString(S, P, Dummy);
  else
    while (P <= Length(S)) and not (S[P] in [',', '}', ']', ' ', #9, #10, #13]) do
      Inc(P);
    Result := True;
  end;
end;

function JsonSkipValue(const S: string; var P: Integer): Boolean;
begin
  Result := JsonSkipValueAt(S, P, 0);
end;

function JsonValueKind(const S: string; APos: Integer): TJsonKind;
var
  P: Integer;
begin
  Result := jkNone;
  if (APos < 1) or (APos > Length(S)) then Exit;
  P := APos;
  JsonSkipWhitespace(S, P);
  if P > Length(S) then Exit;
  case S[P] of
    '{': Result := jkObject;
    '[': Result := jkArray;
    '"': Result := jkString;
    't', 'f': Result := jkBoolean;
    'n': Result := jkNull;
    '-', '0'..'9': Result := jkNumber;
  end;
end;

{ ═══════════════════════════════════════════════════════════════
  按键取值
  ═══════════════════════════════════════════════════════════════ }

function JsonFindKeyValue(const S, AKey: string; out APos: Integer): Boolean;
var
  P, Q: Integer;
  Key: string;
begin
  Result := False;
  APos := 0;
  P := 1;
  while P <= Length(S) do
  begin
    if S[P] = '"' then
    begin
      if not JsonReadString(S, P, Key) then Exit;
      Q := P;
      JsonSkipWhitespace(S, Q);
      if (Q <= Length(S)) and (S[Q] = ':') and (Key = AKey) then
      begin
        Inc(Q);
        JsonSkipWhitespace(S, Q);
        APos := Q;
        Exit(True);
      end;
    end
    else
      Inc(P);
  end;
end;

function JsonGetString(const S, AKey: string; out AValue: string): Boolean;
var
  P: Integer;
begin
  AValue := '';
  Result := False;
  if not JsonFindKeyValue(S, AKey, P) then Exit;
  if (P > Length(S)) or (S[P] <> '"') then Exit;
  Result := JsonReadString(S, P, AValue);
end;

function JsonGetInt64(const S, AKey: string; out AValue: Int64): Boolean;
var
  P: Integer;
  Token: string;
begin
  AValue := 0;
  Result := False;
  if not JsonFindKeyValue(S, AKey, P) then Exit;
  Token := '';
  if (P <= Length(S)) and (S[P] = '-') then
  begin
    Token := '-';
    Inc(P);
  end;
  while (P <= Length(S)) and (S[P] in ['0'..'9']) do
  begin
    Token := Token + S[P];
    Inc(P);
  end;
  if (Token = '') or (Token = '-') then Exit;
  Result := TryStrToInt64(Token, AValue);
end;

function JsonGetInt(const S, AKey: string): Integer;
var
  V: Int64;
begin
  Result := 0;
  if not JsonGetInt64(S, AKey, V) then Exit;
  if (V < Low(Integer)) or (V > High(Integer)) then Exit;
  Result := Integer(V);
end;

function JsonGetBool(const S, AKey: string; out AValue: Boolean): Boolean;
var
  P: Integer;
begin
  AValue := False;
  Result := False;
  if not JsonFindKeyValue(S, AKey, P) then Exit;
  if (P + 3 <= Length(S)) and (Copy(S, P, 4) = 'true') then
  begin
    AValue := True;
    Result := True;
  end
  else if (P + 4 <= Length(S)) and (Copy(S, P, 5) = 'false') then
  begin
    AValue := False;
    Result := True;
  end;
end;

function JsonGetStringArray(const S, AKey: string): TJsonStringArray;
var
  P, Count: Integer;
  Item: string;
begin
  Result := nil;
  if not JsonFindKeyValue(S, AKey, P) then Exit;
  if (P > Length(S)) or (S[P] <> '[') then Exit;
  Inc(P);
  Count := 0;
  while P <= Length(S) do
  begin
    JsonSkipWhitespace(S, P);
    if P > Length(S) then Break;
    if S[P] = ']' then Break;
    if S[P] = ',' then
    begin
      Inc(P);
      Continue;
    end;
    if S[P] = '"' then
    begin
      if not JsonReadString(S, P, Item) then Break;
      SetLength(Result, Count + 1);
      Result[Count] := Item;
      Inc(Count);
    end
    else if not JsonSkipValue(S, P) then
      Break;
  end;
end;

{ ═══════════════════════════════════════════════════════════════
  扁平化：path=value
  ═══════════════════════════════════════════════════════════════ }

function JsonChildPath(const APath, AKey: string): string;
var
  R, Tmp: RawByteString;
begin
  R := '';
  RawAppendText(R, APath);
  if R <> '' then
    RawAppendByte(R, Ord('.'));
  Tmp := AKey;
  RawAppendText(R, Tmp);
  Result := R;
end;

procedure EmitScalarLine(const APath, AValue: string; ADest: TStrings);
var
  Line, Tmp: RawByteString;
begin
  if APath = '' then Exit;
  { 按字节拼好后整体交给 TStrings；不直接传拼接表达式，避免
    TStrings.Add 按系统代码页转换破坏 UTF-8。 }
  Line := '';
  RawAppendText(Line, APath);
  RawAppendByte(Line, Ord('='));
  Tmp := AValue;
  RawAppendText(Line, Tmp);
  ADest.Add(Line);
end;

function FlattenValue(const S, APath: string; var P: Integer; ADepth: Integer;
  ADest: TStrings): Boolean; forward;

function FlattenObject(const S, APath: string; var P: Integer; ADepth: Integer;
  ADest: TStrings): Boolean;
var
  Key: string;
begin
  Result := False;
  if ADepth > JSON_MAX_DEPTH then Exit;
  if (P > Length(S)) or (S[P] <> '{') then Exit;
  Inc(P);
  JsonSkipWhitespace(S, P);
  if (P <= Length(S)) and (S[P] = '}') then
  begin
    Inc(P);
    Exit(True);
  end;
  while True do
  begin
    JsonSkipWhitespace(S, P);
    if not JsonReadString(S, P, Key) then Exit;
    JsonSkipWhitespace(S, P);
    if (P > Length(S)) or (S[P] <> ':') then Exit;
    Inc(P);
    if not FlattenValue(S, JsonChildPath(APath, Key), P, ADepth + 1, ADest) then Exit;
    JsonSkipWhitespace(S, P);
    if P > Length(S) then Exit;
    case S[P] of
      ',': Inc(P);
      '}': begin Inc(P); Exit(True); end;
    else
      Exit;
    end;
  end;
end;

function FlattenArray(const S, APath: string; var P: Integer; ADepth: Integer;
  ADest: TStrings): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if ADepth > JSON_MAX_DEPTH then Exit;
  if (P > Length(S)) or (S[P] <> '[') then Exit;
  Inc(P);
  JsonSkipWhitespace(S, P);
  if (P <= Length(S)) and (S[P] = ']') then
  begin
    Inc(P);
    Exit(True);
  end;
  Index := 0;
  while True do
  begin
    if not FlattenValue(S, JsonChildPath(APath, IntToStr(Index)), P,
                        ADepth + 1, ADest) then Exit;
    Inc(Index);
    JsonSkipWhitespace(S, P);
    if P > Length(S) then Exit;
    case S[P] of
      ',': Inc(P);
      ']': begin Inc(P); Exit(True); end;
    else
      Exit;
    end;
  end;
end;

function FlattenValue(const S, APath: string; var P: Integer; ADepth: Integer;
  ADest: TStrings): Boolean;
var
  V: string;
begin
  Result := False;
  if ADepth > JSON_MAX_DEPTH then Exit;
  JsonSkipWhitespace(S, P);
  if P > Length(S) then Exit;
  case S[P] of
    '{': Result := FlattenObject(S, APath, P, ADepth, ADest);
    '[': Result := FlattenArray(S, APath, P, ADepth, ADest);
    '"':
      begin
        if not JsonReadString(S, P, V) then Exit;
        EmitScalarLine(APath, V, ADest);
        Result := True;
      end;
  else
    if JsonReadScalar(S, P, V) then
    begin
      EmitScalarLine(APath, V, ADest);
      Result := True;
    end;
  end;
end;

function JsonFlatten(const S, APrefix: string; ADest: TStrings;
  out AErrorPos: Integer): Boolean;
var
  P: Integer;
begin
  Result := False;
  AErrorPos := 0;
  if not Assigned(ADest) then Exit;
  if S = '' then
  begin
    Result := True;
    Exit;
  end;
  P := 1;
  { 容忍 JSON 之前的非 JSON 前缀（如 "want:"），定位首个左花括号或方括号。 }
  while (P <= Length(S)) and (S[P] <> '{') and (S[P] <> '[') do
    Inc(P);
  if P > Length(S) then
  begin
    { 没有 JSON 结构：视为空载荷，不报错（与原实现一致）。 }
    Result := True;
    Exit;
  end;
  if not FlattenValue(S, APrefix, P, 0, ADest) then
  begin
    AErrorPos := P;
    Exit;
  end;
  Result := True;
end;

end.
