import fpbridge from 'libfp_bridge.so';
import { window, display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { inputMethod } from '@kit.IMEKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hasPhysicalKeyboard } from './KeyboardDetector';
import { uniformTypeDescriptor, unifiedDataChannel } from '@kit.ArkData';

// ── 系统拖拽辅助类型 ──
interface DragPoint {
  x: number;
  y: number;
}

// getSummary → fpGUI mime 类型表项
interface MimeTypeEntry {
  utd: string;
  mime: string;
}

// summaryJson 载荷（Pascal LoadMimeTypesFromSummary 解析）
interface SummaryPayload {
  types: Array<MimeTypeEntry>;
}

// UnifiedRecord → recordsJson 项（Pascal SetDropDataFromRecords 解析）
interface DropRecord {
  type: string;
  textContent: string;
  abstract: string;
  htmlContent: string;
  uri: string;
}

const DOMAIN = 0x0000;
const TAG = 'fpGUI-Surface';

// ── 2in1/PC 设备判断 ──
// PC/2in1 有物理键盘：连接输入法（保中文输入）但不弹软键盘
// （showTextInput 会激活软键盘/输入法面板；物理键经输入法语言模式路由：
// 中文组合拼音、英文直通）。触屏设备（phone/无物理键盘）完整 showIme。
// 判定（运行时）：物理键盘检测（inputDevice）优先；deviceType 兜底。
//  注意：OpenHarmony 模拟器 deviceType 返回 'tablet'（BMSExt 兼容判定）——
//  不能仅按 '2in1' 判断，须结合物理键盘检测。
function isPcLike(): boolean {
  if (hasPhysicalKeyboard()) {
    return true;
  }
  const dt = deviceInfo.deviceType;
  return dt === '2in1' || dt === 'pc';
}

// ── 鼠标动作常量（真机运行时实测，HarmonyOS 6.x 平板）──
// Press=1(按下)/Release=2(抬起)/Move=3(移动)/Hover=4(悬浮)
// 注意：SDK d.ts 声明为 0 基（Press=0…），与设备运行时不一致；
// 以本组实测值为准，勿改。与 C++ napi_init.cpp 的 MOUSE_ACTION_* 语义一致。
const MOUSE_ACTION_PRESS = 1;   // 按下（Press/Down）
const MOUSE_ACTION_RELEASE = 2; // 抬起（Release/Up）
const MOUSE_ACTION_MOVE = 3;    // 移动（Move）
const MOUSE_ACTION_HOVER = 4;   // 悬浮（Hover）

// ── 输入通道开关 ──
// 鼠标/触控板（SourceType.Mouse）走 onMouse；手指/笔/未知来源走 onTouch
// （onTouch 内按来源分流）。INPUT_USE_ONMOUSE 仅控制 onMouse 通道开关，
// 不再抑制 onTouch。
const INPUT_USE_ONMOUSE = true;
// Move 微抖过滤状态（设备坐标微抖 → 菜单 hover 边界判定抖动 → 子菜单闪烁）
let gLastMouseX: number = -99999;
let gLastMouseY: number = -99999;

// ── 长按模拟右键（触屏无右键）──
// 按住 >= LONGPRESS_MS 且位移 < LONGPRESS_SLOP（vp，曼哈顿距离），
// 松手时先照常转发左键 Up（拖拽捕获释放/选择清理/点击都依赖它，绝不吞），
// 再补发右键 Down/Up：button=2 与 Pascal fpg_ohos.pas 的映射一致（2=Right）。
const LONGPRESS_MS: number = 500;
const LONGPRESS_SLOP: number = 20;

// ── 全局 IME 会话单例（InputMethodController 命令模式）──
// 冒烟测试确认：attach 无需 TextInput 组件，insertText/deleteLeft/
// deleteRight/moveCursor 命令回调直接驱动 fpGUI 编辑框（Pascal 按焦点
// 窗口路由）——彻底消除 TextInput 组件的第二套文本状态（混合流/重复
// 注入/删除方向错位）。回调与 attach 全局仅一次。
let gImeCtl: inputMethod.InputMethodController | null = null;
let gImeAttached: boolean = false;
let gImeType: number = -1;   // 当前 attach 的 TextInputType（变化时 reattach）
// 命令回调已注册标志：attach 成功后注册一次（提前注册不生效——insertText
// 回传丢失导致字母/中文无法录入；重复注册则监听叠加——输入字数递增）
let gImeListenersRegistered: boolean = false;
// 软键盘删除键双路径去重：IME deleteLeft/deleteRight 命令注入后，系统还会
// 把删除键作为物理键事件发来（KEYEV）→ 时间窗内丢弃对应 KEYEV，防双删
let gLastImeDeleteAt: number = 0;
let gLastImeDeleteKind: number = 0;   // 1=deleteLeft(Backspace) 2=deleteRight(Del)
// 符号/标点键双通道去重：这些键 IME 发 insertText 命令 + 系统同时发物理键
// 事件（KEYEV uni）→ 时间窗内丢弃匹配字符的 KEYEV，防双插（字母键实测单通道）
let gLastImeInsertAt: number = 0;
let gLastImeInsertText: string = '';
// hover 双通道自适应：onHoverMove 仅 SDK 15+ 系统触发；高版本系统上
// onMouse Move(3)(Buttons=0) 可能仍携带 hover → 收到 onHoverMove 后
// 500ms 内抑制 onMouse 的 hover Move（版本无关，低版本不受影响）
let gLastHoverMoveAt: number = 0;
// 滚轮去抖：onAxisEvent 滚轮一次滚动可能连续上报 BEGIN/UPDATE/END 多段
// AxisEvent（每段都带角度变化）→ 50ms 内只转发一次，防多段重复滚动
let gLastWheelAt: number = 0;

function imeEnsureAttached(kbType: number): void {
  try {
    if (gImeCtl === null) {
      gImeCtl = inputMethod.getController();
    }
    const wantType: number = (kbType === 2 || kbType === 3)
      ? inputMethod.TextInputType.NUMBER : inputMethod.TextInputType.TEXT;
    if (gImeAttached && gImeType === wantType) return;
    if (gImeAttached) {
      // 输入类型变化 → 结束旧会话后重新 attach
      gImeCtl.stopInputSession().catch(() => {});
      gImeAttached = false;
    }
    gImeCtl.attach(true, {
      inputAttribute: {
        textInputType: wantType,
        enterKeyType: inputMethod.EnterKeyType.UNSPECIFIED
      }
    }).then(() => {
      gImeAttached = true;
      gImeType = wantType;
      hilog.info(DOMAIN, TAG, 'IME attach OK type=%d', wantType);
      // 命令回调注册【attach 成功后、全局一次】：提前注册（attach 前）
      // 不生效——insertText 回传丢失（字母/中文无法录入）；重复注册
      // 则监听叠加（输入字数随 attach 次数递增）。注入目标由 Pascal
      // 焦点窗口路由，与 attach 无关。
      if (!gImeListenersRegistered) {
        gImeCtl!.on('insertText', (text: string) => {
          hilog.info(DOMAIN, TAG, 'IME insertText: [%{public}s]', text);
          try { fpbridge.onTextInput(text); } catch (_e) {}
          // 记录：符号/标点键双通道（insertText + KEYEV）→ sendKeyEvent 去重用
          gLastImeInsertAt = Date.now();
          gLastImeInsertText = text;
        });
        gImeCtl!.on('deleteLeft', (n: number) => {
          hilog.info(DOMAIN, TAG, 'IME deleteLeft: %d', n);
          try { fpbridge.onDeleteChars(n); } catch (_e) {}
          // 记录：软键盘退格后系统仍会发 Backspace 物理键事件 → 去重用
          gLastImeDeleteAt = Date.now();
          gLastImeDeleteKind = 1;
        });
        gImeCtl!.on('deleteRight', (n: number) => {
          hilog.info(DOMAIN, TAG, 'IME deleteRight: %d', n);
          try { fpbridge.onDeleteRightChars(n); } catch (_e) {}
          gLastImeDeleteAt = Date.now();
          gLastImeDeleteKind = 2;
        });
        gImeCtl!.on('moveCursor', (d: number) => {
          hilog.info(DOMAIN, TAG, 'IME moveCursor: %d', d);
          try { fpbridge.onImeMoveCursor(d); } catch (_e) {}
        });
        gImeCtl!.on('sendKeyboardStatus', (s: number) => {
          hilog.info(DOMAIN, TAG, 'IME keyboardStatus: %d', s);
        });
        gImeListenersRegistered = true;
      }
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'IME attach FAILED: %{public}s', JSON.stringify(e));
      gImeAttached = false;
    });
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'IME attach throw: %{public}s', JSON.stringify(e));
  }
}

