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
      OHOS 命令行参数实现（自 fpg_ohos.pas 拆出的独立副本）。

      本单元包含 TfpgOhosCmdLineParams 的完整实现，由 fpg_ohos.pas
      的 implementation uses 引用（替代其中原有的同名类实现）。
      与原实现的差异只有 ParsePayload：改为调用 fpg_jsonutil 的
      递归下降解析器（JsonFlatten），因此：

        * 支持字符串 / 数字 / true / false / null；
        * 支持任意层嵌套对象，数组扁平化为 key.0 / key.1 ...；
        * 完整解码 JSON 转义（\" \\ \/ \b \f \n \r \t \uXXXX，
          \uXXXX 含 UTF-16 代理对），按 UTF-8 写入；
        * 数字按原文保存，不做整型/浮点转换（避免 64 位值丢精度）；
        * 格式错误时只记录日志并停止，不抛异常（启动期不崩溃）。

      日志：本单元不引用 fpg_ohos，输出通过 OhosCmdLineParamsLogHook
      回调注入（签名与 fpGUI_Hilog 一致：level = LOG_INFO(4) 等）。

      其余方法（GetOptionValue / CheckOptions / ParamStr ...）与原实现
      逐行一致，行为保持不变。
}

unit fpg_ohos_CmdLineParams;

{$I fpg_defines.inc}

interface

uses
  Classes,
  SysUtils,
  fpg_cmdlineparams;

const
  { 与 fpg_ohos.pas 的 LOG_* 取值保持一致，避免引用该单元。 }
  OHOS_CMDLINE_LOG_INFO  = 4;
  OHOS_CMDLINE_LOG_ERROR = 6;

type
  { 可选日志回调。默认 nil = 不输出。
    宿主可在初始化时指向 fpGUI_Hilog，恢复与原实现相同的日志。 }
  TfpgOhosCmdLineParamsLogProc = procedure(ALevel: Integer; const AMsg: string);

var
  OhosCmdLineParamsLogHook: TfpgOhosCmdLineParamsLogProc = nil;

{ TfpgOhosCmdLineParams — OHOS command-line params from C++ }
{ Parses space-separated args string: "-b debug key=value" }
type
  TfpgOhosCmdLineParams = class(TInterfacedObject, ICmdLineParams)
  private
    FItems: TStringList;
    FOptionChar: char;
    FCaseSensitiveOptions: Boolean;
    { JSON payload 解析 }
    procedure   ParsePayload(const APayload: string);
    { ICmdLineParams }
    function    GetOptionAtIndex(AIndex: Integer; IsLong: Boolean): string;
    function    FindOptionIndex(const S: string; var LongOpt: Boolean; StartAt: Integer = -1): Integer;
    function    GetOptionValue(const S: string): string;
    function    GetOptionValue(const C: char; const S: string): string;
    function    GetOptionValues(const C: Char; const S: string): TStringArray;
    function    HasOption(const S: string): Boolean;
    function    HasOption(const C: char; const S: string): Boolean;
    function    CheckOptions(const ShortOptions: string; const Longopts: TStrings; Opts, NonOpts: TStrings; AllErrors: Boolean = False): string;
    function    CheckOptions(const ShortOptions: string; const Longopts: array of string; Opts, NonOpts: TStrings; AllErrors: Boolean = False): string;
    function    CheckOptions(const ShortOptions: string; const LongOpts: TStrings; AllErrors: Boolean = False): string;
    function    CheckOptions(const ShortOptions: string; const LongOpts: array of string; AllErrors: Boolean = False): string;
    function    CheckOptions(const ShortOptions: string; const LongOpts: string; AllErrors: Boolean = False): string;
    function    GetNonOptions(const ShortOptions: string; const LongOpts: Array of string): TStringArray;
    procedure   GetNonOptions(const ShortOptions: string; const LongOpts: Array of string; NonOptions: TStrings);
    function    GetCaseSensitiveOptions: Boolean;
    function    GetOptionChar: char;
    procedure   SetCaseSensitiveOptions(AValue: Boolean);
    procedure   SetOptionChar(AValue: char);
    function    ParamStr(AIndex: integer): string;
    function    GetParams(AIndex: integer): string;
    function    GetParamCount: integer;
  public
    constructor Create(const AAppArgs, APayload: string);
    destructor  Destroy; override;
    property    OptionChar: char read GetOptionChar write SetOptionChar;
    property    CaseSensitiveOptions: Boolean read GetCaseSensitiveOptions write SetCaseSensitiveOptions;
    property    Params[Index: integer]: string read GetParams;
    property    ParamCount: integer read GetParamCount;
  end;

implementation

uses
  fpg_constants, fpg_jsonutil;

