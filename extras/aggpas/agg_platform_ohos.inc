{%mainunit Agg2D.pas}

{ OHOS (HarmonyOS) platform implementation for AggPas.
  Uses the native_window API (RequestBuffer + mmap + FlushBuffer) to
  blit the AggPas software-rendered buffer to the OHOS NativeWindow
  surface. Font rendering is handled by OHOS native_drawing
  (AGG2D_NO_FONT is defined in agg_mode.inc), so no FreeType/Win32
  font engine is compiled in. }

{$ifdef uses_interface}
  { No additional units required in the interface section. }
{$endif}


{$ifdef agg_platform_interface}
  protected
{$endif}


{$ifdef uses_implementation}
  fpg_ohos,
  fpg_ohos_nativewindow,
  fpg_impl,           { TfpgWinHandle (= Pointer, OHNativeWindow*) }
  fpg_fontcache,
{$endif}


{$ifdef agg_platform_implementation}

const
  { mmap constants (same as <sys/mman.h> PROT_* / MAP_*). }
  OHOS_PROT_READ     = 1;
  OHOS_PROT_WRITE    = 2;
  OHOS_MAP_SHARED    = 1;

type
  { to get access to protected methods (seeing that FPC doesn't support Friend-classes) }
  TImageHack = class(TfpgImage);

  { TfpgOhosWindow hack to access WinHandle (declared as public property,
    so no hack needed, but kept for consistency with other platforms). }
  TfpgOhosWindowHack = class(TfpgOhosWindow);


{ Resolve an Agg2D font request ('times.ttf' etc.) to a readable file path
  on OHOS. Probe order: as-given (absolute or cwd-relative), the system
  fonts directory, the HAP bundle libs directories (all ABI layouts), the
  app sandbox files directories, and the HAP 'resfile' directories (their
  contents are decompressed into the sandbox at install time, e.g.
  /data/storage/el1/bundle/<moduleName>/resources/resfile/). Returns
  AFileName unchanged when no candidate matched. }
function OhosResolveAggFontFile(const AFileName: string): string;
const
  OhosAggFontProbeDirs: array[0..11-5] of string = (
    '',
    '/system/fonts/',
//    '/data/storage/el1/bundle/libs/x86_64/',
//    '/data/storage/el1/bundle/libs/arm64-v8a/',
//    '/data/storage/el1/bundle/libs/arm64/',
    '/data/storage/el2/base/files/',
    '/data/storage/el2/base/haps/entry/files/',
//    '/data/storage/el1/bundle/fp_bridge/resources/resfile/',
//    '/data/storage/el1/bundle/fp_bridge/resources/resfile/fonts/',
    '/data/storage/el1/bundle/entry/resources/resfile/',
    '/data/storage/el1/bundle/entry/resources/resfile/fonts/',
    '/data/storage/el1/bundle/resources/resfile/'
  );
var
  lName: string;
  i: Integer;
  lCand: string;
  lRes: TSearchRec;
  lBase: string;
begin
  Result := AFileName;
  if AFileName = '' then
    Exit;
  lName := ExtractFileName(AFileName);
  if lName = '' then
    Exit;
  for i := Low(OhosAggFontProbeDirs) to High(OhosAggFontProbeDirs) do
  begin
    lCand := OhosAggFontProbeDirs[i] + lName;
    if FileExists(lCand) then
    begin
      Result := lCand;
      Exit;
    end;
  end;
  { Module name is not known at compile time: scan the bundle sandbox for
    '<module>/resources/resfile[/fonts]/<name>' as well. }
  if FindFirst('/data/storage/el1/bundle/*', faDirectory, lRes) = 0 then
  begin
    try
      repeat
        if (lRes.Name <> '.') and (lRes.Name <> '..') and
           ((lRes.Attr and faDirectory) <> 0) then
        begin
          lBase := '/data/storage/el1/bundle/' + lRes.Name + '/resources/resfile/';
          if FileExists(lBase + lName) then
          begin
            Result := lBase + lName;
            Exit;
          end;
          if FileExists(lBase + 'fonts/' + lName) then
          begin
            Result := lBase + 'fonts/' + lName;
            Exit;
          end;
        end;
      until FindNext(lRes) <> 0;
    finally
      FindClose(lRes);
    end;
  end;
end;


function FontCacheItemFromFontDesc(const desc: string; var asize: double): TFontCacheItem;
var
  facename: string;
  cp: integer;
  c: char;
  token: string;
  prop, propval: string;

  function NextC: char;
  begin
    Inc(cp);
    if cp > length(desc) then
      c := #0
    else
      c := desc[cp];
    Result := c;
  end;

  procedure NextToken;
  begin
    token := '';
    while (c <> #0) and (c in [' ', 'a'..'z', 'A'..'Z', '_', '0'..'9', '.']) do
    begin
      token := token + c;
      NextC;
    end;
  end;

begin
  Result := TFontCacheItem.Create('');

  cp := 0;
  NextC;
  NextToken;

  facename := token;
  // Substitute common bitmap font names to outline equivalents.
  if CompareText(facename, 'Helv') = 0 then
    facename := FPG_DEFAULT_SANS
  else if CompareText(facename, 'Helvetica') = 0 then
    facename := FPG_DEFAULT_SANS
  else if CompareText(facename, 'Tms Rmn') = 0 then
    facename := 'Times New Roman'
  else if CompareText(facename, 'Times') = 0 then
    facename := 'Times New Roman'
  else if CompareText(facename, 'System Proportional') = 0 then
    facename := FPG_DEFAULT_SANS
  else if CompareText(facename, 'System Monospaced') = 0 then
    facename := FPG_DEFAULT_FIXED
  else if CompareText(facename, 'System VIO') = 0 then
    facename := FPG_DEFAULT_FIXED
  else if CompareText(facename, 'Courier') = 0 then
    facename := 'Courier New'
  else if CompareText(facename, 'Monospace') = 0 then
    facename := FPG_DEFAULT_FIXED;
  Result.FamilyName := facename;

  if c = '-' then
  begin
    NextC;
    NextToken;
    asize := StrToIntDef(token, 0);
  end;

  while c = ':' do
  begin
    NextC;
    NextToken;

    prop    := UpperCase(token);
    propval := '';

    if c = '=' then
    begin
      NextC;
      NextToken;
      propval := UpperCase(token);
    end;

    if prop = 'BOLD' then
      Result.IsBold := True
    else if prop = 'ITALIC' then
      Result.IsItalic := True
    else if prop = 'ANGLE' then
      Result.Angle := StrToFloatDef(propval, 0.0);
  end;
end;


procedure TAgg2D.DoPutBufferToScreen(x, y, w, h: TfpgCoord);
var
  win: TfpgOhosWindowHack;
  nativeWin: TfpgWinHandle;
  buf: Pointer;
  fence: Int32;
  hdl: PBufferHandle;
  addr: Pointer;
  region: TOH_Region;
  regRect: TOH_Region_Rect;
  srcData: Pointer;
  srcStride, dstStride: Int32;
  copyW, copyH: Int32;
  physX, physY, physW, physH: Integer;
  scale: Double;
  i: Integer;
begin
  { Only the top-level window canvas puts the buffer to the screen.
    On OHOS, the TOhosHybridCanvas is the primary rendering path and
    delegates to its IBufferManager. This implementation covers the case
    where TAgg2D is used directly as a standalone canvas. }
  if not FWidget.WindowAllocated then
    Exit;
  win := TfpgOhosWindowHack(FWidget.Window);
  if win = nil then
    Exit;
  nativeWin := win.WinHandle;
  if nativeWin = nil then
    Exit;

  if not Assigned(FImg) then
    Exit;
  FImg.UpdateImage;
  srcData := FImg.ImageData;
  if srcData = nil then
    Exit;

  { Convert logical coordinates to physical (OHOS NativeWindow buffer
    is in physical pixels). gHiDPIScaleFactor is set from gScaleFactorX
    in ohos_set_screen_size. }
  scale := gHiDPIScaleFactor;
  if scale < 1.0 then
    scale := 1.0;
  physX := Round(x * scale);
  physY := Round(y * scale);
  physW := Round(w * scale);
  physH := Round(h * scale);

  if (physW <= 0) or (physH <= 0) then
    Exit;

  { Set the flush region to the physical rectangle. }
  regRect.x := physX;
  regRect.y := physY;
  regRect.w := physW;
  regRect.h := physH;
  region.rects := @regRect;
  region.rectNumber := 1;

  { Request a native buffer (API 20+: RequestBuffer replaces LockBuffer). }
  buf := nil;
  fence := -1;
  if OH_NativeWindow_NativeWindowRequestBuffer(nativeWin, @buf, @fence) <> 0 then
    Exit;

  hdl := OH_NativeWindow_GetBufferHandleFromNative(buf);
  if hdl = nil then
  begin
    OH_NativeWindow_NativeWindowAbortBuffer(nativeWin, buf);
    Exit;
  end;

  { mmap the native buffer for CPU access. }
  addr := fpmmap(nil, hdl^.size,
    OHOS_PROT_READ or OHOS_PROT_WRITE, OHOS_MAP_SHARED,
    hdl^.fd, 0);
  if addr = Pointer(-1) then
  begin
    OH_NativeWindow_NativeWindowAbortBuffer(nativeWin, buf);
    Exit;
  end;

  { Copy pixel data from the AggPas buffer to the native window buffer.
    Both are 32-bit RGBA, so a direct byte copy works. }
  srcStride := FImg.Width * 4;
  dstStride := hdl^.stride;

  copyW := physW * 4;
  if copyW > dstStride then
    copyW := dstStride;
  if (physX * 4 + copyW) > srcStride then
    copyW := srcStride - physX * 4;

  copyH := physH;
  if copyH > hdl^.height - physY then
    copyH := hdl^.height - physY;
  { Clamp source rows to our image buffer. }
  if (physY + copyH) > FImg.Height then
    copyH := FImg.Height - physY;

  if (copyW > 0) and (copyH > 0) then
  begin
    for i := 0 to copyH - 1 do
      Move(PByte(srcData)[(physY + i) * srcStride + physX * 4],
           PByte(addr)[(physY + i) * dstStride + physX * 4],
           copyW);
  end;

  { Unmap before FlushBuffer (matching the non-AGG pattern). }
  fpmunmap(addr, hdl^.size);

  { Submit the buffer to the surface. }
  OH_NativeWindow_NativeWindowFlushBuffer(nativeWin, buf, fence, region);

  { 首帧上屏通知：TAgg2D 独立画布路径首次成功 FlushBuffer 后告知 ETS 打开
    XComponent 显示门（contentReady/firstFrameArrived）。缺失此通知时 ETS
    侧 firstFrameArrived 恒为 false → XComponent Visibility.Hidden →
    窗口只显示页面背景（内容不可见）。同句柄仅通知一次（内部去重）。 }
  OhosNotifyFirstFrame(nativeWin);
end;


procedure TAgg2D.DoRestoreFromBuffer(const ARect: TfpgRect);
begin
  { Blit the given rectangle from the off-screen buffer to the window.
    On OHOS there is no Expose event, but the semantics match GDI/X11:
    copy the specified rect from the back-buffer to the screen. }
  if (ARect.Width < 1) or (ARect.Height < 1) then
    Exit;
  if not Assigned(FImg) then
    Exit;
  DoPutBufferToScreen(ARect.Left, ARect.Top, ARect.Width, ARect.Height);
end;


{$endif}