// 光标跟随：编辑框内触摸 DOWN → IME 候选框跟随光标（物理屏幕 px）
function imeUpdateCursor(xVp: number, yVp: number, density: number): void {
  if (!gImeCtl) return;
  try {
    gImeCtl.updateCursor({
      left: Math.round(xVp * density),
      top: Math.round(yVp * density),
      width: 2,
      height: 20
    }).catch(() => {});
  } catch (_e) {}
}

// 页面 → 组件单向调用桥（仿 TextInputController 模式）。
// 页面持有 FpgSurfaceCtrl 并传给 FpgSurface；组件 aboutToAppear 时注册回调。
// ── 窗口位置统一同步（PositionSync）────────────────────────
// 背景：2in1 系统管理下 windowRectChange 事件不可靠（输入法避让/系统移动
//   不触发），主窗此前用 150ms 轮询兜底；子窗缺失 → 被软键盘顶起后位置
//   不更新，Pascal 坐标基准错位。
// 统一：本模块级单例持有"窗口注册表"（各窗口创建处注册 getter，Index 持有
//   subWinMap 为唯一窗口源），150ms 主动 getWindowProperties → 变化才
//   onWindowMoved(reqId,x,y) 上报 Pascal（onWindowMoved→SetScreenPosition）。
//   保留各窗口 windowRectChange 事件为即时通道（双保险）。
class PositionSync {
  private wins: Map<number, () => window.Window | null | undefined> = new Map();
  private cache: Map<number, [number, number]> = new Map();
  private timer: number = -1;

  register(reqId: number, getWin: () => window.Window | null | undefined): void {
    this.wins.set(reqId, getWin);
    this.ensureTimer();
  }

  unregister(reqId: number): void {
    this.wins.delete(reqId);
    this.cache.delete(reqId);
  }

  private ensureTimer(): void {
    if (this.timer >= 0) return;
    this.timer = setInterval(() => {
      this.tick();
    }, 150);
  }

  private tick(): void {
    this.wins.forEach((getWin, reqId) => {
      try {
        const win = getWin();
        if (win === undefined || win === null) return;
        const p = win.getWindowProperties();
        const x: number = p.windowRect.left;
        const y: number = p.windowRect.top;
        const c = this.cache.get(reqId);
        if (c === undefined || c[0] !== x || c[1] !== y) {
          // 上报成功后记录缓存：失败（NAPI 异常/属性未就绪被 catch）时
          // cache 不更新 → 下个 tick 重试，避免"一次失败永久不同步"
          // （弹窗锚点窗口位置停在初始值 → 子菜单/二次弹出错位）
          fpbridge.onWindowMoved(reqId, x, y);
          this.cache.set(reqId, [x, y]);
        }
      } catch (_e) {}
    });
  }
}

const gPositionSync = new PositionSync();

// 窗口创建处注册（reqId 窗口）：getter 返回该窗口 Window 对象（销毁后 undefined/null 自动跳过）
export function registerWindowPositionSync(reqId: number, getWin: () => window.Window | null | undefined): void {
  gPositionSync.register(reqId, getWin);
}

// 窗口销毁处注销（Index destroyWindow / 系统销毁回调）
export function unregisterWindowPositionSync(reqId: number): void {
  gPositionSync.unregister(reqId);
}

// ── 首帧上屏通知注册表 ─────────────────────────────────────
// Pascal 窗口第一次成功上屏（FlushBuffer）→ C++ NATIVE_CMD_FIRST_FRAME →
// Index/调用方 notifyFirstFrame(reqId) → 对应 FpgSurface 打开 XComponent
// 显示门（contentReady）。消除"窗口 show → 首帧 flush 之间黑色 surface 闪现"。
const firstFrameMap: Map<number, () => void> = new Map();
export function notifyFirstFrame(reqId: number): void {
  const cb = firstFrameMap.get(reqId);
  if (cb) cb();
}

export class FpgSurfaceCtrl {
  showIme?: (kbType: number) => void;   // IME 命令（type=6）路由
  hideIme?: () => void;
  focus?: () => void;                   // 子窗销毁后恢复本窗口键盘焦点
  focusHiddenInput?: () => void;        // 主窗隐藏 TextInput 焦点恢复（XComponent.onKeyEvent 不触发兜底）
  setExpectClientSize?: (w: number, h: number) => void;  // 首帧显示门：期望客户区尺寸（主窗）
}

@Component
export struct FpgSurface {
  @Prop reqId: number = 0;
  ctrl: FpgSurfaceCtrl = new FpgSurfaceCtrl();

  private xcCtrl: XComponentController = new XComponentController();
  // ── 自绘标题栏（OpenHarmony legacy 子窗无系统装饰时替代）──
  // 平时隐藏；需要时按主窗标题栏高（AppStorage 'decH_1'，vp）展示：
  // 图标（=主窗应用图标）+ 标题 + 关闭按钮 + 拖动（PanGesture → moveWindowTo）。
  @State showTitleBar: boolean = false;
  @State titleBarH: number = 32;
  @State titleText: string = 'fpGUI';
  private titleBarWin: window.Window | null = null;   // 拖动/关闭用（Index 存 winHandle_'+reqId）
  private dragWinX: number = 0;                        // 拖动起点窗口位置
  private dragWinY: number = 0;
  // 首帧显示门：期望客户区尺寸（px）。
  // 主窗：命令到达后由 Index 经 ctrl.setExpectClientSize 设置（标准窗口模式）；
  // 子窗：aboutToAppear 读 AppStorage('winClientW/H_'+reqId)（createSubWin 已存）。
  // 门开启期间 XComponent opacity=0，surface 尺寸到位（双维度±2px）后放行，
  // 并调 refreshWindow 强制 Pascal 重绘（buffer 重建=surface，消除首帧黑边）。
  // 主窗初始/全屏无期望（expect=0）→ contentReady=true 直接显示（行为不变）。
  @State contentReady: boolean = false;
  private firstFrameArrived: boolean = false;   // Pascal 首帧已上屏（NATIVE_CMD_FIRST_FRAME）
  private expectW: number = 0;
  private expectH: number = 0;
  private expectSetAt: number = 0;      // 门开启时间戳（超时兜底用）
  private refreshed: boolean = false;   // 放行后仅强制刷新一次
  private curW: number = 0;             // 最近一次 area 宽（px）
  private curH: number = 0;             // 最近一次 area 高（px）
  private hasSurface: boolean = false;  // XComponent surface 已 onLoad（未加载前不可调 setXComponentSurfaceRect）
  private surfaceSyncTimer: number = -1; // surface 同步后延迟重刷的防抖定时器
  private destroyed: boolean = false;   // 组件已销毁（窗口关闭/卸载）——延迟刷新须跳过，防对失效窗口操作
  private densityPx: number = 1.0;
  // modifier state -> real modifier mask for Pascal (avoids Shift stickiness)
  private shiftDown: boolean = false;
  private ctrlDown: boolean = false;
  private altDown: boolean = false;
  private metaDown: boolean = false;
  // ── 长按模拟右键状态（触屏）──
  private lpDownAt: number = 0;     // 本次 DOWN 时间（0=无按压）
  private lpDownX: number = 0;      // DOWN 点（vp，与 onTouch 坐标同基准）
  private lpDownY: number = 0;
  private lpMoved: boolean = false; // 位移越过阈值 → 按拖拽处理，不合成右键
  private lpTimer: number = -1;     // 长按定时器（-1=无）