{ ═══════════════════════════════════════════════════════════════
  单元级辅助
  ═══════════════════════════════════════════════════════════════ }

procedure OhosCmdLineLog(ALevel: Integer; const AMsg: string);
begin
  if Assigned(OhosCmdLineParamsLogHook) then
    OhosCmdLineParamsLogHook(ALevel, AMsg);
end;

{ ═══════════════════════════════════════════════════════════════
  JSON payload 解析：递归下降解析器已统一到 fpg_jsonutil。
  路径规则：对象 key 用 '.' 连接；数组元素用 '.0' '.1' ...
  保留顶层前缀（如 parameters.moduleName=...），与原实现一致。
  ═══════════════════════════════════════════════════════════════ }

procedure TfpgOhosCmdLineParams.ParsePayload(const APayload: string);
var
  ErrPos: Integer;
begin
  if APayload = '' then Exit;
  if not JsonFlatten(APayload, '', FItems, ErrPos) then
    OhosCmdLineLog(OHOS_CMDLINE_LOG_ERROR,
      Format('ParsePayload: invalid JSON at offset %d', [ErrPos]))
  else
    OhosCmdLineLog(OHOS_CMDLINE_LOG_INFO,
      Format('ParsePayload: %d item(s)', [FItems.Count]));
end;

constructor TfpgOhosCmdLineParams.Create(const AAppArgs, APayload: string);
var tmp: TStringList;
    i: Integer;
begin
  inherited Create;
  FItems := TStringList.Create;
  FOptionChar := '-';
  FCaseSensitiveOptions := False;
  // 1. 解析 OhosArgs → 按空格分割追加到 FItems
  if Trim(AAppArgs) <> '' then
  begin
    tmp := TStringList.Create;
    try
      tmp.Delimiter := ' ';
      tmp.StrictDelimiter := True;
      tmp.DelimitedText := Trim(AAppArgs);
      for i := 0 to tmp.Count - 1 do
        if Trim(tmp[i]) <> '' then
          FItems.Add(Trim(tmp[i]));
    finally
      tmp.Free;
    end;
  end;
  // 2. 解析 gLaunchParams → JSON 字段追加为 key=value
  ParsePayload(APayload);
  if APayload <> '' then
    OhosCmdLineLog(OHOS_CMDLINE_LOG_INFO, APayload);
  OhosCmdLineLog(OHOS_CMDLINE_LOG_INFO, FItems.Text);
end;

destructor TfpgOhosCmdLineParams.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TfpgOhosCmdLineParams.GetOptionAtIndex(AIndex: Integer; IsLong: Boolean): string;
var
  P: Integer;
  O: String;
begin
  Result := '';
  If (AIndex < 0) then
    Exit;
  If IsLong then
  begin // Long options have form --option=value
    O := FItems[AIndex];
    P := Pos('=', O);
    if (P = 0) then
      P := Length(O);
    Delete(O, 1, P);
    Result := O;
  end
  else
  begin // short options have form '-o value'
    if (AIndex<ParamCount-1) then
      if (Copy(FItems[AIndex+1], 1, 1) <> '-') then
        Result := FItems[AIndex+1];
  end;
end;

function TfpgOhosCmdLineParams.FindOptionIndex(const S: string; var LongOpt: Boolean; StartAt: Integer): Integer;
var
  SO, O: string;
  I, P: integer;
begin
  if not CaseSensitiveOptions then
    SO := UpperCase(S)
  else
    SO := S;
  Result := -1;
  I := StartAt;
  if (I = -1) then
    I := ParamCount-1;
  while (Result = -1) and (I >= 0) do
  begin
    O := FItems[i];
    // - must be seen as an option value
    if (Length(O) > 1) and (O[1] = FOptionChar) then
    begin
      Delete(O, 1, 1);
      LongOpt := (Length(O) > 0) and (O[1] = FOptionChar);
      if LongOpt then
        Delete(O, 1, 1);
      P := Pos('=', O);
      if (P <> 0) then
        O := Copy(O, 1, P - 1);
      if not CaseSensitiveOptions then
        O      := UpperCase(O);
      if (O = SO) then
        Result := i;
    end;
    Dec(i);
  end;
end;

