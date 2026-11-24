// ── 多实例主窗 Ability（multiton）─────────────────────────────────
// 由 Index 在收到 waSizeable 的普通/模态窗创建命令时 startAbility 拉起。
// 每个实例 = 独立的 WindowStage + 主窗口（真正的顶层主窗）。
// 窗口内容不在本 Ability 里加载：Index 完成尺寸/装饰/AppStorage 准备后，
// 通过 FpWindowRegistry 的 load 回调触发 loadContent，时序与子窗一致。
import { UIAbility, Want, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fpbridge from 'libfp_bridge.so';
import { registerAbilityWindow, bindContextReqId, unregisterAbilityWindow, markActiveWindow } from '../common/FpWindowRegistry';

const DOMAIN = 0x0000;
const TAG = 'fpbridge-Window';

const ATTR_BORDERLESS = 1 << 4;

export default class FpWindowAbility extends UIAbility {
  private reqId: number = 0;
  private winWidth: number = 0;
  private winHeight: number = 0;
  private winX: number = 0;
  private winY: number = 0;
  private winAttrs: number = 0;
  private winTitle: string = 'fpGUI';
  private stageWin: window.Window | null = null;
  private closedNotified: boolean = false;
  private contentLoaded: boolean = false;

  onCreate(want: Want): void {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params !== undefined) {
      const rid: number | undefined = params['fpWindowReqId'] as number | undefined;
      const w: number | undefined = params['fpWidth'] as number | undefined;
      const h: number | undefined = params['fpHeight'] as number | undefined;
      const x: number | undefined = params['fpX'] as number | undefined;
      const y: number | undefined = params['fpY'] as number | undefined;
      const a: number | undefined = params['fpAttrs'] as number | undefined;
      const t: string | undefined = params['fpTitle'] as string | undefined;
      if (rid !== undefined) this.reqId = rid;
      if (w !== undefined) this.winWidth = w;
      if (h !== undefined) this.winHeight = h;
      if (x !== undefined) this.winX = x;
      if (y !== undefined) this.winY = y;
      if (a !== undefined) this.winAttrs = a;
      if (t !== undefined) this.winTitle = t;
    }
    hilog.info(DOMAIN, TAG,
      'onCreate req=%{public}d size=%{public}dx%{public}d pos=(%{public}d,%{public}d) attrs=%{public}d title=%{public}s',
      this.reqId, this.winWidth, this.winHeight, this.winX, this.winY,
      this.winAttrs, this.winTitle);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    let win: window.Window | null = null;
    try {
      win = windowStage.getMainWindowSync();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'getMainWindowSync failed req=%{public}d: %{public}s',
        this.reqId, JSON.stringify(e));
    }
    if (win === null) {
      this.notifyClosed('no main window');
      try { this.context.terminateSelf().catch(() => {}); } catch (_e) {}
      return;
    }
    this.stageWin = win;

    const borderless: boolean = (this.winAttrs & ATTR_BORDERLESS) !== 0;
    try { win.setWindowDecorVisible(!borderless); } catch (_e) {}
    try { win.setWindowBackgroundColor('#F1F3F5'); } catch (_e) {}
    try {
      win.setWindowTitle(this.winTitle.length > 0 ? this.winTitle : 'fpGUI').catch(() => {});
    } catch (_e) {}

    // 预布局只做位置：尺寸交给 Index 的 createSubWin 管线（px 单位一致）。
    // 注意不要在这里 resize——Ability 主窗首次 resize 的取整/单位路径与
    // Index 的 Window 代理不同，实测会把 2280x1330 放大成 4370x2724。
    if (this.winX !== 0 || this.winY !== 0) {
      win.moveWindowTo(this.winX, this.winY).catch(() => {});
    }

    // 最小化按钮隐藏由 Index 在窗口显示后统一下发（此时调用会报 1300002）。

    // titleBar 期望由 Index 的 createSubWin 统一判定（此时取装饰高不可靠）：
    // 多实例主窗一律使用系统装饰，不再回退自绘标题栏。

    // 尽早监听激活：Ability 窗口可能在 Index 注册 windowEvent 之前就获焦，
    // 漏掉 WINDOW_ACTIVE 会让后续子窗挂到 id=1 主窗下（被本主窗挡住）。
    try {
      win.on('windowEvent', (t: number) => {
        if (t === 2) markActiveWindow(this.reqId);
      });
    } catch (_e) {}
    markActiveWindow(this.reqId);

    const reqId: number = this.reqId;
    bindContextReqId(this.context, reqId);
    const storage = new LocalStorage();
    storage.setOrCreate<number>('reqId', reqId);
    registerAbilityWindow(reqId, this.context, windowStage, win,
      (): Promise<void> => {
        hilog.info(DOMAIN, TAG, 'loadContent req=%{public}d storageReq=%{public}d',
          reqId, storage.get<number>('reqId') ?? -1);
        return windowStage.loadContent('pages/MainWindowSurface', storage).then(() => {
          this.contentLoaded = true;
        });
      });

    // 兜底：Index 若因超时/异常始终没请求加载内容，本实例会变成无内容空窗 →
    // 15s 后自行结束（C++ 创建等待上限 10s，留 5s 余量）。
    setTimeout(() => {
      if (this.contentLoaded) return;
      hilog.warn(DOMAIN, TAG,
        'content not requested in 15s -> terminate req=%{public}d', reqId);
      this.notifyClosed('content timeout');
      try { this.context.terminateSelf().catch(() => {}); } catch (_e) {}
    }, 15000);

    hilog.info(DOMAIN, TAG,
      'onWindowStageCreate req=%{public}d registered (content deferred)', reqId);
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy req=%{public}d', this.reqId);
    unregisterAbilityWindow(this.reqId);
    this.notifyClosed('stage destroy');
    this.stageWin = null;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy req=%{public}d', this.reqId);
    this.notifyClosed('ability destroy');
  }

  // 窗口销毁通知 Pascal/C++（释放 native window）。重复调用由 C++ 侧幂等兜底，
  // 这里再用标志位避免同一实例内重复发。
  private notifyClosed(reason: string): void {
    if (this.closedNotified || this.reqId <= 1) return;
    this.closedNotified = true;
    hilog.info(DOMAIN, TAG, 'notifyClosed req=%{public}d (%{public}s)', this.reqId, reason);
    try {
      fpbridge.onWindowClosed(this.reqId);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'onWindowClosed(req=%{public}d) failed: %{public}s',
        this.reqId, JSON.stringify(e));
    }
  }
}
