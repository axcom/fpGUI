import fpbridge from 'libfp_bridge.so';
import { window, display, LevelOrder, dragController } from '@kit.ArkUI';
import { unifiedDataChannel } from '@kit.ArkData';
import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getWindowStage, getMainWindow, terminateAbility, getLaunchPayload, getMergedArgs } from '../fp_bridgeability/Fp_bridgeAbility';
import { APP_LIB_NAME } from '../common/FpAppConfig';
import { FpgSurface, FpgSurfaceCtrl, notifyFirstFrame, registerWindowPositionSync, unregisterWindowPositionSync } from '../common/FpgSurface';
import { TrayManager } from '../common/TrayManager';
import { initTimerDaemon, startTimerTick, stopTimerTick } from '../common/TimerDaemon';
import { initKeyboardDetector } from '../common/KeyboardDetector';
import { pointer } from '@kit.InputKit';
import { showFilePicker } from '../common/FpgFilePicker';
import { handleFileIo, FileIoCommand } from '../common/FpgFileIo';

interface NativeCommand {
  type: number;
  reqId: number;
  x: number;
  y: number;
  width: number;
  height: number;
  windowAttributes: number;
  windowType: number;
  surfaceId: string;
  xcId: string;
  title: string;
  payload: string;
  // 文件流命令（type=21）专用字段
  offset: number;
  length: number;
  data: ArrayBuffer;
}

// ── 系统拖拽起拖载荷（Pascal OhosMimeDataToJson 序列化）──
interface DragPayload {
  text?: string;
  html?: string;
  uris?: string[];
  actions?: number;
  default?: number;
}

// executeDrag extraParams（sessionId 回传 + 动作协商位掩码）
interface DragExtraParams {
  session: number;
  actions: number;
  default: number;
}

const DOMAIN = 0x0000;
const TAG = 'page-Index';

@Entry
@Component
struct Index {
  private subWinMap: Map<number, window.Window> = new Map();
  private imeCtrl: FpgSurfaceCtrl = new FpgSurfaceCtrl();  // 主窗 FpgSurface（XComponent/IME/事件）控制桥
  private hiddenInputCtrl: TextInputController = new TextInputController();  // 隐藏 TextInput 控制器（数字键捕获）
  // 修饰键状态追踪（hidden TextInput 全键转发用）
  private hiShiftDown: boolean = false;
  private hiCtrlDown: boolean = false;
  private hiAltDown: boolean = false;
  private hiMetaDown: boolean = false;
  private lastShakeAt: number = 0;   // 模态抖动节流（连续 DROPPED 触发时防动画打断）
  // 位置同步统一交由 FpgSurface.PositionSync（主窗+子窗 150ms 轮询，windowRectChange 为即时通道）
  // 主窗 XComponent 延迟创建：Pascal 创建命令（setupMainWindow resize 完成）后才渲染。
  // XComponent surface（buffer 池）固定于创建时刻的窗口尺寸——若页面首帧就创建
  // （窗口还是系统默认 1900x1260），surface=1900x1260 而 fpGUI buffer=期望客户区
  // （如 1710x1045）→ 内容只画左上角，右/下黑边。延迟到窗口 resize 完成后创建
  // → surface=期望尺寸 → buffer 1:1 填满，首帧黑边根治。
  @State mainReady: boolean = false;
  // 光标统一 ArkTS（pointer.setPointerStyle）依赖：reqId → WindowManager windowId，
  // 与 setWindowPointerId 上报同步维护（创建 set、销毁 delete）。
  private winPointerIds: Map<number, number> = new Map();
  // windowSizeChange 去重：部分系统在纯移动（位置变化、尺寸不变）时也回调
  // 本事件 → 过滤后避免多余的 SET_BUFFER_GEOMETRY+重绘+提交 → 防拖动花屏。
  private lastMainSizeW: number = 0;
  private lastMainSizeH: number = 0;
  private lastSubSize: Map<number, [number, number]> = new Map();

  aboutToAppear(): void {
    fpbridge.setEtsReady();
    hilog.info(DOMAIN, TAG, 'Index: setEtsReady called');
    // 启动 Pascal fpGUI 应用（库名由外部配置 FpAppConfig.APP_LIB_NAME 动态指定；
    // PascalThread 内部等待 ETS ready 后 dlopen "lib<APP_LIB_NAME>.so"）
    // 第二参数：启动载荷 JSON（want.uri/action/entities/parameters）→ C++ argv → RunLazarus
    // 第三参数：命令行参数（-b debug / key=value 风格）→ Pascal ICmdLineParams
    fpbridge.start(APP_LIB_NAME, getLaunchPayload(), getMergedArgs());
    TrayManager.getInstance().init(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // 物理键盘检测（PC 模式 → 不弹软键盘）；含热插拔监听
    initKeyboardDetector();

    fpbridge.setNativeCallback((cmdObj: object) => {
      const cmd: NativeCommand = {
        type: cmdObj['type'] as number,
        reqId: cmdObj['reqId'] as number,
        x: cmdObj['x'] as number,
        y: cmdObj['y'] as number,
        width: cmdObj['width'] as number,
        height: cmdObj['height'] as number,
        windowAttributes: cmdObj['windowAttributes'] as number,
        windowType: cmdObj['windowType'] as number,
        surfaceId: cmdObj['surfaceId'] as string,
        xcId: cmdObj['xcId'] as string,
        title: cmdObj['title'] as string,
        payload: cmdObj['payload'] as string,
        // 文件流命令（type=21）专用字段（C++ 对命令 21 始终下发）
        offset: cmdObj['offset'] as number,
        length: cmdObj['length'] as number,
        data: cmdObj['data'] as ArrayBuffer
      };
      this.handleNativeCommand(cmd);
    }, 'window');
    hilog.info(DOMAIN, TAG, 'Index: window callback registered');
    // 定时器 ArkUI 注入：补查当前是否有活动定时器（Pascal 早发通知时回调未注册会丢）
    initTimerDaemon();
  }

  aboutToDisappear(): void {
    stopTimerTick();
  }

  private handleNativeCommand(cmd: NativeCommand): void {
    switch (cmd.type) {
      case 0:
        this.createWindowFromNative(cmd.reqId, cmd.xcId, cmd.width, cmd.height,
          cmd.x, cmd.y, cmd.windowAttributes, cmd.windowType, cmd.surfaceId, cmd.title);
        break;
      case 1:
        this.moveWindow(cmd.reqId, cmd.x, cmd.y);
        break;
      case 2:
        this.showWindow(cmd.reqId);
        break;
      case 3:
        this.hideWindow(cmd.reqId);
        break;
      case 4:
        this.destroyWindow(cmd.reqId);
        break;
      case 5:
        this.shakeWindow(cmd.reqId);
        break;
      case 6:
        if (cmd.x > 0) {
          if (this.imeCtrl.showIme) this.imeCtrl.showIme(cmd.x);
        } else {
          if (this.imeCtrl.hideIme) this.imeCtrl.hideIme();
        }
        break;
      case 7:
        this.resizeWindow(cmd.reqId, cmd.width, cmd.height);
        break;
      case 8:
        TrayManager.getInstance().add(cmd.title);
        break;
      case 9:
        TrayManager.getInstance().setMenu(cmd.payload);
        break;
      case 10:
        TrayManager.getInstance().remove();
        break;
      case 11:
        // 定时器 ArkUI tick 启停（Pascal TfpgOhosTimer 感知翻转通知）
        if (cmd.x > 0) {
          startTimerTick();
        } else {
          stopTimerTick();
        }
        break;
      case 12:
        // 光标统一 ArkTS：C++ 无脑转发 → pointer.setPointerStyle(windowId, style)
        this.applyPointerStyle(cmd.reqId, cmd.x);
        break;
      case 13:
        // 系统拖拽起拖：reqId = sessionId（低 31 位），payload = dataJson，title = extraJson
        this.startSystemDrag(cmd.reqId, cmd.payload, cmd.title);
        break;
      case 14:
        // 窗口拖入开关（Pascal DoDNDEnabled → C++ → ETS）
        AppStorage.setOrCreate<number>('dndEnabled_' + cmd.reqId, cmd.x);
        hilog.info(DOMAIN, TAG, 'dndEnabled req=%{public}d = %{public}d', cmd.reqId, cmd.x);
        break;
      case 15:
        // 窗口状态：0=normal 1=minimized 2=maximized
        this.applyWindowState(cmd.reqId, cmd.x);
        break;
      case 16:
        // 窗口透明度：value = opacity*1000（OpenHarmony SDK 无 setWindowOpacity →
        // 暂存 AppStorage 供未来 SDK 启用；仅日志）
        this.applyWindowOpacity(cmd.reqId, cmd.x);
        break;
      case 17:
        // 窗口标题（运行时修改）
        this.applyWindowTitle(cmd.reqId, cmd.title);
        break;
      case 18:
        // 窗口属性位掩码（waFullScreen/waBorderless/waStayOnTop/waSystemStayOnTop）
        this.applyWindowAttributes(cmd.reqId, cmd.x);
        break;
      case 19:
        // Pascal 首帧已上屏 → 打开该窗口 XComponent 显示门（防黑屏闪现）
        notifyFirstFrame(cmd.reqId);
        break;
      case 20:
        // 系统文件选择器：cmd.x = 类型(0文档打开/1图片视频/2音频/3文档另存为)，cmd.payload = optsJson
        showFilePicker(this.getUIContext().getHostContext() as common.UIAbilityContext, cmd.reqId, cmd.x, cmd.payload);
        break;
      case 21:
        // 文件流：cmd.x=子操作 cmd.y=模式/句柄 offset/length payload=URI data=写数据
        // ArkTS 名义类型（arkts-no-structural-typing）：NativeCommand 不能结构兼容
        // 传给 FileIoCommand 形参，必须显式构造目标接口字面量
        const fcmd: FileIoCommand = {
          reqId: cmd.reqId,
          x: cmd.x,
          y: cmd.y,
          offset: cmd.offset,
          length: cmd.length,
          payload: cmd.payload,
          data: cmd.data
        };
        handleFileIo(fcmd);
        break;
      default:
        hilog.warn(DOMAIN, TAG, 'Unknown native command type=%{public}d', cmd.type);
    }
  }

  // ── 窗口属性联动（Pascal TfpgOhosWindow → OHOS Window）──────────────
  private getWin(reqId: number): window.Window | null {
    if (reqId === 1) return getMainWindow();
    return this.subWinMap.get(reqId) ?? null;
  }

  private async applyWindowState(reqId: number, state: number): Promise<void> {
    const win = this.getWin(reqId);
    if (win === null) {
      hilog.warn(DOMAIN, TAG, 'setState: no window req=%{public}d', reqId);
      return;
    }
    try {
      if (state === 1) {
        await win.minimize();
      } else if (state === 2) {
        await win.maximize();
      } else {
        await win.restore();
      }
      hilog.info(DOMAIN, TAG, 'setState req=%{public}d state=%{public}d OK', reqId, state);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setState req=%{public}d state=%{public}d failed: %{public}s',
        reqId, state, JSON.stringify(e));
    }
  }