function TfpgOhosCmdLineParams.GetOptionValue(const S: string): string;
begin
  Result := GetoptionValue(#255, S);
end;

function TfpgOhosCmdLineParams.GetOptionValue(const C: char; const S: string): string;
var
  B: Boolean;
  I, P: integer;
  O: string;
begin
  Result := '';
  B := False;
  I      := FindOptionIndex(C, B);
  if (I = -1) then
    I := FindoptionIndex(S, B);
  if (I <> -1) then
    if B then
    begin
      // Long options have form --option=value
      O := FItems[I];
      P := Pos('=', O);
      if (P = 0) then
        P := Length(O);
      Delete(O, 1, P);
      Result := O;
    end
    else if (I < ParamCount-1) then
    begin
      if (Copy(FItems[I+1], 1, 1) <> '-') then
        Result := FItems[I+1]; // short options have form '-o value'
    end;
end;

function TfpgOhosCmdLineParams.GetOptionValues(const C: Char; const S: string): TStringArray;
var
  I, Cnt: Integer;
  B: Boolean;
begin
  SetLength(Result, ParamCount);
  Cnt := 0;
  Repeat
    I := FindOptionIndex(C, B, I);
    If I<>-1 then
    begin
      Inc(Cnt);
      Dec(I);
    end;
  Until I = -1;
  Repeat
    I := FindOptionIndex(S, B,I );
    If I <> -1 then
    begin
      Inc(Cnt);
      Dec(I);
    end;
  Until I = -1;
  SetLength(Result, Cnt);
  Cnt := 0;
  I := -1;
  Repeat
    I := FindOptionIndex(C, B, I);
    If (I <> -1) then
    begin
      Result[Cnt] := GetOptionAtIndex(I, False);
      Inc(Cnt);
      Dec(i);
    end;
  Until (I = -1);
  I := -1;
  Repeat
    I := FindOptionIndex(S, B, I);
    If I <> -1 then
    begin
      Result[Cnt] := GetOptionAtIndex(I, True);
      Inc(Cnt);
      Dec(i);
    end;
  Until (I = -1);
end;

function TfpgOhosCmdLineParams.HasOption(const S: string): Boolean;
var
  B: Boolean;
begin
  B := False;
  Result := FindOptionIndex(S, B) <> -1;
end;

function TfpgOhosCmdLineParams.HasOption(const C: char; const S: string): Boolean;
var
  B: Boolean;
begin
  B := False;
  Result := (FindOptionIndex(C, B) <> -1) or (FindOptionIndex(S, B) <> -1);
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const Longopts: TStrings; AllErrors: Boolean): string;
begin
  Result := CheckOptions(ShortOptions, LongOpts, nil, nil, AllErrors);
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const Longopts: TStrings; Opts, NonOpts: TStrings; AllErrors: Boolean): string;
var
  I, J, L, P: integer;
  O, OV, SO: string;
  UsedArg, HaveArg: Boolean;

  function FindLongOpt(S: string): Boolean;
  var
    I: integer;
  begin
    Result := Assigned(LongOpts);
    if not Result then
      Exit;
    if CaseSensitiveOptions then
    begin
      I := LongOpts.Count - 1;
      while (I >= 0) and (LongOpts[i] <> S) do
        Dec(i);
    end
    else
    begin
      S := UpperCase(S);
      I := LongOpts.Count - 1;
      while (I >= 0) and (UpperCase(LongOpts[i]) <> S) do
        Dec(i);
    end;
    Result := (I <> -1);
  end;

  procedure AddToResult(const Msg: string);
  begin
    if (Result <> '') then
      Result := Result + LineEnding;
    Result := Result + Msg;
  end;

begin
  if CaseSensitiveOptions then
    SO := ShortOptions
  else
    SO := LowerCase(ShortOptions);
  Result := '';
  I := 1;
  while (I < ParamCount) and ((Result = '') or AllErrors) do
  begin
    O := FItems[I];
    if (Length(O) = 0) or (O[1] <> FOptionChar) then
    begin
      if Assigned(NonOpts) then
        NonOpts.Add(O);
    end
    else
	  begin
      if (Length(O) < 2) then
        AddToResult(Format(SErrInvalidOption, [i, O]))
      else
      begin
        HaveArg := False;
        OV      := '';
        // Long option ?
        if (O[2] = FOptionChar) then
        begin
          Delete(O, 1, 2);
          J := Pos('=', O);
          if J <> 0 then
          begin
            HaveArg := True;
            OV      := O;
            Delete(OV, 1, J);
            O       := Copy(O, 1, J - 1);
          end;
          // Switch Option
          if FindLongopt(O) then
          begin
            if HaveArg then
              AddToResult(Format(SErrNoOptionAllowed, [I, O]));
          end
          else
          begin // Required argument
            if FindLongOpt(O + ':') then
            begin
              if not HaveArg then
                AddToResult(Format(SErrOptionNeeded, [I, O]));
            end
            else
            begin // Optional Argument.
              if not FindLongOpt(O + '::') then
                AddToResult(Format(SErrInvalidOption, [I, O]));
            end;
          end;
        end
        else // Short Option.
        begin
          HaveArg := (I < ParamCount-1) and (Length(FItems[I + 1]) > 0) and (FItems[I + 1][1] <> FOptionChar);
          UsedArg := False;
          if HaveArg then
            OV := FItems[I + 1];
          if not CaseSensitiveOptions then
            O := LowerCase(O);
          L := Length(O);
          J := 2;
          while ((Result = '') or AllErrors) and (J <= L) do
          begin
            P := Pos(O[J], ShortOptions);
            if (P = 0) or (O[j] = ':') then
              AddToResult(Format(SErrInvalidOption, [I, O[J]]))
            else
            begin
	          if (P < Length(ShortOptions)) and (Shortoptions[P + 1] = ':') then
		        begin
                // Required argument
                if ((P + 1) = Length(ShortOptions)) or (Shortoptions[P + 2] <> ':') then
                  if (J < L) or not haveArg then // Must be last in multi-opt !!
                    AddToResult(Format(SErrOptionNeeded, [I, O[J]]));
                O := O[j]; // O is added to arguments.
                UsedArg := True;
              end;
            end;
            Inc(J);
          end;
          if HaveArg and UsedArg then
          begin
            Inc(I); // Skip argument.
            O := O[Length(O)]; // O is added to arguments !
          end;
        end;
        if HaveArg and ((Result = '') or AllErrors) then
          if Assigned(Opts) then
            Opts.Add(O + '=' + OV);
      end;
    end;
    Inc(I);
  end;
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const Longopts: array of string; Opts, NonOpts: TStrings; AllErrors: Boolean): string;
var
  L: TStringList;
  I: integer;