  aboutToAppear(): void {
    // 期望客户区尺寸（px）：子窗由 Index.ets createSubWin 存 AppStorage('winClientW/H_'+reqId)
    this.expectW = AppStorage.get<number>('winClientW_' + this.reqId) ?? 0;
    this.expectH = AppStorage.get<number>('winClientH_' + this.reqId) ?? 0;
    // 自绘标题栏标志（Index createSubWin 在 setUIContent 前已存）：
    // 显示时高度=主窗标题栏高（decH_1，vp），标题/窗口句柄取自存储
    this.showTitleBar = (AppStorage.get<number>('titleBar_' + this.reqId) ?? 0) === 1;
    if (this.showTitleBar) {
      const h: number = AppStorage.get<number>('decH_1') ?? 0;
      if (h >= 10) this.titleBarH = h;
      this.titleText = AppStorage.get<string>('winTitle_' + this.reqId) ?? 'fpGUI';
      this.titleBarWin = AppStorage.get<window.Window>('winHandle_' + this.reqId) ?? null;
    }
    this.densityPx = display.getDefaultDisplaySync().densityPixels;
    // 首帧显示门注册：Pascal 首帧上屏后经 notifyFirstFrame(reqId) 回调。
    // 无期望尺寸（弹窗等）：首帧到达即放行；600ms 兜底防通知丢失永久隐藏。
    firstFrameMap.set(this.reqId, (): void => { this.onFirstFrame(); });
    if (this.expectW <= 0 && this.expectH <= 0) {
      setTimeout(() => {
        if (!this.destroyed && !this.contentReady) {
          this.contentReady = true;
          this.doRefresh();
        }
      }, 600);
    }
    this.expectSetAt = Date.now();
    this.ctrl.showIme = (kbType: number): void => { this.showIme(kbType); };
    this.ctrl.hideIme = (): void => { this.hideIme(); };
    this.ctrl.focus = (): void => {
      // 主窗（reqId=1）：焦点交给 Index 隐藏 TextInput；
      // 子窗：焦点交给本窗口隐藏 TextInput（XComponent 无法持有组件焦点）。
      if (this.reqId === 1) {
        if (this.ctrl.focusHiddenInput) this.ctrl.focusHiddenInput();
        return;
      }
      this.focusKbdInput();
    };
    this.ctrl.setExpectClientSize = (w: number, h: number): void => {
      this.expectW = w;
      this.expectH = h;
      this.expectSetAt = Date.now();
      this.refreshed = false;
      if (this.matchCurrent() && this.firstFrameArrived) {
        this.contentReady = true;
        this.doRefresh();
      } else if (this.curW > 0 || this.curH > 0) {
        // 当前 area 未达期望（窗口 resize 未完成）→ 隐藏错位首帧，等 onAreaChange 匹配
        this.contentReady = false;
      }
      // 超时兜底：resize 异常（surface 永不达期望）时强制放行+刷新，避免永久隐藏
      setTimeout(() => {
        try {
          if (this.expectW > 0 && !this.refreshed) {
            this.contentReady = true;
            this.doRefresh();
          }
        } catch (_e) {}
      }, 2500);
    };
  }

  aboutToDisappear(): void {
    // 窗口关闭/组件卸载：置 destroyed——surface sync 的延迟 refreshWindow 定时器
    // 在窗口销毁后仍可能触发，对失效窗口刷新会访问已释放句柄/画布 → SIGSEGV
    // （扫菜单反复开合 popup 的崩溃回归）。卸载后跳过硬刷。
    this.destroyed = true;
    firstFrameMap.delete(this.reqId);
  }

  // Pascal 首帧已上屏：门条件之一满足。尺寸也已到位（或无期望）时立即放行；
  // 尺寸未到位则等 onAreaChange 匹配后放行（firstFrameArrived 已置位）。
  private onFirstFrame(): void {
    this.firstFrameArrived = true;
    if (this.destroyed || this.contentReady) return;
    this.contentReady = true;
    this.doRefresh();
  }

  // 当前 area（px）与期望客户区匹配（±2px 容差）
  private matchCurrent(): boolean {
    if (this.expectW <= 0 || this.expectH <= 0) return false;
    if (this.curW <= 0 || this.curH <= 0) return false;
    return Math.abs(this.curW - this.expectW) <= 2 &&
      Math.abs(this.curH - this.expectH) <= 2;
  }