  private applyWindowOpacity(reqId: number, opacityX1000: number): void {
    // OpenHarmony SDK 无 setWindowOpacity：暂存（未来 SDK 支持后在此启用）
    AppStorage.setOrCreate<number>('winOpacity_' + reqId, opacityX1000 / 1000);
    hilog.info(DOMAIN, TAG, 'setOpacity req=%{public}d opacity=%.3f (SDK 预留)',
      reqId, opacityX1000 / 1000);
  }

  private async applyWindowTitle(reqId: number, title: string): Promise<void> {
    const win = this.getWin(reqId);
    if (win === null) return;
    try {
      await win.setWindowTitle(title);
      hilog.info(DOMAIN, TAG, 'setTitle req=%{public}d title=%{public}s OK', reqId, title);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setTitle req=%{public}d failed: %{public}s',
        reqId, JSON.stringify(e));
    }
  }

  private async applyWindowAttributes(reqId: number, attrs: number): Promise<void> {
    const win = this.getWin(reqId);
    if (win === null) return;
    const ATTR_STAY_ON_TOP = 1 << 2;
    const ATTR_FULLSCREEN = 1 << 3;
    const ATTR_BORDERLESS = 1 << 4;
    const ATTR_SYS_STAY_ON_TOP = 1 << 7;
    try {
      // 全屏：沉浸全屏（内容延伸到系统栏后面）
      if ((attrs & ATTR_FULLSCREEN) !== 0) {
        await win.setWindowLayoutFullScreen(true);
        hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen');
      } else {
        try { await win.setWindowLayoutFullScreen(false); } catch (_e) {}
      }
      // 无边框：隐藏系统装饰 + 最大化
      if ((attrs & ATTR_BORDERLESS) !== 0) {
        try { await win.setWindowDecorVisible(false); } catch (_e) {}
        try { await win.maximize(); } catch (_e) {}
      }
      // 置顶（waStayOnTop | waSystemStayOnTop）
      const topmost = (attrs & (ATTR_STAY_ON_TOP | ATTR_SYS_STAY_ON_TOP)) !== 0;
      try { await win.setWindowTopmost(topmost); } catch (_e) {}
      hilog.info(DOMAIN, TAG, 'setAttrs req=%{public}d attrs=%{public}d OK', reqId, attrs);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setAttrs req=%{public}d attrs=%{public}d failed: %{public}s',
        reqId, attrs, JSON.stringify(e));
    }
  }

  // 光标统一 ArkTS（@ohos.multimodalInput.pointer，@since 9 —— API 20/24 均支持）。
  // CursorMap 数值与 pointer.PointerStyle 同序同值，可直接 cast 传入。
  private applyPointerStyle(reqId: number, style: number): void {
    const wId = this.winPointerIds.get(reqId);
    if (wId === undefined) {
      return;   // 窗口 id 未上报（如 handle 无法解析）——静默
    }
    try {
      pointer.setPointerStyle(wId, style as pointer.PointerStyle).catch(() => {});
    } catch (_e) {}
  }

  // ── 系统拖拽：起拖（Pascal TfpgOhosDrag.Execute → ohos_drag_start → case 13）──
  // dataJson: {"text","html","uris","types","actions","default"}（Pascal 序列化）
  // extraJson: {"actions":位掩码,"default":序号}（当前仅日志/扩展用）
  private async startSystemDrag(sessionId: number, dataJson: string, extraJson: string): Promise<void> {
    try {
      const data = JSON.parse(dataJson) as DragPayload;
      const unified = new unifiedDataChannel.UnifiedData();
      if (data.text && data.text.length > 0) {
        const rec = new unifiedDataChannel.PlainText();
        rec.textContent = data.text;
        rec.abstract = data.text.slice(0, 32);
        unified.addRecord(rec);
      }
      if (data.html && data.html.length > 0) {
        const rec = new unifiedDataChannel.HTML();
        rec.htmlContent = data.html;
        unified.addRecord(rec);
      }
      if (data.uris && data.uris.length > 0) {
        for (const u of data.uris) {
          const rec = new unifiedDataChannel.File();
          rec.uri = u;
          unified.addRecord(rec);
        }
      }
      const extra: DragExtraParams = {
        session: sessionId,
        actions: data.actions ?? 1,
        default: data.default ?? 1
      };
      const info: dragController.DragInfo = {
        pointerId: 0,   // 鼠标起拖场景 v1 固定 0（后续可传实际 pointerId）
        data: unified,
        extraParams: JSON.stringify(extra)
      };
      this.getUIContext().getDragController().executeDrag(() => {
        this.DragPreviewBuilder();
      }, info, (err, res) => {
        let result = DragResult.DRAG_CANCELED;
        if (!err && res?.event) {
          result = res.event.getResult();
        }
        fpbridge.onDragEnd(sessionId, this.dragResultToCode(result));
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'startSystemDrag failed: %{public}s', JSON.stringify(e));
      fpbridge.onDragEnd(sessionId, 2);   // CANCELED：保证 Pascal Execute 不卡 60s
    }
  }

  private dragResultToCode(r: DragResult): number {
    if (r === DragResult.DRAG_SUCCESSFUL) return 1;
    if (r === DragResult.DRAG_FAILED) return 0;
    return 2;
  }

  // 系统拖拽跟手预览（v1 简单圆角矩形；后续可升级 PixelMap 截取 fpGUI 控件画面）
  @Builder
  DragPreviewBuilder() {
    Column() {
      Text('fpGUI')
        .fontSize(12)
        .fontColor(Color.White)
    }
    .width(96)
    .height(40)
    .borderRadius(8)
    .backgroundColor('#FF3D7EFF')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 主窗口（Ability 窗口）尺寸/位置/全屏控制。
  // attrs = fpGUI TWindowAttributes bitmask（fpg_base.pas 枚举序）：
  //   waFullScreen=bit3(1<<3)，waBorderless=bit4(1<<4)
  // 规则：
  //   waFullScreen+waBorderless → setWindowLayoutFullScreen(true)（沉浸全屏，无装饰）
  //   waFullScreen 无 waBorderless → maximize()（最大化，保留系统标题栏）
  //   无 waFullScreen → 标准窗口模式：resize/moveTo（客户区+系统装饰补偿）；
  //     含 waBorderless → setWindowDecorVisible(false) 隐藏系统标题栏
  // 闭环 resize 校正：drawable = resize 输入 + 系统偏移（2in1 FLOATING 实测 +2,+11，
  // 换机器可能不同）→ resize(w-dx, h-dy) 迭代，读实际 drawable 反推偏移直到收敛
  // （≤4 次）。任何设备的系统偏移都能自适应，无需硬编码。
  private async resizeToClient(win: window.Window, w: number, h: number): Promise<void> {
    let dx = 0;
    let dy = 0;
    for (let i = 0; i < 4; i++) {
      await win.resize(w - dx, h - dy);
      await new Promise<void>(r => setTimeout(r, 120));
      try {
        const p = win.getWindowProperties();
        dx = p.drawableRect.width - w;
        dy = p.drawableRect.height - h;
        if (Math.abs(dx) <= 2 && Math.abs(dy) <= 2) break;
        hilog.info(DOMAIN, TAG,
          'resizeToClient iter=%{public}d: drawable=%{public}dx%{public}d delta=(%{public}d,%{public}d) -> resize(%{public}dx%{public}d)',
          i, p.drawableRect.width, p.drawableRect.height, dx, dy, w - dx, h - dy);
      } catch (_e) {
        break;
      }
    }
  }

  private async setupMainWindow(width: number, height: number,
      posX: number, posY: number, attrs: number, winTitle: string): Promise<void> {
    const ATTR_FULLSCREEN = 1 << 3;
    const ATTR_BORDERLESS = 1 << 4;
    // waBorderless：主窗无系统装饰（setWindowDecorVisible(false)）→ decW/decH 按 0 处理
    const borderless = (attrs & ATTR_BORDERLESS) !== 0;
    const mainWin = getMainWindow();
    if (mainWin === null) return;
    try {
      // 主窗 windowId 上报（OH_Input_SetPointerStyle 需要真实窗口 id；
      // 此前缺失导致系统光标样式不切换）。主窗重建路径也走本函数 → 自动重报。
      const mainWinId: number = mainWin.getWindowProperties().id;
      hilog.info(DOMAIN, TAG, 'PointerId report: req=%{public}d id=%{public}d', 1, mainWinId);
      this.winPointerIds.set(1, mainWinId);
    } catch (_e) {}
    try {
      if (winTitle && winTitle.length > 0) {
        try { await mainWin.setWindowTitle(winTitle); } catch (_e) {}
      }
      if ((attrs & ATTR_FULLSCREEN) !== 0) {
        // 全屏模式：
        //   含 waBorderless（无边框）→ 沉浸全屏（隐藏系统装饰）
        //   不含 waBorderless（有边框）→ 最大化（保留系统标题栏/系统栏）
        if ((attrs & ATTR_BORDERLESS) !== 0)
          await mainWin.setWindowLayoutFullScreen(true);  // 沉浸全屏
        else
          await mainWin.maximize();                       // 最大化
      } else {
        // 标准窗口模式：系统标题栏（默认）；waBorderless 时隐藏装饰
        if ((attrs & ATTR_BORDERLESS) !== 0) {
          try {
            await mainWin.setWindowDecorVisible(false);
            await mainWin.setWindowTitleButtonVisible(false,false,false);
          } catch (_e) {}
        }
        // 注：SDK 12 无 setWindowMode/WindowMode API（自由悬浮窗口模式不可显式切换；
        // 主窗口默认即标准窗口模式，resize/moveTo 有效）。后续 SDK 支持时可在
        // phone 模式切换 FLOATING 后操作。
        const props = mainWin.getWindowProperties();
        // 装饰隐藏后 windowRect-drawableRect 可能是残留假装饰，触摸补偿/定位
        // 补偿/resize 必须按实际装饰（borderless→0）处理，否则偏移一个标题栏高。
        const decW = borderless ? 0 : props.windowRect.width  - props.drawableRect.width;
        const decH = borderless ? 0 : props.windowRect.height - props.drawableRect.height;
        // 标题栏高度（触摸补偿用）：统一存 AppStorage('decH_1')。
        // 注意单位：触摸坐标 displayX/Y 为 vp → 存 vp 值（÷densityPixels）
        const densityPx: number = display.getDefaultDisplaySync().densityPixels;
        AppStorage.setOrCreate<number>('decH_1', decH / densityPx);
        // 左边框 vp（左右对称 decW/2）：onMouse X 补偿 + 标题栏真高（decH-下边框）计算
        AppStorage.setOrCreate<number>('decW_1', decW / 2 / densityPx);
        // 上报 C++（Pascal 弹窗定位补偿）：逻辑值（÷densityPx，与 Pascal 逻辑坐标空间一致；
        // ETS 本地 resize 仍用 px 原值 decW/decH）
        fpbridge.setMainWindowDec(Math.round(decW / densityPx), Math.round(decH / densityPx));
        try {
          // width/height 与 resize 均为 px（C++ 透传的 Pascal 逻辑 px 与 OHOS px 1:1）。
          // 闭环校正：drawable=resize 输入+系统偏移 → 迭代收敛到期望客户区。
          await this.resizeToClient(mainWin, width, height);
          await mainWin.moveWindowTo(posX, posY);

          // ── 二次校正：部分版本 resize 后 drawable 与期望不符（内容被压缩）──
          {
            const props2 = mainWin.getWindowProperties();
            const decW2 = borderless ? 0 : props2.windowRect.width  - props2.drawableRect.width;
            const decH2 = borderless ? 0 : props2.windowRect.height - props2.drawableRect.height;
            hilog.info(DOMAIN, TAG,
              'MainWindow resized: windowRect=%dx%d drawable=%{public}dx%{public}d dec=%{public}d,%{public}d expect client=%{public}dx%{public}d',
              props2.windowRect.width, props2.windowRect.height,
              props2.drawableRect.width, props2.drawableRect.height,
              decW2, decH2, width, height);
            if (props2.windowRect.width !== width + decW2 ||
                props2.windowRect.height !== height + decH2 ||
                props2.drawableRect.width !== width ||
                props2.drawableRect.height !== height) {
              await this.resizeToClient(mainWin, width, height);
              hilog.info(DOMAIN, TAG,
                'MainWindow corrected: resizeToClient %{public}dx%{public}d', width, height);
            }
            // resize 可能改变窗口位置（部分版本底部/中心锚定）→ 重新定位，
            // 否则弹窗菜单基于 FPosition 定位会错位
            await mainWin.moveWindowTo(posX, posY);
            // 装饰值若有变化，更新存储（触摸 vp）与 C++（定位逻辑值）
            AppStorage.setOrCreate<number>('decH_1', decH2 / densityPx);
            AppStorage.setOrCreate<number>('decW_1', decW2 / 2 / densityPx);
            fpbridge.setMainWindowDec(Math.round(decW2 / densityPx), Math.round(decH2 / densityPx));
          }
        } catch (e2) {
          // 设备把主窗强制最大化 / 不允许自由 resize（实测 code=1300002
          // "CheckAndModifyWindowRect failed"）：drawable 含系统栏区域，而
          // 页面/XComponent 只覆盖其中一部分（实测 2800x1840 vs 2800x1691，
          // 差 149px）→ 合成器把 Pascal 小缓冲放大显示 + 点击坐标错位。
          // 处理：切沉浸全屏，让 page=XComponent=drawable（系统栏隐藏），
          // 再由 FpgSurface.onAreaChange/windowSizeChange 上报真实尺寸
          // （C++ 侧 pending 补送）→ Pascal 重建 1:1 缓冲。
          hilog.warn(DOMAIN, TAG,
            'MainWindow resize rejected (msg=%{public}s) -> immersive fullscreen',
            (e2 as Error).message || '');
          try { await mainWin.setWindowLayoutFullScreen(true); } catch (_e) {}
          // 隐藏系统状态栏（保留底部导航），使顶部 Tab/控件不被时间/电量遮挡，
          // 且整个 surface 区域可点击（沉浸全屏已获确认）。
          try { await mainWin.setWindowSystemBarEnable(['navigation']); } catch (_e) {}
          AppStorage.setOrCreate<number>('decH_1', 0);
          AppStorage.setOrCreate<number>('decW_1', 0);
          fpbridge.setMainWindowDec(0, 0);
        }

        mainWin.on('windowSizeChange', (size: window.Size) => {
          // 去重：部分系统在纯移动（位置变化、尺寸不变）时也回调本事件，
          // 若不过滤会触发多余的 SET_BUFFER_GEOMETRY+重绘+提交 → 拖动花屏。
          if (size.width === this.lastMainSizeW && size.height === this.lastMainSizeH) {
            return;
          }
          this.lastMainSizeW = size.width;
          this.lastMainSizeH = size.height;
          // 现算 dec（二次校正后装饰值可能变化，避免闭包旧值）；
          // waBorderless 时装饰已隐藏，按 0 处理（残留假装饰会误导补偿/校准）
          const p3 = mainWin.getWindowProperties();
          const decW3 = borderless ? 0 : p3.windowRect.width  - p3.drawableRect.width;
          const decH3 = borderless ? 0 : p3.windowRect.height - p3.drawableRect.height;
          // 最大化/平铺（左右分屏）时系统隐藏标题栏 → dec 变化 → 实时更新
          // 触摸补偿（decW_1 左边框/decH_1 标题栏）与 Pascal 弹窗定位（setMainWindowDec）。
          // 现算 decW3/decH3 即系统真实值（windowRect−drawable），无需 decorHeight
          // 校准 API（旧校准块含 resize 重设，最大化时会把窗口拉回普通尺寸）。
          AppStorage.setOrCreate<number>('decH_1', decH3 / densityPx);
          AppStorage.setOrCreate<number>('decW_1', decW3 / 2 / densityPx);
          fpbridge.setMainWindowDec(Math.round(decW3 / densityPx), Math.round(decH3 / densityPx));
          // waBorderless：drawable 即客户区真值（windowRect 可能残留假装饰）
          const drawW = borderless ? p3.drawableRect.width : size.width - decW3;
          const drawH = borderless ? p3.drawableRect.height : size.height - decH3;
          hilog.info(DOMAIN, TAG,
            'MainWindow changed: %{public}dx%{public}d (dec=%{public}d,%{public}d draw=%{public}dx%{public}d borderless=%{public}d)',
            size.width, size.height, decW3, decH3, drawW, drawH, borderless ? 1 : 0);
          // 忽略"创建阶段压缩反馈"（draw 恰 = 期望客户区 - dec），
          // 避免 FSize 临时变小导致首帧内容被拉伸（字体变长）。
          if (drawW === width - decW3 && drawH === height - decH3) {
            hilog.info(DOMAIN, TAG,
              'MainWindow skip creation-compressed feedback (%{public}dx%{public}d)', drawW, drawH);
            return;
          }
          fpbridge.onWindowResized(1, drawW, drawH);        // 反馈客户区
        });

        // ── 主窗口标题栏事件：关闭（CanClose 双向）、移动/最大化位置同步 ──
        // 点 X 拦截（v7）：resolve(true) 阻止窗口关闭有效（此前"系统销毁"
        // 实为 Timer→Hide 链所致：FWindow.Free → _ohos_destroy_window →
        // ETS destroyWindow(1) → terminateAbility；已改 SetWindowVisible(False)
        // 收起，不销毁）。拦截成功后 100ms Timer → minimize 收起，进程/托盘常驻。
        try {
          mainWin.on('windowWillClose', async (): Promise<boolean> => {
            const can: number = fpbridge.queryCanClose(1);
            hilog.info(DOMAIN, TAG,
              'MainWindow windowWillClose: canClose=%{public}d', can);
            return can === 0;   // true=阻止关闭（关闭到托盘）
          });
        } catch (_e) {}
        try {
          mainWin.on('windowEvent', (t: number) => {
            if (t === 7) {   // WINDOW_DESTROYED：主窗口被系统关闭 → 退出应用
              hilog.info(DOMAIN, TAG, 'MainWindow destroyed by system');
              fpbridge.onWindowClosed(1);
              terminateAbility();
            }
          });
        } catch (_e) {}
        try {
          mainWin.on('windowStatusChange', (status: window.WindowStatusType) => {
            hilog.info(DOMAIN, TAG,
              'MainWindow statusChange: %{public}d', status);
            fpbridge.updateWindowState(1, status);
          });
          hilog.info(DOMAIN, TAG, 'MainWindow statusChange registered');
        } catch (_e) {}
        try {
          mainWin.on('windowRectChange', (opts: window.RectChangeOptions) => {
            hilog.info(DOMAIN, TAG,
              'MainWindow rectChanged: left=%{public}d top=%{public}d w=%{public}d h=%{public}d',
              opts.rect.left, opts.rect.top, opts.rect.width, opts.rect.height);
            fpbridge.onWindowMoved(1, opts.rect.left, opts.rect.top);
          });
          hilog.info(DOMAIN, TAG, 'MainWindow rectChange registered');
        } catch (e) {
          const err = e as Error;
          hilog.warn(DOMAIN, TAG,
            'MainWindow rectChange register failed: msg=%{public}s',
            err.message || '');
        }
      }
      hilog.info(DOMAIN, TAG,
        'MainWindow setup: attrs=%{public}d fullscreen=%{public}d borderless=%{public}d size=%{public}dx%{public} pos=(%{public}d,%{public}d)',
        attrs, (attrs & ATTR_FULLSCREEN) !== 0 ? 1 : 0,
        (attrs & ATTR_BORDERLESS) !== 0 ? 1 : 0,
        width, height, posX, posY);
      // 位置同步统一 FpgSurface.PositionSync：主窗注册（150ms 轮询兜底，
      // windowRectChange 为即时通道），wnd.Left/Top 与系统实际一致是点击全局
      // 坐标基准正确的前提。
      registerWindowPositionSync(1, () => getMainWindow());
    } catch (err) {
      hilog.warn(DOMAIN, TAG,
        'MainWindow setup failed: code=%{public}d msg=%{public}s',
        err.code, err.message || '');
    }
  }

  private async createSubWin(reqId: number, xcId: string,
      width: number, height: number, posX: number, posY: number,
      attrs: number, wtype: number, winTitle: string): Promise<boolean> {
    hilog.info(DOMAIN, TAG, 'createSubWin reqId=%{public}d,scid=%{public}s %{public}d %{public}d %{public}d %{public}d attrs=%{public}d type=%{public}d title=%{public}s',reqId,xcId,posX,posY,width,height,attrs,wtype,winTitle);
    const ws = getWindowStage();
    if (ws === null) return false;

    // fpGUI TWindowAttributes：waFullScreen=bit3(1<<3)，waBorderless=bit4(1<<4)
    const ATTR_FULLSCREEN = 1 << 3;
    const ATTR_BORDERLESS = 1 << 4;
    const hasFS = (attrs & ATTR_FULLSCREEN) !== 0;
    const hasBL = (attrs & ATTR_BORDERLESS) !== 0;
    // fpGUI TWindowType：0=wtChild, 1=wtWindow, 2=wtModalForm, 3=wtPopup
    // 弹出菜单/下拉（wtPopup）恒无标题栏；wtWindow/wtModalForm 按 waBorderless
    const isPopup = (wtype === 3);
    let decorEnabled = isPopup ? false : !hasBL;
    // fpGUI 期望系统装饰（非 popup 非 borderless）：legacy 回退丢装饰时
    // 用自绘标题栏（FpgSurface）替代——平时隐藏，需要时按主窗标题栏高展示。
    const wantedDecor = !isPopup && !hasBL;

    const winName: string = 'fpg_win_' + reqId;

    try {
      // 创建时预估装饰高度：系统标题栏与主窗口同源（decH≈70px），总尺寸 = 客户区 + dec。
      // 否则首帧 drawable=客户区-dec（压缩），二次校正才展开 → 视觉"拉长"（=dec 高度）。
      let createH = height;
      if (decorEnabled) {
        const estDecVp = AppStorage.get<number>('decH_1');
        if (estDecVp && estDecVp > 0) {
          const estDecPx = Math.round(estDecVp *
            display.getDefaultDisplaySync().densityPixels);
          createH = height + estDecPx;
        }
      }
      // API 20 的 SubWindowOptions 支持 windowRect（since 18）→ 恢复初始定位；
      // 创建失败时回退旧 API createSubWindow（无 options，位置由后续 move/resize 设定）
      let win: window.Window;
      /*try {
        win = await ws.createSubWindowWithOptions(winName, {
          title: (winTitle && winTitle.length > 0) ? winTitle : 'fpGUI',
          windowRect: { left: posX, top: posY, width: width, height: createH },
          decorEnabled: decorEnabled
        });
        hilog.info(DOMAIN, TAG, 'createSubWindowWithOptions OK (req=%{public}d)', reqId);
      } catch (e1) {
        hilog.warn(DOMAIN, TAG, 'createSubWindowWithOptions failed req=%{public}d: %{public}s -> legacy createSubWindow',
          reqId, JSON.stringify(e1));
        if (decorEnabled) {
          try {
            win = await Promise.race([
              ws.createSubWindowWithOptions(winName, { title: (winTitle && winTitle.length > 0) ? winTitle : 'fpGUI', decorEnabled: true }),
              // HarmonyOS：OK；OpenHarmony：1300002 或 3s 超时 → 走 catch
              new Promise<never>((_, rej) => setTimeout(() => rej(new Error('createSubWindowWithOptions timeout')), 3000))
            ]);
          } catch (e) {
            win = await ws.createSubWindow(winName);   // legacy 兜底（无装饰）
            decorEnabled = false;   // legacy 无装饰：后续 createH/二次校正估算/dec 存储按无装饰处理
          }
        } else {
          win = await ws.createSubWindow(winName);
          decorEnabled = false;
        }
        hilog.info(DOMAIN, TAG, 'legacy createSubWindow OK (req=%{public}d)', reqId);
      }*/
      win = await ws.createSubWindow(winName);  //有些版本有标题栏&有些又没有，都自绘吧~
      decorEnabled = false;
      /*/ 自绘标题栏判定：期望装饰但实际无装饰（OpenHarmony legacy 回退路径）
      const titleBar = wantedDecor && !decorEnabled;
      hilog.info(DOMAIN, TAG,
        'createSubWindow decor=%{public}d (popup=%{public}d) createH=%{public}d (est. dec from main)',
        decorEnabled ? 1 : 0, isPopup ? 1 : 0, createH);*/

      // Establish large viewport first, then calculate decoration offset
      //await win.resize(999, 999);
      //await win.setWindowFocusable(true);
      // #1 并行化无依赖 await：圆角/可聚焦与 resize 互不依赖（圆角只改圆角，聚焦只改
      //   焦点能力，resize 只改尺寸），且此时窗口尚未 showWindow → 无可见瞬态。合并到
      //   Promise.all 一次 IPC 批次，省 2 次串行往返（原 cornerRadius→resize→focusable 三串）。
      //   注意 moveWindowTo 不并入：resize 经验上会漂移窗口位置，move 须在 resize 之后
      //   校正位置（参见二次校正块），并行会丢位置。
      const cornerRadiusTask: Promise<void> = (async () => {
        try {
          await win.setWindowCornerRadius(isPopup ? 0 : 8);  // popup=直角，普通=8 圆角
        } catch (_e) {
          // 旧版本 API 不支持，忽略
        }
      })();
      const props = win.getWindowProperties();
      // 子窗 windowId 上报（per-window 光标切换）；销毁时清除（setWindowPointerId(reqId, 0)）
      try {
        this.winPointerIds.set(reqId, props.id);
      } catch (_e) {}
      const decW = props.windowRect.width - props.drawableRect.width;
      const decH = props.windowRect.height - props.drawableRect.height;
      // 自绘标题栏判定：期望装饰但实际无装饰（OpenHarmony legacy 回退路径）
      const titleBar = wantedDecor && (!decorEnabled /*|| (decH===0)*/);
      // 单位：width/height 与 resize/windowRect 均为 px（C++ 透传的 Pascal 逻辑 px
      // 与 OHOS px 1:1）→ dec 直接用 px 原值补偿（勿 ÷density）
      const densityPx: number = display.getDefaultDisplaySync().densityPixels;

      // 自绘标题栏：高度=主窗标题栏高（decH_1 vp，兜底 32）；窗口总高=客户区+标题栏
      let titleBarVp = 0;
      let titleBarPx = 0;
      if (titleBar) {
        titleBarVp = AppStorage.get<number>('decH_1') ?? 32;
        if (titleBarVp < 10) titleBarVp = 32;
        titleBarPx = Math.round(titleBarVp * densityPx);
        hilog.info(DOMAIN, TAG,
          'TitleBar for sub-window %d: h=%{public}dvp (%{public}dpx)',
          reqId, titleBarVp, titleBarPx);
      }

      const totalW = width + decW;
      const totalH = height + decH + titleBarPx;
      // #2 去冗余 resize：windowRect 已含正确总尺寸时跳过（popup/borderless 常命中：
      //   dec=0 → totalW=width, totalH=height，与创建 windowRect 一致）。每省一次
      //   IPC 往返约 20-50ms。装饰窗 dec≠0 时 totalW≠width → 不命中 → 正常 resize。
      const needResize = props.windowRect.width !== totalW || props.windowRect.height !== totalH;
      const resizeTask: Promise<void> = needResize
        ? win.resize(totalW, totalH)
        : Promise.resolve();
      const focusableTask: Promise<void> = win.setWindowFocusable(true);
      hilog.info(DOMAIN, TAG,
        'createSubWin parallel batch (req=%{public}d): cornerRadius+focusable+resize (resize %{public}s)',
        reqId, needResize ? 'applied' : 'skipped(already matches)');
      await Promise.all([cornerRadiusTask, focusableTask, resizeTask]);

      // 全屏/最大化（SDK 12 子窗口 maximize 默认不支持，可能 Unauthorized →
      // try-catch 退化；SDK 17+ 需创建时 maximizeSupported:true）
      if (hasFS) {
        try { await win.maximize(); } catch (_e) {}
        if (hasBL) {
          try { await win.setWindowLayoutFullScreen(true); } catch (_e) {}
        }
      }

      // 标题栏高度（触摸补偿用）：统一存 AppStorage('decH_' + reqId)。
      // 注意单位：触摸坐标 displayX/Y 为 vp → 存 vp 值（÷densityPixels）
      AppStorage.setOrCreate<number>('decH_' + reqId, decH / densityPx);
      // 左边框 vp（左右对称 decW/2）：子窗 X 方向触摸补偿（与主窗 decW_1 同语义）
      AppStorage.setOrCreate<number>('decW_' + reqId, decW / 2 / densityPx);
      // 期望客户区尺寸（px）：WindowSurface/FpgSurface 首帧显示门用——
      // 创建阶段 drawable=客户区-dec（压缩），area 达到客户区后再显示内容，
      // 消除"拉长"（=dec 高度的压缩→展开瞬态）
      AppStorage.setOrCreate<number>('winClientW_' + reqId, width);
      AppStorage.setOrCreate<number>('winClientH_' + reqId, height);
      // 上报 C++（Pascal 弹窗定位补偿，per-window）：逻辑值（÷densityPx）
      fpbridge.setWindowDec(reqId, Math.round(decW / densityPx), Math.round(decH / densityPx));

      // ── 自绘标题栏存储（FpgSurface aboutToAppear 读取，须在 setUIContent 之前）──
      // 仅"期望装饰但创建失败（OpenHarmony legacy 回退）"时开启；HarmonyOS
      // 成功路径自带系统标题栏不开启。decH/decW 仍存真实装饰值（原补偿路线不变），
      // 标题栏高由 FpgSurface 在补偿基础上附加。winTitle/winHandle 供标题/关闭/拖动。
      if (titleBar) {
        AppStorage.setOrCreate<number>('titleBar_' + reqId, 1);
        AppStorage.setOrCreate<string>('winTitle_' + reqId,
          (winTitle && winTitle.length > 0) ? winTitle : 'fpGUI');
        AppStorage.setOrCreate<window.Window>('winHandle_' + reqId, win);
        // 自绘标题栏高（vp）上报 C++ g_winDec → Pascal 懒查询 FDecTop →
        // DoWindowToScreen 菜单/弹窗锚点补偿（系统装饰=0，标题栏=32vp，否则
        // 弹出位置偏上=标题栏高）。与系统装饰同一单位（vp）。
        fpbridge.setWindowDec(reqId, 0, Math.round(titleBarVp));
      }

      AppStorage.setOrCreate<number>('currentReqId', reqId);

      // #2 去冗余 move：resize 完成后重取 windowRect，位置已为目标值时跳过 moveWindowTo。
      //   注意须在 resize 之后取位置（resize 经验上会漂移窗口位置），故 move 未并入上方
      //   Promise.all，保持串行在 resize 完成后按真实位置决定是否校正。
      if (posX !== 0 || posY !== 0) {
        const postRect = win.getWindowProperties().windowRect;
        if (postRect.left !== posX || postRect.top !== posY) {
          await win.moveWindowTo(posX, posY);
        } else {
          hilog.info(DOMAIN, TAG,
            'createSubWin move skipped (req=%{public}d): already at (%{public}d,%{public}d)',
            reqId, posX, posY);
        }
      }
      // ── 先加载页面再 showWindow：页面在窗口隐藏时加载，showWindow 时
      // FpgSurface Stack 背景 '#F1F3F5' 已就绪 → 消除黑屏闪现。
      // surface 初始可能为压缩态，由 contentReady 门 + setXComponentSurfaceRect +
      // refreshWindow 机制在 2nd-pass resize 后自动校正。
      hilog.info(DOMAIN, TAG, 'setUIContent before showWindow (anti black-flash)');
      await win.setUIContent('pages/WindowSurface');
      // 窗口背景色兜底（部分版本 setUIContent 后才生效）
      try { win.setWindowBackgroundColor('#00000000'); } catch (_e) {}
      await win.showWindow();

      // ── 窗口可见后二次校正尺寸 ──
      // 部分版本在窗口未显示时 resize 不生效（创建 windowRect=客户区值被当总尺寸，
      // 内容区=客户区-dec 被压缩）。显示后重算实际装饰并 resize 到 客户区+dec。
      {
        const props2 = win.getWindowProperties();
        // drawable 未就绪（0x0）时 dec 不可计算——不能把 windowRect 全值当 dec
        // （否则 total=客户区+dec 变成 2× 尺寸：窗口 2 倍 + 内容只画左上 1/4）
        let decW2 = props2.drawableRect.width > 0
          ? props2.windowRect.width - props2.drawableRect.width : 0;
        let decH2 = props2.drawableRect.height > 0
          ? props2.windowRect.height - props2.drawableRect.height : 0;
        // showWindow 后 windowRect 可能仍=0x0（页面布局未完成），
        // dec 信息无效（dec=0）→ 二次校正 resize 会漏加 dec → drawable=客户区-dec
        // （压缩）→ buffer 偏小 → "拉高"。用主窗口标题栏高（decH_1，同源系统
        // 标题栏）预估，使 resize 总尺寸=客户区+dec。
        if (decorEnabled && (decH2 <= 0 || props2.windowRect.width <= 0)) {
          const estDecVp = AppStorage.get<number>('decH_1');
          if (estDecVp && estDecVp > 0) {
            const estDecPx = Math.round(estDecVp * densityPx);
            if (decH2 <= 0) decH2 = estDecPx;
            hilog.info(DOMAIN, TAG,
              'Sub-window %{public}d dec unavailable (winRect=%{public}dx%{public}d), est decH=%{public}dpx from main',
              reqId, props2.windowRect.width, props2.windowRect.height, estDecPx);
          }
        }
        hilog.info(DOMAIN, TAG,
          'Sub-window %{public}d shown: windowRect=%{public}dx%{public}d drawable=%{public}dx%{public}d dec=%{public}d,%{public}d expect client=%{public}dx%{public}d',
          reqId, props2.windowRect.width, props2.windowRect.height,
          props2.drawableRect.width, props2.drawableRect.height,
          decW2, decH2, width, height);
        const totalW2 = width + decW2;
        let totalH2 = height + decH2;
        if (titleBar) totalH2 += titleBarPx;   // 自绘标题栏计入窗口总高（系统 dec=0）
        if (props2.windowRect.width !== totalW2 ||
            props2.windowRect.height !== totalH2 ||
            props2.drawableRect.width !== width ||
            props2.drawableRect.height !== height) {
          await win.resize(totalW2, totalH2);
          hilog.info(DOMAIN, TAG,
            'Sub-window %d corrected: resize to %{public}dx%{public}d', reqId, totalW2, totalH2);
          // resize 可能改变窗口位置 → 重新定位（保持弹窗/菜单在正确屏幕位置）
          if (posX !== 0 || posY !== 0) {
            try { await win.moveWindowTo(posX, posY); } catch (_e) {}
          }
          // 装饰值若有变化，更新存储（触摸 vp）与 C++（定位逻辑值）
          // （原补偿路线不变：decH/decW 恒存真实装饰值）
          AppStorage.setOrCreate<number>('decH_' + reqId, decH2 / densityPx);
          AppStorage.setOrCreate<number>('decW_' + reqId, decW2 / 2 / densityPx);
          // titleBar 窗口：自绘标题栏高（vp）已在上方 titleBar 块上报，
          // 这里只报真实系统装饰（borderless=0）会把它覆盖成 0 → Pascal
          // DoWindowToScreen 菜单锚点漏补偿（偏上=标题栏高）。特判跳过。
          if (!titleBar) {
            fpbridge.setWindowDec(reqId, Math.round(decW2 / densityPx), Math.round(decH2 / densityPx));
          }
        }
      }

      // ── 内容已在上文 showWindow 之前加载（防黑屏），此处直接注册事件 ──
      hilog.info(DOMAIN, TAG, 'try on windowSizeChange');
      try {
        win.on('windowSizeChange', (size: window.Size) => {
          // 去重：部分系统在纯移动（位置变化、尺寸不变）时也回调本事件，
          // 若不过滤会触发多余的 SET_BUFFER_GEOMETRY+重绘+提交 → 拖动花屏。
          const last = this.lastSubSize.get(reqId);
          if (last && last[0] === size.width && last[1] === size.height) {
            return;
          }
          this.lastSubSize.set(reqId, [size.width, size.height]);
          // 窗口销毁流程中系统仍可能触发本回调，此时 getWindowProperties
          // 抛 1300002（window state abnormal）→ 必须整段兜底，否则 jscrash。
          let props: window.WindowProperties;
          try {
            props = win.getWindowProperties();
          } catch (_e) {
            hilog.info(DOMAIN, TAG, 'windowSizeChange skip: window %{public}d state abnormal', reqId);
            return;
          }
          const decW = props.windowRect.width - props.drawableRect.width;
          const decH = props.windowRect.height - props.drawableRect.height;
          // 统一更新触摸补偿存储（现算 windowRect−drawable，任何装饰状态收敛真实值）：
          // 与主窗对齐——legacy 无装饰（dec=0）/估算残留/补装饰变化均在此收敛。
          // （原补偿路线不变：decH/decW 恒存真实装饰值；自绘标题栏高由 FpgSurface 附加）
          AppStorage.setOrCreate<number>('decH_' + reqId, decH / densityPx);
          AppStorage.setOrCreate<number>('decW_' + reqId, decW / 2 / densityPx);

          // 修：HarmonyOS 主窗走 createSubWin（reqId=1）时，创建初期 getWindowProperties
          // 返回 0x0（未布局）→ 上面上报 g_winDec[1]={0,0} 而重报路径（二次校正/
          // decorHeight 校准）条件均不满足 → Pascal 弹窗定位（DoWindowToScreen）拿 0
          // → 菜单/弹窗整体偏上=标题栏高。用 decH_1（触摸同源，windowRect 无效时由
          // 主窗标题栏预估，已证实有值）兜底补报。
          // 注意：OH legacy 主窗（titleBar=true, :488 已报 32）windowRect=drawable→dec=0，
          // 必须跳过，否则把 :488 的自绘标题栏 32 覆盖成 0 → OH 回归。
          if (reqId === 1 && (decW > 0 || decH > 0)) {
            try { fpbridge.setWindowDec(1, Math.round(decW / densityPx), Math.round(decH / densityPx)); } catch (_e) {}
          }

          // 标题栏高度校准：windowSizeChange（内容加载+布局完成）后 getWindowDecorHeight
          // 才准确（vp）。与存储的 decH 不一致时更新触摸补偿/定位补偿/上报 C++。
          // 自绘标题栏窗口跳过（无系统装饰，校准会把 decH 归 0 并错误 resize 回退）。
          if (!titleBar) {
            try {
            const decHReal = win.getWindowDecorHeight();   // vp
            const stored = AppStorage.get<number>('decH_' + reqId) ?? 0;
            if (decHReal > 0 && Math.abs(decHReal - stored) > 1) {
              AppStorage.setOrCreate<number>('decH_' + reqId, decHReal);
              AppStorage.setOrCreate<number>('decW_' + reqId, decW / 2 / densityPx);
              fpbridge.setWindowDec(reqId, Math.round(decW / densityPx), Math.round(decHReal));
              hilog.info(DOMAIN, TAG,
                'Window %d decH calibrated: %{public}d -> %{public}d vp (decorHeight API, diff=%{public}dpx)',
                reqId, stored, decHReal, decH);
              // 按新标题栏高重新设置窗口总尺寸（总=客户区+新dec），
              // 否则旧 decH 算出的总高导致 drawable≠客户区（内容偏差）
              const newDecHpx = Math.round(decHReal * densityPx);
              const newTotalW = width + decW;
              const newTotalH = height + newDecHpx;
              win.resize(newTotalW, newTotalH).then(() => {
                hilog.info(DOMAIN, TAG,
                  'Window %{public}d resized by decH calibration: total=%{public}dx%{public}d (client=%{public}dx%{public}d dec=%{public}dpx)',
                  reqId, newTotalW, newTotalH, width, height, newDecHpx);
              }).catch(() => {});
            }
          } catch (_e) {}
            }
          const drawW = size.width - decW;
          let drawH = size.height - decH;
          // 自绘标题栏：窗口总高含标题栏，上报 Pascal 的客户区须减标题栏高
          // （否则 Pascal 布局=总高，内容被标题栏遮挡/压缩）
          if (titleBar) drawH -= titleBarPx;
          hilog.info(DOMAIN, TAG,
            'Window %d changed: %{public}dx%{public}d (dec=%{public}d,%{public}d draw=%{public}dx%{public}d)',
            reqId, size.width, size.height, decW, decH, drawW, drawH);
          // 忽略"创建阶段压缩反馈"：初始 windowRect=客户区被当总尺寸时
          // drawable=客户区-dec（偏小），若反馈给 Pascal → FSize 临时变小 →
          // 首帧缓冲过小被拉伸（字体变长）。特征：draw 恰 = 期望客户区 - dec。
          if (drawW === width - decW && drawH === height - decH) {
            hilog.info(DOMAIN, TAG,
              'Window %{public}d skip creation-compressed feedback (%{public}dx%{public}d)', reqId, drawW, drawH);
            return;
          }
          fpbridge.onWindowResized(reqId, drawW, drawH);
        });
      } catch (_e) {}

      // ── 标题栏事件：关闭（CanClose 双向）、移动/最大化位置同步 ──
      try {
        win.on('windowWillClose', async (): Promise<boolean> => {
          const can: number = fpbridge.queryCanClose(reqId);
          hilog.info(DOMAIN, TAG,
            'Window %{public}d windowWillClose: canClose=%{public}d', reqId, can);
          return can === 0;   // true=阻止关闭（CanClose=false 时窗口保持）
        });
      } catch (_e) {}
      try {
        win.on('windowEvent', (t: number) => {
          if (t === 7) {   // WINDOW_DESTROYED：窗口已被系统销毁
            hilog.info(DOMAIN, TAG, 'Window %{public}d destroyed by system', reqId);
            fpbridge.onWindowClosed(reqId);
            try {
              this.winPointerIds.delete(reqId);
            } catch (_e) {}
            // 清理自绘标题栏存储（句柄/标志，防复用错配）
            AppStorage.delete('titleBar_' + reqId);
            AppStorage.delete('winTitle_' + reqId);
            AppStorage.delete('winHandle_' + reqId);
            unregisterWindowPositionSync(reqId);
            this.subWinMap.delete(reqId);
            this.lastSubSize.delete(reqId);
          }
        });
      } catch (_e) {}
      try {
        win.on('windowRectChange', (opts: window.RectChangeOptions) => {
          fpbridge.onWindowMoved(reqId, opts.rect.left, opts.rect.top);
        });
      } catch (_e) {}
      try {
        win.on('windowStatusChange', (status: window.WindowStatusType) => {
          fpbridge.updateWindowState(reqId, status);
        });
      } catch (_e) {}

      hilog.info(DOMAIN, TAG,
        'Sub-window %{public}d created: %{public}dx%{public}d at (%{public}d,%{public}d) xcId=%{public}s',
        reqId, width, height, posX, posY, xcId);
      this.subWinMap.set(reqId, win);
      // 位置同步（FpgSurface.PositionSync）：子窗位置变化（输入法避让/系统移动）实时上报 Pascal
      registerWindowPositionSync(reqId, () => this.subWinMap.get(reqId));
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG,
        'createSubWin failed for req %{public}d: code=%{public}d msg=%{public}s',
        reqId, err.code, err.message || '');
      return false;
    }
  }

  private async createWindowFromNative(reqId: number, xcId: string,
      width: number, height: number, posX: number, posY: number,
      attrs: number, wtype: number, surfaceId: string, title: string): Promise<void> {
      hilog.info(DOMAIN, TAG, 'createWindowFromNative scid=%{public}s %{public}d %{public}d %{public}d %{public}d attrs=%{public}d type=%{public}d title=%{public}s',xcId,posX,posY,width,height,attrs,wtype,title);
      // 主窗口（reqId=1）：Ability 窗口尺寸/位置/全屏控制；
      // 渲染 surface 由 build() 中固定的 XComponent（xc_fpg_1）提供。
      if (reqId === 1) {
        // 首帧显示门（仅标准窗口模式）：Pascal 在 OnSurfaceReady 后立即 PutBuf
        // 期望尺寸 buffer，但 XComponent surface 还停在默认窗口尺寸 → 右/下黑边。
        // 设期望客户区 → surface resize 到位后 FpgSurface 放行并 refreshWindow
        // 强制 Pascal 重绘（buffer 重建=surface）。全屏/最大化 surface=全屏≠期望，
        // 不设门（保持直显，windowSizeChange 反馈驱动重绘）。
        const isFullScreen = (attrs & 8) !== 0;   // waFullScreen=1<<3
        if (!isFullScreen && this.imeCtrl.setExpectClientSize) {
          this.imeCtrl.setExpectClientSize(width, height);
        }
        // 主窗期望客户区（px）走 AppStorage（与子窗同通道）：FpgSurface aboutToAppear
        // 时 ctrl.setExpectClientSize 回调尚未注册（组件在 mainReady=true 后才创建），
        // 直接读存储固定 XComponent 尺寸=期望 → surface=buffer 无拉伸（点击精确）。
        // 全屏/最大化无期望（不存）→ 保持 100% 直显。
        if (!isFullScreen) {
          AppStorage.setOrCreate<number>('winClientW_' + reqId, width);
          AppStorage.setOrCreate<number>('winClientH_' + reqId, height);
        }
        // 主窗顶部屏幕偏移（状态栏+posY）→ 鼠标坐标补偿用（设备 displayY 为屏幕坐标）
        AppStorage.setOrCreate<number>('mainPosY', posY);
        await this.setupMainWindow(width, height, posX, posY, attrs, title);
        // ── 系统窗口尺寸限制钳制校正 ────────────────────────────
        // 自由窗口最小宽 320vp：Pascal 请求 300vp(570px) 被系统钳到 608px。
        // 若期望客户区仍按请求值 570 存储，FpgSurface 首帧显示门
        // matchCurrent() 永不成立（|608-570|=38>2），且：
        //   - setExpectClientSize 的 2500ms 兜底未布防（回调在组件创建前调用，
        //     Index.ets:995 跳过——见 :998-999 注释）；
        //   - onAreaChange 的 2000ms 兜底仅在面积变化事件内求值，窗口稳定后不触发；
        // → contentReady 永假 → XComponent opacity≈0 → 窗口空白，
        //   必须拖动触发超时兜底才显示（animation demo 空白根因）。
        // 校正为实际 drawable：门在首帧即放行；并反馈 Pascal 真实客户区，
        // buffer 重设 608x475 与 surface 1:1（与拖动 resize 同路径，已验证安全）。
        if (!isFullScreen) {
          try {
            const mw = getMainWindow();
            if (mw !== null) {
              const dr = mw.getWindowProperties().drawableRect;
              if (Math.abs(dr.width - width) > 2 || Math.abs(dr.height - height) > 2) {
                AppStorage.setOrCreate<number>('winClientW_' + reqId, dr.width);
                AppStorage.setOrCreate<number>('winClientH_' + reqId, dr.height);
                hilog.info(DOMAIN, TAG,
                  'createWindow expect corrected by window limits: request=%{public}dx%{public}d actual=%{public}dx%{public}d',
                  width, height, dr.width, dr.height);
                fpbridge.onWindowResized(reqId, dr.width, dr.height);
              }
            }
          } catch (_e) {}
        }
        // 窗口尺寸已到位 → 创建主窗 XComponent（onLoad 上报 surface 时=期望客户区）
        this.mainReady = true;
        // 注册隐藏 TextInput 焦点恢复回调（子窗关闭后恢复主窗键盘焦点）
        this.imeCtrl.focusHiddenInput = (): void => {
          this.focusHiddenInput();
        };
        // 延迟聚焦隐藏 TextInput（等 build 完成后生效）
        setTimeout(() => {
          this.focusHiddenInput();
        }, 200);
        return;
      }

      // 其它窗口：系统子窗口（createSubWindowWithOptions，独立窗口/系统标题栏）
      if (!(await this.createSubWin(reqId, xcId, width, height, posX, posY, attrs, wtype, title))) {
        hilog.warn(DOMAIN, TAG,
          'createSubWin failed for req %{public}d (no fallback inline window)', reqId);
      }
  }

  private async destroyWindow(reqId: number): Promise<void> {
    // 清除 per-window 光标 id（防句柄复用错配）
    try {
      this.winPointerIds.delete(reqId);
    } catch (_e) {}
    unregisterWindowPositionSync(reqId);
    // 清理自绘标题栏存储（句柄/标志，防复用错配）
    AppStorage.delete('titleBar_' + reqId);
    AppStorage.delete('winTitle_' + reqId);
    AppStorage.delete('winHandle_' + reqId);
    const subWin = this.subWinMap.get(reqId);
    if (subWin !== undefined) {
      this.subWinMap.delete(reqId);
      this.lastSubSize.delete(reqId);
      // 注销标题栏事件监听（避免泄漏/重复触发）
      try { subWin.off('windowWillClose'); } catch (_e) {}
      try { subWin.off('windowEvent'); } catch (_e) {}
      try { subWin.off('windowRectChange'); } catch (_e) {}
      try { await subWin.destroyWindow(); } catch (_e) {}
      hilog.info(DOMAIN, TAG, 'Sub-window %d destroyed', reqId);
      if (reqId === 1) {
        // 诊断：主窗销毁→终止应用（黑底未绘/弹菜单切换期闪退排查：确认谁触发）
        hilog.warn(DOMAIN, TAG, 'destroyWindow MAIN -> terminateAbility (req=1)');
        terminateAbility();
      }
      else {
        // 子窗口销毁后恢复主窗口焦点（键盘事件继续路由到主窗口）
        try { if (this.imeCtrl.focus) this.imeCtrl.focus(); } catch (_e) {}
      }
      return;
    }
    // 主窗口：无 subWin 记录（页面内固定 XComponent），直接结束 Ability
    if (reqId === 1) terminateAbility();
  }

  // 调整窗口尺寸：fpGUI 传的是客户区尺寸（不含标题栏/边框）。
  // 仅系统子窗口：win.resize(客户区 + 装饰 dec)（含标题栏补偿）
  private async resizeWindow(reqId: number, w: number, h: number): Promise<void> {
    const win = this.subWinMap.get(reqId);
    if (win !== undefined) {
      try {
        const props = win.getWindowProperties();
        const decW = props.windowRect.width - props.drawableRect.width;
        const decH = props.windowRect.height - props.drawableRect.height;
        // w/h 与 resize 均为 px（C++ 透传的 Pascal 逻辑 px 与 OHOS px 1:1）
        // → dec 直接用 px 原值补偿（勿 ÷density）。
        // 自绘标题栏窗口：系统 dec=0，但窗口总高仍含标题栏 → 加上 titleBarPx。
        // 注意 decH_1 可能为 0（主窗 borderless 无标题栏时存储为 0）→ <10 兜底 32
        let titleBarPx = 0;
        try {
          if ((AppStorage.get<number>('titleBar_' + reqId) ?? 0) === 1) {
            let titleBarVp: number = AppStorage.get<number>('decH_1') ?? 32;
            if (titleBarVp < 10) titleBarVp = 32;
            titleBarPx = Math.round(titleBarVp * display.getDefaultDisplaySync().densityPixels);
          }
        } catch (_e) {}
        await win.resize(w + decW, h + decH + titleBarPx);   // 客户区 + 系统装饰(px)
        hilog.info(DOMAIN, TAG,
          'Resize sub-window %d: client=%dx%d total=%dx%d',
          reqId, w, h, w + decW, h + decH);
      } catch (_e) {}
    }
  }

  private async moveWindow(reqId: number, x: number, y: number): Promise<void> {
    const win = this.subWinMap.get(reqId);
    if (win !== undefined) {
      try { await win.moveWindowTo(x, y); } catch (_e) {}
    }
  }

  private async showWindow(reqId: number): Promise<void> {
    // 主窗口（Ability 窗口）不在 subWinMap：直接操作 getMainWindow
    if (reqId === 1) {
      const mainWin = getMainWindow();
      if (mainWin !== null) {
        try { await mainWin.showWindow(); } catch (_e) {}
      }
      // 恢复后确保主窗 XComponent 系统键盘焦点（托盘收起/恢复后焦点丢失，
      // onKeyEvent 不触发 → 键盘无效；FpgSurface 交互即聚焦为兜底）
      try { if (this.imeCtrl.focus) this.imeCtrl.focus(); } catch (_e) {}
      return;
    }
    const win = this.subWinMap.get(reqId);
    if (win !== undefined) {
      try { await win.showWindow(); } catch (_e) {}
    }
  }

  private async hideWindow(reqId: number): Promise<void> {
    // 主窗口（Ability 窗口）不在 subWinMap：直接操作 getMainWindow。
    // 注：API 20 的 Window 无 hide()；托盘收起走 minimize（配合托盘唤醒，
    // 窗口不销毁，恢复走 showWindow(1)）。
    if (reqId === 1) {
      const mainWin = getMainWindow();
      if (mainWin !== null) {
        try { await mainWin.minimize(); } catch (_e) {}
      }
      return;
    }
    const win = this.subWinMap.get(reqId);
    if (win !== undefined) {
      try { await win.minimize(); } catch (_e) {}
    }
  }

  private async shakeWindow(reqId: number): Promise<void> {
    // 节流：鼠标悬停/拖动在模态外会高频触发 DROPPED → 连续 shake 互相打断，
    // 动画永远走不完（看不到抖动）。500ms（>一次完整序列时长）内只执行一次。
    const now = Date.now();
    if (now - this.lastShakeAt < 500) return;
    this.lastShakeAt = now;
    hilog.info(DOMAIN, TAG, 'shakeWindow: reqId=%d (modal feedback)', reqId);
    const win = this.subWinMap.get(reqId);
    if (win !== undefined) {
      try {
        const p: window.WindowProperties = win.getWindowProperties();
        const x0 = p.windowRect.left;
        const y0 = p.windowRect.top;
        hilog.info(DOMAIN, TAG, 'shakeWindow: pos=(%d,%d) -> move ±8', x0, y0);
        // 整窗左右快速位移（比 resize 宽度的视觉反馈明显）。moveWindowTo 不 await
        // （连续 await 可能被系统异步状态卡住导致序列中断、位置停在中间值），
        // 用固定间隔让系统渲染出每帧；末尾显式复位 + 位置校验。
        const sleep = (ms: number) => new Promise<void>(r => setTimeout(r, ms));
        for (let i = 0; i < 3; i++) {
          win.moveWindowTo(x0 + 8, y0).catch(() => {});
          await sleep(70);
          win.moveWindowTo(x0 - 8, y0).catch(() => {});
          await sleep(70);
        }
        win.moveWindowTo(x0, y0).catch(() => {});
        await sleep(90);
        try {
          const p2: window.WindowProperties = win.getWindowProperties();
          if (p2.windowRect.left !== x0 || p2.windowRect.top !== y0) {
            hilog.info(DOMAIN, TAG, 'shakeWindow: restore check pos=(%d,%d)', p2.windowRect.left, p2.windowRect.top);
            win.moveWindowTo(x0, y0).catch(() => {});
          }
        } catch (_e) {}
        win.showWindow().catch(() => {});

        // 模态窗 Z 序置顶：HO 子窗口点击被 OS 自动 raise，会盖住模态窗
        // （OH legacy 无此行为→零回归）。抖动完显式压回最前。
        //win.setLevelOrder(LevelOrder.clamp(100000));
        win.setWindowFocusable(true).catch(() => {});

        // 激活为焦点窗口：同应用内切换焦点（源=当前获焦的主窗，目标=模态窗口）。
        // 目标已 showWindow 且已加载内容；focusControl.requestFocus 无法跨窗口
        // 切系统焦点，必须用 window.shiftAppWindowFocus。
        try {
          const mainWin = getMainWindow();
          const srcId: number = mainWin ? mainWin.getWindowProperties().id : 0;
          const dstId: number = win.getWindowProperties().id;
          if (srcId > 0 && dstId > 0) {
            window.shiftAppWindowFocus(srcId, dstId).catch(() => {});
            hilog.info(DOMAIN, TAG, 'shakeWindow: focus shift %d -> %d', srcId, dstId);
          }
        } catch (_e) {}
      } catch (_e) {}
    }
  }

  // 聚焦隐藏 TextInput（子窗关闭后恢复主窗键盘焦点）
  private focusHiddenInput(): void {
    try {
      focusControl.requestFocus('hidden_digit_input');
    } catch (_e) {
      hilog.info(DOMAIN, TAG, 'focusHiddenInput: err');
    }
  }

  build() {
    // 背景色 = fpGUI OHOS 主题 clWindowBackground（$FFF0F2F5）：
    // FLOATING 主窗 resize 被系统 clamp（drawable 408x349 > 期望 400x300）时，
    // XComponent 固定期望尺寸后右/下多出的区域用同色填充，白条不可见。
    Stack() {
      // 主窗口渲染 surface（固定 reqId=1；XComponent/IME/事件转发全部在
      // 公共组件 FpgSurface 内；其它窗口由 createSubWin 创建系统子窗口）。
      // mainReady 延迟创建：窗口 resize 到期望尺寸后才渲染 XComponent，
      // 保证 surface（固定于创建时刻）尺寸=期望客户区 → 首帧无黑边。
      if (this.mainReady) {
        FpgSurface({ reqId: 1, ctrl: this.imeCtrl })
      }
      // ── 隐藏 TextInput：主窗 XComponent.onKeyEvent 不触发的兜底 ──
      // 物理键盘数字键被 HMKeyboard 消费（isConsumedKeyDown）→ 丢失；
      // 隐藏 TextInput 获焦后 HMKeyboard 将数字键直送其 onKeyEvent，
      // 转发至 fpbridge.onKeyEvent → EnqueueKeyEvent → ProcessQueuedKeyEvents。
      // 仅主窗（mainReady=true）时创建；弹出子窗 XComponent.onKeyEvent 正常，
      // 无需此兜底。
      if (this.mainReady) {
        TextInput({ text: '', placeholder: '', controller: this.hiddenInputCtrl })
          .id('hidden_digit_input')
          .type(InputType.Normal)
          .opacity(0)
          .fontSize(0)
          .width(0).height(0)
          .focusable(true)
          // 程序性获焦（focusHiddenInput）只作物理键捕获兜底，不绑输入法：
          // TextInput 自 API 10 起获焦默认弹软键盘 → 启动 200ms 后误弹。
          // 正式输入仍由 Pascal 焦点驱动 showIme 命令模式弹出。
          .enableKeyboardOnFocus(false)
          .onKeyEvent((event: KeyEvent): boolean => {
            const kc: number = event.keyCode as number;
            const isDown: boolean = (event.type as number) === 0;
            const act: number = isDown ? 0 : 1;
            // 修饰键追踪
            if (kc === 2047 || kc === 2048) this.hiShiftDown = isDown;
            else if (kc === 2072 || kc === 2073) this.hiCtrlDown = isDown;
            else if (kc === 2045 || kc === 2046) this.hiAltDown = isDown;
            else if (kc === 2076 || kc === 2077) this.hiMetaDown = isDown;
            const mods: number = (this.hiCtrlDown ? 1 : 0) | (this.hiShiftDown ? 2 : 0)
              | (this.hiAltDown ? 4 : 0) | (this.hiMetaDown ? 8 : 0);
            // 计算 unicode（字母/数字/符号）
            let uni: number = 0;
            if (kc >= 2000 && kc <= 2009) {
              uni = 48 + (kc - 2000);  // '0'-'9'
            } else if (kc >= 2017 && kc <= 2042) {
              const base: number = 'a'.charCodeAt(0) + (kc - 2017);
              uni = (mods & 2) !== 0 ? base - 32 : base;  // shift → 大写
            } else if (kc === 2050) {
              uni = 32;  // space
            } else if (kc === 2049) {
              uni = 9;   // tab
            } else if (kc === 2054) {
              uni = 13;  // enter
            }
            // Backspace/Delete：放行让 IME 路径处理（已有 deleteLeft/deleteRight 回调），
            // 避免双删（hidden TextInput 转发 + IME 回调双发）。
            if (kc === 2055 || kc === 2071) {
              return false;
            }
            // 所有其他键统一转发，不区分类型——TextInput 不处理任何东西（纯传 key 工具人）
            fpbridge.onKeyEvent(kc, act, mods, uni);
            return true;  // 消费：不让 TextInput 插入/处理任何东西
          })
          .onFocus(() => {
            hilog.info(DOMAIN, TAG, 'HiddenInput: focused');
          })
      }
    }
    .backgroundColor('#F0F2F5')
    .width('100%').height('100%')
  }
}