begin
  L := TStringList.Create;
  try
    for I := 0 to High(LongOpts) do
      L.Add(LongOpts[i]);
    Result := CheckOptions(ShortOptions, L, Opts, NonOpts, AllErrors);
  finally
    L.Free;
  end;
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const LongOpts: array of string; AllErrors: Boolean): string;
var
  L: TStringList;
  I: integer;
begin
  L := TStringList.Create;
  try
    for I := 0 to High(LongOpts) do
      L.Add(LongOpts[i]);
    Result := CheckOptions(ShortOptions, L, AllErrors);
  finally
    L.Free;
  end;
end;

function TfpgOhosCmdLineParams.CheckOptions(const ShortOptions: string; const LongOpts: string; AllErrors: Boolean): string;
const
  cSepChars = ' '#10#13#9;
var
  L: TStringList;
  Len, I, J: integer;
begin
  L := TStringList.Create;
  try
    I := 1;
    Len := Length(LongOpts);
    while I <= Len do
    begin
      while Isdelimiter(cSepChars, LongOpts, I) do
        Inc(I);
      J := I;
      while (J <= Len) and not IsDelimiter(cSepChars, LongOpts, J) do
        Inc(J);
      if (I <= J) then
        L.Add(Copy(LongOpts, I, (J - I)));
      I := J + 1;
    end;
    Result := CheckOptions(Shortoptions, L, AllErrors);
  finally
    L.Free;
  end;
end;

function TfpgOhosCmdLineParams.GetNonOptions(const ShortOptions: string; const LongOpts: array of string): TStringArray;
var
  NO : TStrings;
  I : Integer;
begin
  NO := TStringList.Create;
  try
    GetNonOptions(ShortOptions, LongOpts, No);
    SetLength(Result, NO.Count);
    For I := 0 to NO.Count-1 do
      Result[I] := NO[i];
  finally
    NO.Free;
  end;
end;

procedure TfpgOhosCmdLineParams.GetNonOptions(const ShortOptions: string; const LongOpts: array of string; NonOptions: TStrings);
var
  S: String;
begin
  S := CheckOptions(ShortOptions, LongOpts, Nil, NonOptions, true);
  if (S <> '') then
    Raise EListError.Create(S);
end;

function TfpgOhosCmdLineParams.GetCaseSensitiveOptions: Boolean;
begin
  Result := FCaseSensitiveOptions;
end;

function TfpgOhosCmdLineParams.GetOptionChar: char;
begin
  Result := FOptionChar;
end;

procedure TfpgOhosCmdLineParams.SetCaseSensitiveOptions(AValue: Boolean);
begin
  FCaseSensitiveOptions := AValue;
end;

procedure TfpgOhosCmdLineParams.SetOptionChar(AValue: char);
begin
  FOptionChar := AValue;
end;

function TfpgOhosCmdLineParams.ParamStr(AIndex: integer): string;
begin
  if AIndex < FItems.Count then
    Result := FItems[AIndex]
  else
    Result := '';
end;

function TfpgOhosCmdLineParams.GetParams(AIndex: integer): string;
begin
  Result := GetOptionAtIndex(AIndex, False);
end;

function TfpgOhosCmdLineParams.GetParamCount: integer;
begin
  Result := FItems.Count;
end;

end.