  // 强制 Pascal 重绘 + 重发 move/resize（C++ RefreshWindow → ohos_force_window_refresh：
  // Invalidate 重绘 + DoUpdateWindowPosition 重建 buffer 池为当前 surface 尺寸）
  private doRefresh(): void {
    if (this.refreshed) return;
    this.refreshed = true;
    try {
      fpbridge.refreshWindow(this.reqId);
      hilog.info(DOMAIN, TAG, 'FpgSurface req=%d refreshWindow (first-frame gate)', this.reqId);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'FpgSurface req=%d refreshWindow err: %{public}s', this.reqId, (e as Error).message);
    }
  }

  // ── 自绘标题栏交互 ──
  // 拖动（PanGesture onActionStart 记录窗口位置 → onActionUpdate 增量移动）。
  // moveWindowTo 触发 windowRectChange → 现有即时通道上报 Pascal 位置同步。
  private titleBarDragStart(): void {
    if (this.titleBarWin === null) return;
    try {
      const p: window.WindowProperties = this.titleBarWin.getWindowProperties();
      this.dragWinX = p.windowRect.left;
      this.dragWinY = p.windowRect.top;
    } catch (_e) {}
  }

  private titleBarDragMove(offsetX: number, offsetY: number): void {
    if (this.titleBarWin === null) return;
    try {
      this.titleBarWin.moveWindowTo(this.dragWinX + offsetX, this.dragWinY + offsetY).catch(() => {});
    } catch (_e) {}
  }

  // 关闭按钮：复刻系统标题栏 X 语义——先 queryCanClose（Pascal CanClose 双向：
  // 0=CanClose=false 不允许关 → 保持窗口；1=允许关 → 放行），放行则
  // destroyWindow → windowEvent 7（WINDOW_DESTROYED）→ onWindowClosed → 完整清理链。
  private titleBarClose(): void {
    if (this.titleBarWin === null) return;
    hilog.info(DOMAIN, TAG, 'TitleBar close clicked req=%d', this.reqId);
    let can = -1;
    try { can = fpbridge.queryCanClose(this.reqId); } catch (_e) {}
    hilog.info(DOMAIN, TAG, 'TitleBar close: canClose=%d', can);
    if (can === 0) return;   // CanClose=false：阻止关闭（窗口保持）
    try { this.titleBarWin.destroyWindow(); } catch (_e) {}
    // 主动销毁：windowEvent(7) 不保证及时/必然回调 → 显式通知 Pascal 关闭链。
    // 模态子窗（wtModalForm）场景必须走 inject_window_closed → FPGM_CLOSE →
    // DoReleaseWindowHandle → gModalWinHandle 清空；否则 Pascal 仍认为模态
    // 存活，主窗触摸被 DROPPED by modal 永久丢弃。与 windowEvent(7) 双调
    // 幂等（C++ g_winMap.find 失败跳过 / Pascal FindWindowByHandle 失败跳过）。
    fpbridge.onWindowClosed(this.reqId);
    hilog.info(DOMAIN, TAG, 'TitleBar close: inject closed req=%d', this.reqId);
  }

  // 顶部 Y 补偿（vp）：原路线取 AppStorage('decH_'+reqId)（系统装饰真实值）；
  // 自绘标题栏窗口（OpenHarmony legacy 回退，系统 dec=0）在基础上附加标题栏高
  // titleBarH（vp）——自绘标题栏占据客户区顶部，触摸/鼠标 displayY 同样要减。
  private compensateTop(): number {
    const decH: number = AppStorage.get<number>('decH_' + this.reqId) ?? 0;
    return this.showTitleBar ? decH + this.titleBarH : decH;
  }

  private showIme(kbType: number): void {
    hilog.info(DOMAIN, TAG, 'showIme: type=%d', kbType);
    // Pascal 聚焦了本窗口的编辑（showKeyboard → 本页）：把键盘焦点交给本窗口
    // 隐藏 TextInput——否则子窗内无获焦组件，物理数字键被 IME 忽略后丢弃。
    if (this.reqId !== 1) {
      this.focusKbdInput();
    }
    // IME 命令模式：attach（输入类型变化时 reattach）→ 弹软键盘
    imeEnsureAttached(kbType);
    // PC/2in1：连接输入法（保中文输入）但不弹软键盘（物理键经输入法
    // 语言模式路由：中文组合拼音、英文直通；软键盘面板会拦截物理键）
    if (!isPcLike()) {
      if (gImeCtl) {
        try { gImeCtl.showTextInput().catch(() => {}); } catch (_e) {}
      }
    }
    // 通知 Pascal 键盘将显示（ohos_show_keyboard_from_ets 不 bridge 回 ETS，无回环）
    try { fpbridge.showKeyboard(1); } catch (_e) {}
    hilog.info(DOMAIN, TAG, 'showIme: done');
  }

  private hideIme(): void {
    hilog.info(DOMAIN, TAG, 'hideIme: enter');
    // 隐藏软键盘（InputMethodController 命令模式，无 TextInput 组件）
    if (gImeCtl) {
      try { gImeCtl.hideTextInput().catch(() => {}); } catch (_e) {}
      // 结束输入法会话并复位 attach 状态：hideTextInput 只隐藏面板，
      // 会话仍占位导致下次 showIme 跳过 attach（输入法只打开一次的根因）。
      // 下次 showIme → imeEnsureAttached 重新 attach → 会话重建 → 输入法恢复。
      try { gImeCtl.stopInputSession().catch(() => {}); } catch (_e) {}
      gImeAttached = false;
    }
    // 通知 Pascal 键盘将隐藏（对称 showIme）
    try { fpbridge.showKeyboard(0); } catch (_e) {}
    hilog.info(DOMAIN, TAG, 'hideIme: done');
  }

  // 交互即聚焦：确保本窗口持有系统键盘焦点（onKeyEvent 仅在聚焦时触发）。
  // 弹窗关闭/托盘收起恢复/窗口失焦后焦点可能丢失——任何触摸/鼠标交互即恢复。
  private ensureFocus(): void {
    // 主窗（reqId=1）：焦点由 Index 的隐藏 TextInput 持有（focusHiddenInput 恢复）。
    if (this.reqId === 1) return;
    this.focusKbdInput();
  }

  // 长按模拟右键：取消未到点的定时器
  private cancelLongPress(): void {
    if (this.lpTimer !== -1) {
      clearTimeout(this.lpTimer);
      this.lpTimer = -1;
    }
  }

  // 子窗隐藏 TextInput 标识（与主窗 Index 的 'hidden_digit_input' 区分）
  private hiddenKbdId(): string {
    return 'hidden_digit_input_' + this.reqId;
  }

  // 子窗键盘焦点：焦点控制只对可获焦组件（TextInput/Button...）生效，
  // XComponent 无法成为获焦组件（onFocus/onKeyEvent 不触发，requestFocus 静默
  // 失败）→ 弹窗内数字键被 IME 忽略后无人接收 → 录入不了数字（主窗正常，因为
  // 主窗有 Index 隐藏 TextInput）。这里记录 requestFocus 返回值作为对账证据。
  private focusKbdInput(): void {
    try {
      const ok: boolean = focusControl.requestFocus(this.hiddenKbdId());
      hilog.info(DOMAIN, TAG,
        'FpgSurface req=%d focus hidden input: ok=%{public}d', this.reqId, ok ? 1 : 0);
    } catch (e) {
      hilog.warn(DOMAIN, TAG,
        'FpgSurface req=%d focus hidden input err: %{public}s', this.reqId, (e as Error).message);
    }
  }

  // 隐藏 TextInput 按键转发（与主窗 Index 同一路径）：TextInput 消费事件
  // 防止其自身插入字符，uni>0 才能让 Pascal 生成 KEYCHAR 插入。
  private hiddenKeyHandler(event: KeyEvent): boolean {
    const kc: number = event.keyCode as number;
    const isDown: boolean = (event.type as number) === 0;
    const act: number = isDown ? 0 : 1;
    if (kc === 2047 || kc === 2048) this.shiftDown = isDown;
    else if (kc === 2072 || kc === 2073) this.ctrlDown = isDown;
    else if (kc === 2045 || kc === 2046) this.altDown = isDown;
    else if (kc === 2076 || kc === 2077) this.metaDown = isDown;
    const mods: number = (this.ctrlDown ? 1 : 0) | (this.shiftDown ? 2 : 0)
      | (this.altDown ? 4 : 0) | (this.metaDown ? 8 : 0);
    let uni: number = 0;
    if (kc >= 2000 && kc <= 2009) {
      uni = 48 + (kc - 2000);  // '0'-'9'
    } else if (kc >= 2017 && kc <= 2042) {
      const base: number = 'a'.charCodeAt(0) + (kc - 2017);
      uni = (mods & 2) !== 0 ? base - 32 : base;
    } else if (kc === 2050) {
      uni = 32;  // space
    } else if (kc === 2049) {
      uni = 9;   // tab
    } else if (kc === 2054) {
      uni = 13;  // enter
    }
    // Backspace/Delete：放行让 IME deleteLeft/deleteRight 路径处理，避免双删。
    if (kc === 2055 || kc === 2071) {
      return false;
    }
    hilog.info(DOMAIN, TAG,
      'SUBKEY kc=%d act=%d mods=%d uni=%d req=%d', kc, act, mods, uni, this.reqId);
    fpbridge.onKeyEvent(kc, act, mods, uni);
    return true;
  }

  private sendKeyEvent(event: KeyEvent): void {
    const kc: number = event.keyCode as number;
    const isDown: boolean = (event.type as number) === 0;  // component KeyType: Down=0, Up=1
    if (kc === 2047 || kc === 2048) this.shiftDown = isDown;
    else if (kc === 2072 || kc === 2073) this.ctrlDown = isDown;
    else if (kc === 2045 || kc === 2046) this.altDown = isDown;
    else if (kc === 2076 || kc === 2077) this.metaDown = isDown;
    const act: number = isDown ? 0 : 1; // OH_KEY_DOWN=0, UP=1
    // mask matches Pascal OHOS_MODIFIER_*: CTRL=1, SHIFT=2, ALT=4, META=8
    const mods: number = (this.ctrlDown ? 1 : 0) | (this.shiftDown ? 2 : 0)
      | (this.altDown ? 4 : 0) | (this.metaDown ? 8 : 0);
    // 删除键双路径去重：软键盘删除键 → IME deleteLeft/deleteRight 命令注入后，
    // 系统仍发物理键事件（KEYEV code=2055/2071）→ 时间窗（250ms）内丢弃，
    // 否则 Pascal 双删。硬件键盘删除键无 IME 命令 → 正常转发。
    if ((kc === 2055 || kc === 2071) && Date.now() - gLastImeDeleteAt < 250) {
      return;
    }
    // 物理键字符（数字/字母走 KEYEV 通道，uni 必须补上——Pascal 仅 uni>0 时
    // 生成 KEYCHAR 插入；否则数字键无字符可插（此前"不能输入数字"根因））
    const uni: number = this.keyCodeToUnicode(kc, (mods & 2) !== 0);
    // 符号/标点键双通道去重：IME insertText 刚注入过相同字符 → 丢弃 KEYEV
    // （软键盘符号键实测双发：insertText 命令 + 物理键事件）
    if (uni > 0 && Date.now() - gLastImeInsertAt < 150 &&
        gLastImeInsertText.indexOf(String.fromCharCode(uni)) >= 0) {
      return;
    }
    // DIAG: keyboard routing 对账（ETS 侧）——与 Pascal KEYEV kind/KEYEV mapped 对照。
    // 定位 Alt/Ctrl 组合（菜单/剪贴板）与 Home/End 不生效的断点：
    // 修饰键自身事件是否到达（tracking）、keycode 是否 SDK 预期、metaKey 位状态。
    hilog.info(DOMAIN, TAG,
      'KEYD kc=%d act=%d mods=%d uni=%d raw_metaKey=%d track(alt=%d ctrl=%d shift=%d meta=%d)',
      kc, act, mods, uni, (event.metaKey ?? 0),
      this.altDown ? 1 : 0, this.ctrlDown ? 1 : 0, this.shiftDown ? 1 : 0, this.metaDown ? 1 : 0);
    fpbridge.onKeyEvent(kc, act, mods, uni);
  }
  // 物理键码 → Unicode 字符（命令模式下数字/字母/符号走 KEYEV 通道）。
  // 键码 = OHOS KeyCode 枚举（@ohos.multimodalInput.keyCode）：
  //   2000='0'、2001-2009='1'-'9'、2010='*'、2011='#'、2017-2042='A'-'Z'、
  //   2043=','、2044='.'、2050=空格、2056-2066=符号键。
  // shift 上档：数字行 !@#$%^&*()、字母大写、符号对应上档字符。
  private keyCodeToUnicode(kc: number, shift: boolean): number {
    if (kc === 2000) return shift ? ')'.charCodeAt(0) : '0'.charCodeAt(0);
    if (kc >= 2001 && kc <= 2009) {
      const base = String.fromCharCode('1'.charCodeAt(0) + (kc - 2001));
      if (!shift) return base.charCodeAt(0);
      const up = '!@#$%^&*(';
      return up.charCodeAt(kc - 2001);
    }
    if (kc === 2010) return '*'.charCodeAt(0);   // KEYCODE_STAR
    if (kc === 2011) return '#'.charCodeAt(0);   // KEYCODE_POUND
    if (kc >= 2017 && kc <= 2042) {
      const base = String.fromCharCode('a'.charCodeAt(0) + (kc - 2017));
      return shift ? base.toUpperCase().charCodeAt(0) : base.charCodeAt(0);
    }
    if (kc === 2043) return shift ? '<'.charCodeAt(0) : ','.charCodeAt(0);
    if (kc === 2044) return shift ? '>'.charCodeAt(0) : '.'.charCodeAt(0);
    if (kc === 2050) return ' '.charCodeAt(0);
    if (kc === 2056) return shift ? '~'.charCodeAt(0) : '`'.charCodeAt(0);
    if (kc === 2057) return shift ? '_'.charCodeAt(0) : '-'.charCodeAt(0);
    if (kc === 2058) return shift ? '+'.charCodeAt(0) : '='.charCodeAt(0);
    if (kc === 2059) return shift ? '{'.charCodeAt(0) : '['.charCodeAt(0);
    if (kc === 2060) return shift ? '}'.charCodeAt(0) : ']'.charCodeAt(0);
    if (kc === 2061) return shift ? '|'.charCodeAt(0) : '\\'.charCodeAt(0);
    if (kc === 2062) return shift ? ':'.charCodeAt(0) : ';'.charCodeAt(0);
    if (kc === 2063) return shift ? '"'.charCodeAt(0) : '\''.charCodeAt(0);
    if (kc === 2064) return shift ? '?'.charCodeAt(0) : '/'.charCodeAt(0);
    if (kc === 2065) return '@'.charCodeAt(0);
    if (kc === 2066) return '+'.charCodeAt(0);
    return 0;
  }

  build() {
    Column() {
      // ── 自绘标题栏（平时隐藏；OpenHarmony legacy 子窗丢系统装饰时显示）──
      // 高度 = 主窗标题栏高（decH_1 vp）；图标=应用图标（与主窗一致）+
      // 标题 + 关闭按钮；PanGesture 拖动（moveWindowTo，rectChange 上报位置）。
      if (this.showTitleBar) {
        Row() {
          Image($r('app.media.startIcon'))
            .width(this.titleBarH * 0.6)
            .height(this.titleBarH * 0.6)
            .margin({ left: 12, right: 8 })
          Text(this.titleText)
            .fontSize(14)
            .fontColor('#FF000000')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Text('✕')
            .width(this.titleBarH)
            .height(this.titleBarH)
            .textAlign(TextAlign.Center)
            .fontSize(16)
            .fontColor('#FF666666')
            .onClick(() => { this.titleBarClose(); })
        }
        .width('100%')
        .height(this.titleBarH)
        .backgroundColor('#F1F3F5')
        .gesture(
          PanGesture()
            .onActionStart(() => { this.titleBarDragStart(); })
            .onActionUpdate((event: GestureEvent) => {
              this.titleBarDragMove(event.offsetX, event.offsetY);
            })
        )
      }
      XComponent({
        id: 'xc_fpg_' + this.reqId,
        type: XComponentType.SURFACE,
        controller: this.xcCtrl
      })
      // XComponent 不获焦（全部窗口）：焦点控制不支持 XComponent，requestFocus
      // 静默失败 → 键盘焦点交给隐藏 TextInput（子窗=本组件创建，主窗=Index 创建）。
      .focusable(false)
      .defaultFocus(false)
      // onKeyPreIme：IME 之前拦截物理键——数字键被 HMKeyboard 消费前截获，
      // 直接注入 EnqueueKeyEvent；字母等留给 IME insertText 中文输入。
      .onKeyPreIme((event: KeyEvent): boolean => {
        const kc: number = event.keyCode as number;
        const isDown: boolean = (event.type as number) === 0;
        const isUp: boolean = (event.type as number) === 1;
        // 数字行 OHOS keycodes: 2000='0'..2009='9'
        if (kc >= 2000 && kc <= 2009) {
          // 更新修饰键状态（onKeyPreIme 先于 sendKeyEvent 触发）
          if (kc === 2047 || kc === 2048) this.shiftDown = isDown;
          else if (kc === 2072 || kc === 2073) this.ctrlDown = isDown;
          else if (kc === 2045 || kc === 2046) this.altDown = isDown;
          else if (kc === 2076 || kc === 2077) this.metaDown = isDown;
          const act: number = isDown ? 0 : 1;
          const mods: number = (this.ctrlDown ? 1 : 0) | (this.shiftDown ? 2 : 0)
            | (this.altDown ? 4 : 0) | (this.metaDown ? 8 : 0);
          const uni: number = isDown
            ? this.keyCodeToUnicode(kc, (mods & 2) !== 0)
            : this.keyCodeToUnicode(kc, (mods & 2) !== 0);
          hilog.info(DOMAIN, TAG,
            'PreIme DIGIT: kc=%d act=%d uni=%d — intercepted before IME', kc, act, uni);
          fpbridge.onKeyEvent(kc, act, mods, uni);
          return true;   // consume: prevent HMKeyboard from swallowing
        }
        return false;     // let other keys flow to IME → onKeyEvent
      })
      .opacity(this.contentReady ? 1 : 0.01)
      .visibility(this.firstFrameArrived ? Visibility.Visible : Visibility.Hidden)
      .onLoad(() => {
        this.hasSurface = true;
        const sid: string = this.xcCtrl.getXComponentSurfaceId();
        try {
          // false=支持alpha透明混合(API22+)
          this.xcCtrl.setXComponentSurfaceConfig({ isOpaque: false });
        } catch (_e) {}
        // 渲染面真实尺寸（px）随上报：C++ 以它作为 native buffer 几何权威值。
        // 设备被强制最大化时建窗请求尺寸是旧值（如 1344x831），用它钉 buffer
        // 池会导致合成器把画面放大显示、且首帧后失配帧被丢弃（画面冻结）。
        let surfW: number = 0;
        let surfH: number = 0;
        try {
          const r = this.xcCtrl.getXComponentSurfaceRect();
          surfW = r.surfaceWidth;
          surfH = r.surfaceHeight;
        } catch (_e) {}
        fpbridge.onSurfaceReady(this.reqId, 'xc_fpg_' + this.reqId, sid, surfW, surfH);
        hilog.info(DOMAIN, TAG,
          'FpgSurface onLoad: reqId=%d sid=%s surf=%dx%d', this.reqId, sid, surfW, surfH);
        // 主窗（reqId=1）：焦点由 Index 隐藏 TextInput 持有；子窗：交给本窗口
        // 隐藏 TextInput 捕获键盘事件（XComponent 无法获焦）。
        if (this.reqId !== 1) {
          this.focusKbdInput();
        }
      })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const w: number = Number(newValue.width) || 0;
        const h: number = Number(newValue.height) || 0;
        this.curW = Math.round(w * this.densityPx);
        this.curH = Math.round(h * this.densityPx);
        // 强制 surface 尺寸同步：XComponent surface 不随窗口 resize 即时更新
        // （最大化→内容放大、还原→缩小+黑屏，需点击/焦点后才异步就绪）。此处把
        // surface 钉成组件当前 px 尺寸（SurfaceRect 单位 px），并延迟重刷
        // refreshWindow 让 Pascal 在新 surface 下重绘重提交 → 1:1 无放大/黑屏。
        if (this.hasSurface && this.curW > 0 && this.curH > 0) {
          try {
            this.xcCtrl.setXComponentSurfaceRect({
              offsetX: 0,
              offsetY: 0,
              surfaceWidth: this.curW,
              surfaceHeight: this.curH
            });
            try {
              const cur = this.xcCtrl.getXComponentSurfaceRect();
              hilog.info(DOMAIN, TAG,
                'FpgSurface req=%d surface sync: want=%dx%d got=%dx%d',
                this.reqId, this.curW, this.curH,
                cur.surfaceWidth, cur.surfaceHeight);
            } catch (_e) {}
            // surface 生效后再重绘重提交（防抖：合并快速连续 resize；窗口已销毁则跳过，
            // 避免对失效句柄操作崩溃——popup 快速开关时 100ms 定时器常在窗口销毁后触发）
            if (this.surfaceSyncTimer >= 0) {
              clearTimeout(this.surfaceSyncTimer);
            }
            this.surfaceSyncTimer = setTimeout(() => {
              this.surfaceSyncTimer = -1;
              if (this.destroyed) {
                return;
              }
              try {
                fpbridge.refreshWindow(this.reqId);
              } catch (_e) {}
            }, 100);
          } catch (e) {
            hilog.warn(DOMAIN, TAG,
              'FpgSurface req=%d setXComponentSurfaceRect err: %{public}s',
              this.reqId, (e as Error).message);
          }
        }
        // 主窗（reqId=1）：把 surface 实际尺寸（px）上报 Pascal——权威渲染目标尺寸。
        // 创建期 Index.windowSizeChange 的上报可能早于 native 句柄登记被丢弃，
        // 这里在 surface 就绪/变化后持续上报；C++ 侧去重 + pending 补送。
        if (this.reqId === 1 && this.curW > 0 && this.curH > 0) {
          try { fpbridge.onWindowResized(1, this.curW, this.curH); } catch (_e) {}
        }
        // 首帧显示门：surface 尺寸（px）与期望客户区匹配后放行 + refreshWindow
        // 强制 Pascal 重绘（buffer 重建=surface → 内容填满无黑边）。
        // 主窗从默认窗口缩到期望尺寸、子窗从压缩态展开到客户区，均在此收敛。
        const wasReady: boolean = this.contentReady;
        if (!wasReady && this.expectW > 0 && this.expectH > 0) {
          if (this.matchCurrent() && this.firstFrameArrived) {
            this.contentReady = true;
            this.doRefresh();
          } else if (Date.now() - this.expectSetAt > 2000) {
            // 超时兜底：resize 未达期望（异常/全屏差异）时强制放行，避免永久隐藏
            this.contentReady = true;
            this.doRefresh();
          }
        }
      })
      .onTouch((event: TouchEvent) => {
        // 交互即聚焦：点击/触摸 XComponent 时确保系统键盘焦点（onKeyEvent
        // 仅在组件聚焦时触发）。弹窗/托盘流程后焦点可能丢失，点击即恢复。
        this.ensureFocus();
        // 按输入来源分流：鼠标/触控板交给 onMouse（避免双通道重复）；
        // 手指/笔/未知来源走本通道（Down/Move/Up = 左键点按/拖拽）。
        if (event.source === SourceType.Mouse) {
          return;
        }
        if (event.touches.length > 0) {
          const t = event.touches[0];
          // 与 onMouse 统一坐标基准与补偿（X: decW，Y: decTop=decH-decW）。
          // TouchObject.displayX/displayY 与 MouseEvent 同为 vp 单位。
          const decH: number = this.compensateTop();
          const decW: number = AppStorage.get<number>('decW_' + this.reqId) ?? 0;
          const decTop: number = decH - decW;
          const sx: number = (t.displayX ?? 0) - decW;
          const sy: number = (t.displayY ?? 0) - decTop;
          // 坐标有效性防御：设备上部分事件 displayX/Y 未填充（NaN/垃圾值）
          // → 丢弃，避免 Pascal 收到无效坐标导致点击失效
          if (!Number.isFinite(sx) || !Number.isFinite(sy) ||
              Math.abs(sx) > 20000 || Math.abs(sy) > 20000) {
            hilog.warn(DOMAIN, TAG, 'touch invalid coord req=%d sx=%d sy=%d', this.reqId, sx, sy);
            return;
          }
          if (event.type === TouchType.Down) {
            // 光标跟随（近似）：编辑框内点击位置 → IME 候选框跟随
            imeUpdateCursor(sx, sy, this.densityPx);
            // 长按模拟右键：到点即弹（不必等松手）
            this.cancelLongPress();
            this.lpDownAt = Date.now();
            this.lpDownX = sx;
            this.lpDownY = sy;
            this.lpMoved = false;
            this.lpTimer = setTimeout(() => {
              this.lpTimer = -1;
              if (this.destroyed || this.lpDownAt <= 0 || this.lpMoved) return;
              hilog.info(DOMAIN, TAG, 'LONGPRESS right-click req=%d vp=(%d,%d)',
                this.reqId, Math.round(this.lpDownX), Math.round(this.lpDownY));
              // 1) 右键 Down+Up：编辑框弹出右键菜单（手指未松）
              fpbridge.onMouseEvent(String(this.reqId), this.lpDownX, this.lpDownY, 0, 2);
              fpbridge.onMouseEvent(String(this.reqId), this.lpDownX, this.lpDownY, 2, 2);
              // 2) 补发左键 Down（button=1→MOUSE_LEFT）：右键 UP 清掉了
              //    Pascal 的左键路由/按键状态，不补则松手 UP 被丢弃
              //    （MouseCapture 不释放）；补发后 Move 仍带左键、Up 正常。
              fpbridge.onMouseEvent(String(this.reqId), this.lpDownX, this.lpDownY, 0, 1);
            }, LONGPRESS_MS);
            fpbridge.onTouchEvent(String(this.reqId), sx, sy, 0);
          } else if (event.type === TouchType.Move) {
            // 位移越阈值 → 按拖拽处理：取消长按（事件照常转发，不影响拖拽）
            if (!this.lpMoved &&
                (Math.abs(sx - this.lpDownX) + Math.abs(sy - this.lpDownY) > LONGPRESS_SLOP)) {
              this.lpMoved = true;
              this.cancelLongPress();
            }
            fpbridge.onTouchEvent(String(this.reqId), sx, sy, 1);
          } else if (event.type === TouchType.Up) {
            // 左键 Up 照常转发：定时器补发的左键 Down 已恢复路由，
            // 这条 Up 仍送达原按下控件（MouseCapture 释放/点击/复选框）
            this.cancelLongPress();
            this.lpDownAt = 0;
            this.lpMoved = false;
            fpbridge.onTouchEvent(String(this.reqId), sx, sy, 2);
          } else if (event.type === TouchType.Cancel) {
            this.cancelLongPress();
            this.lpDownAt = 0;
            this.lpMoved = false;
          }
        }
      })
      // Real mouse: 真机实测 action = Press=1/Release=2/Move=3/Hover=4
      // → 映射为 OH_TOUCH 语义（0=Down/1=Move/2=Up）。触屏走 onTouch。
      .onMouse((event: MouseEvent) => {
        // 交互即聚焦（同 onTouch）：鼠标交互时确保系统键盘焦点
        this.ensureFocus();
        // 模拟器（INPUT_USE_ONMOUSE=false）：onMouse 抑制（onTouch 完整承载）
        if (!INPUT_USE_ONMOUSE) {
          return;
        }
        // action → OH_TOUCH 语义（0=Down/1=Move/2=Up）。
        const btn = event.button as number;
        const ma = event.action as number;
        let act = 1;   // 默认 Move（OH_TOUCH_MOVE）
        if (ma === MOUSE_ACTION_PRESS) act = 0;          // Press → Down
        else if (ma === MOUSE_ACTION_RELEASE) act = 2;   // Release → Up
        else if (ma === MOUSE_ACTION_MOVE || ma === MOUSE_ACTION_HOVER) act = 1;  // Move/Hover → Move
        // Unified SCREEN coordinate basis (displayX/displayY, no mixed-basis
        // fallback to component-relative x/y). 减标题栏高 decH。
        // 设备 displayY 为屏幕坐标。统一坐标系（主窗/子窗同公式）：
        // ETS 只补偿"XComponent 在窗口内的偏移"——X：左边框（decW_'+reqId，
        // decW/2）；Y：标题栏真高 decTop（decH_'+reqId 总装饰高 − 下边框≈左边框）。
        // 窗口位置（windowRect.top/left）由 Pascal wnd.Left/Top 处理
        // （主窗 pos-poll 强制同步；子窗 windowRectChange 事件）。
        // 子窗无标题栏（OpenHarmony 回退路径）时 decH/decW=0 → 减 0 无影响；
        // 自绘标题栏窗口：compensateTop 附加标题栏高（decH 真值 0 + titleBarH）。
        const decH: number = this.compensateTop();
        const decW: number = AppStorage.get<number>('decW_' + this.reqId) ?? 0;
        const decTop: number = decH - decW;   // 标题栏真高 = 总装饰 − 下边框(≈左边框)
        let mx: number = (event.displayX ?? 0) - decW;
        let my: number = (event.displayY ?? 0) - decTop;
        if (this.reqId === 1) {
          hilog.info(DOMAIN, TAG,
            'MOUSE-CALIB req=%{public}d rawX=%{public}d rawY=%{public}d decW=%{public}d decH=%{public}d decTop=%{public}d newX=%{public}d newY=%{public}d',
            btn, Math.round(event.displayX ?? 0), Math.round(event.displayY ?? 0),
            decW, decH, decTop, Math.round(mx), Math.round(my));
        }
        // 坐标有效性防御（同 onTouch）：无效坐标丢弃
        if (!Number.isFinite(mx) || !Number.isFinite(my) ||
            Math.abs(mx) > 20000 || Math.abs(my) > 20000) {
          hilog.warn(DOMAIN, TAG, 'mouse invalid coord req=%d mx=%d my=%d', this.reqId, mx, my);
          return;
        }
        // Move 微抖过滤：设备坐标微抖（<2px）→ 菜单 hover 边界判定抖动 →
        // 子菜单闪烁。Down/Up 不受影响（必须转发）。
        if (act === 1 && Math.abs(mx - gLastMouseX) < 2 && Math.abs(my - gLastMouseY) < 2) {
          return;
        }
        gLastMouseX = mx;
        gLastMouseY = my;
        fpbridge.onMouseEvent(String(this.reqId), mx, my, act, btn);
      })
      .onAxisEvent((event: AxisEvent) => {
        // 鼠标滚轮：axisVertical 为单位为"角度"的单次变化量（非总量），
        // 受系统滚轮放大倍数影响（scrollStep 告知倍率）；向前滚为负、向后为正。
        // BEGIN/UPDATE/END 多段都带角度 → 50ms 去抖只转发一次。
        // C++ OnWheelEvent / Pascal FPGM_SCROLL 链路已就绪（±delta per notch）。
        const v = event.axisVertical ?? 0;
        if (v === 0) return;
        const now = Date.now();
        if (now - gLastWheelAt < 50) return;
        gLastWheelAt = now;
        // 坐标：displayX/Y（屏幕 vp）与 onMouse 统一基准 + 装饰补偿
        const decH: number = this.compensateTop();
        const decW: number = AppStorage.get<number>('decW_' + this.reqId) ?? 0;
        const decTop: number = decH - decW;
        const mx: number = (event.displayX ?? event.x ?? 0) - decW;
        const my: number = (event.displayY ?? event.y ?? 0) - decTop;
        if (!Number.isFinite(mx) || !Number.isFinite(my) ||
            Math.abs(mx) > 20000 || Math.abs(my) > 20000) {
          return;
        }
        // 角度 → fpGUI 刻度（±1 notch）：每 ~scrollStep° 一键
        const step = 50;//(event.scrollStep ?? 15) > 0 ? (event.scrollStep ?? 15) : 15;
        //const delta = Math.sign(v) * Math.max(1, Math.round(Math.abs(v) / step));
        const delta = v > 0 ? 1 : -1;
        hilog.info(DOMAIN, TAG,
          'WHEEL req=%{public}d v=%{public}d step=%{public}d delta=%{public}d xy=(%{public}d,%{public}d)',
          this.reqId, v, step, delta, Math.round(mx), Math.round(my));
        fpbridge.onWheelEvent(String(this.reqId), mx, my, delta);
      })
      .onHoverMove((event: HoverEvent) => {
        // SDK 15+ 才有 onHoverMove（低版本系统不触发 → onMouse Move(3) 承载 hover）
        gLastHoverMoveAt = Date.now();
        // 与 onMouse 统一补偿：X 减左边框（decW）、Y 减标题栏真高
        // （decTop=decH−decW；自绘标题栏窗口经 compensateTop 附加标题栏高）
        const decH: number = this.compensateTop();
        const decW: number = AppStorage.get<number>('decW_' + this.reqId) ?? 0;
        const decTop: number = decH - decW;
        const hx: number = (event.displayX ?? 0) - decW;
        const hy: number = (event.displayY ?? 0) - decTop;
        hilog.info(DOMAIN, TAG, 'HOV req=%{public}d x=%{public}d y=%{public}d', this.reqId, Math.round(hx), Math.round(hy));
        fpbridge.onHoverEvent(String(this.reqId), hx, hy);
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        this.sendKeyEvent(event);
        // Consume the key so the system navigation (D-pad focus moves,
        // Enter/Esc default handling) does not swallow it before Pascal
        // processes the KEYPRESS.
        return true;
      })
      // ── 系统拖拽接收（fpGUI 拖入目标）─────────────────────────────
      // allowDrop 常开；无 DropHandler 控件时按 dndEnabled 过滤转发
      // （ETS isDndEnabled + C++ g_dndEnabled 双保险）。
      // 不设 .draggable(true)：避免长按自动起拖与 fpGUI 程序化 executeDrag 双触发。
      .allowDrop([
        uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        uniformTypeDescriptor.UniformDataType.HTML,
        uniformTypeDescriptor.UniformDataType.FILE,
        uniformTypeDescriptor.UniformDataType.IMAGE
      ])
      .onDragEnter((ev: DragEvent) => {
        this.forwardDrag(ev, 0);
      })
      .onDragMove((ev: DragEvent) => {
        // 乐观置位可落；Pascal 精确接受判定在 onDrop 同步应答（角标可能滞后一拍）
        ev.setResult(DragResult.DROP_ENABLED);
        this.forwardDrag(ev, 1);
      })
      .onDragLeave(() => {
        if (!this.dragEnabled()) return;
        try { fpbridge.onDragEvent(String(this.reqId), 2, 0, 0, ''); } catch (_e) {}
      })
      .onDrop((ev: DragEvent) => {
        if (!this.dragEnabled()) {
          hilog.warn(DOMAIN, TAG, 'DRAG drop req=%d BLOCKED by dndEnabled', this.reqId);
          ev.setResult(DragResult.DRAG_FAILED);
          return;
        }
        try {
          const records: Array<unifiedDataChannel.UnifiedRecord> = ev.getData().getRecords();
          const pt = this.dragCoords(ev);
          const recs = this.serializeRecords(records);
          hilog.info(DOMAIN, TAG, 'DRAG drop req=%d pt=(%d,%d) records=%{public}s',
            this.reqId, Math.round(pt.x), Math.round(pt.y), recs);
          // 同步应答（Pascal 经 win-cmd 队列处理，≤5s）：(accept<<8)|action
          const ret: number = fpbridge.onDropEvent(
            String(this.reqId), pt.x, pt.y, recs) as number;
          const accept = (ret >> 8) & 0xFF;
          hilog.info(DOMAIN, TAG, 'DRAG drop req=%d reply=%d accept=%d',
            this.reqId, ret, accept);
          ev.setResult(accept === 1 ? DragResult.DRAG_SUCCESSFUL : DragResult.DRAG_FAILED);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'req=%d onDrop failed: %{public}s',
            this.reqId, JSON.stringify(e));
          ev.setResult(DragResult.DRAG_FAILED);
        }
      })
      // 尺寸：标题栏隐藏时 100%；显示时占剩余（calc 减标题栏高 vp）。
      // 首帧显示门（contentReady）仍在：surface 尺寸=期望（±2px）后才放行。
      .width('100%')
      .height(this.showTitleBar ? `calc(100% - ${this.titleBarH}vp)` : '100%')
      // ── 子窗隐藏 TextInput（reqId!==1）：物理键捕获兜底 ──
      // XComponent 不能成为获焦组件 → 子窗内无获焦组件时，物理数字键被
      // HMKeyboard 忽略（isConsumedKeyDown ignore）后无人接收 → 弹窗编辑
      // 录入不了数字（主窗正常=Index 隐藏 TextInput 获焦直送 onKeyEvent）。
      // 本组件在本窗口获焦后同路径转发 fpbridge.onKeyEvent。
      if (this.reqId !== 1) {
        TextInput({ text: '', placeholder: '' })
          .id('hidden_digit_input_' + this.reqId)
          .type(InputType.Normal)
          .opacity(0)
          .fontSize(0)
          .width(0).height(0)
          .focusable(true)
          // 程序性/defaultFocus 获焦只作物理键捕获兜底，不绑输入法：
          // 防子窗创建时隐藏输入框获焦误弹软键盘；正式输入仍由 Pascal showIme 控制。
          .enableKeyboardOnFocus(false)
          .defaultFocus(true)
          .onKeyEvent((event: KeyEvent): boolean => {
            return this.hiddenKeyHandler(event);
          })
          .onFocus(() => {
            hilog.info(DOMAIN, TAG, 'SubHiddenInput: focused req=%d', this.reqId);
          })
      }
    }
    .width('100%').height('100%')
  }

  // ── 系统拖拽辅助 ─────────────────────────────────────────────
  private dragEnabled(): boolean {
    return (AppStorage.get<number>('dndEnabled_' + this.reqId) ?? 0) === 1;
  }

  // 拖拽坐标：getX/getY 自 API10 废弃 → 官方等价替代 getWindowX/getWindowY
  // （两者文档语义相同：均"相对窗口左上角"vp）——与 onMouse 同式补偿：
// X − 左边框(decW)，Y − 标题栏真高(decTop)。补偿后为客户区 vp，
// C++ ×density → px，Pascal ÷gfx 即客户区逻辑坐标（不再减窗口位置）。
  private dragCoords(ev: DragEvent): DragPoint {
    const decH: number = this.compensateTop();
    const decW: number = AppStorage.get<number>('decW_' + this.reqId) ?? 0;
    const decTop: number = decH - decW;
    const pt: DragPoint = {
      x: ev.getWindowX() - decW,
      y: ev.getWindowY() - decTop
    };
    if (this.reqId === 1) {
      hilog.info(DOMAIN, TAG,
        'DRAG-COORD req=%d X/Y=(%d,%d) dec=(%d,%d) WinX/Y=(%d,%d) DisX/Y=(%d,%d)',
        this.reqId,
        Math.round(ev.getWindowX()), Math.round(ev.getWindowY()),
        Math.round(decW), Math.round(decTop),
        Math.round(ev.getWindowX()), Math.round(ev.getWindowY()),
        Math.round(ev.getDisplayX()), Math.round(ev.getDisplayY()));
    }
    return pt;
  }

  private forwardDrag(ev: DragEvent, kind: number): void {
    if (!this.dragEnabled()) return;
    try {
      const pt = this.dragCoords(ev);
      const types = this.serializeSummary(ev.getSummary());
      const sp: SummaryPayload = { types: types };
      hilog.info(DOMAIN, TAG, 'DRAG forward req=%d kind=%d pt=(%d,%d) types=%s',
        this.reqId, kind, Math.round(pt.x), Math.round(pt.y), JSON.stringify(types));
      fpbridge.onDragEvent(String(this.reqId), kind, pt.x, pt.y, JSON.stringify(sp));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'DRAG forward err req=%d kind=%d: %{public}s',
        this.reqId, kind, JSON.stringify(e));
    }
  }

  // Summary.summary（UTD 类型 → 数据大小映射）→ fpGUI mime 类型表
  // 宽松匹配：PlainText 的 getSummary key 实测可能是 'general.text' 而非
  // 'general.plain-text'（两者都映射 text/plain）；未知 key 也下发（mime 空），
  // Pascal 侧 LoadMimeTypesFromRecords 再做 records-type 兜底。
  private serializeSummary(s: Summary | undefined): Array<MimeTypeEntry> {
    const out: Array<MimeTypeEntry> = [];
    if (!s) return out;
    const keys: Array<string> = Object.keys(s.summary);
    for (const k of keys) {
      let mime = '';
      if (k === 'general.plain-text' || k === 'general.text' || k === 'general.hyperlink') {
        mime = 'text/plain';
      } else if (k === 'general.html') {
        mime = 'text/html';
      } else if (k === 'general.file-uri' || k === 'general.image' ||
        k === 'general.video' || k === 'general.audio' || k === 'general.folder') {
        mime = 'text/uri-list';
      }
      out.push({ utd: k, mime: mime });
    }
    return out;
  }

  // UnifiedRecord → recordsJson（Pascal SetDropDataFromRecords 解析）
  private serializeRecords(records: Array<unifiedDataChannel.UnifiedRecord>): string {
    const arr: Array<DropRecord> = [];
    for (const r of records) {
      const rec: DropRecord = { type: r.getType(), textContent: '', abstract: '', htmlContent: '', uri: '' };
      if (r instanceof unifiedDataChannel.PlainText) {
        rec.textContent = (r as unifiedDataChannel.PlainText).textContent ?? '';
        rec.abstract = (r as unifiedDataChannel.PlainText).abstract ?? '';
      } else if (r instanceof unifiedDataChannel.HTML) {
        rec.htmlContent = (r as unifiedDataChannel.HTML).htmlContent ?? '';
      } else if (r instanceof unifiedDataChannel.Image) {
        rec.uri = (r as unifiedDataChannel.Image).imageUri ?? '';
      } else if (r instanceof unifiedDataChannel.File) {
        rec.uri = (r as unifiedDataChannel.File).uri ?? '';
      }
      arr.push(rec);
    }
    return JSON.stringify(arr);
  }
}
