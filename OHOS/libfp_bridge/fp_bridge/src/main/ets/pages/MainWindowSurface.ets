// ── 多实例主窗内容页 ─────────────────────────────────────────────
// 由 FpWindowAbility.onWindowStageCreate 通过
// windowStage.loadContent('pages/MainWindowSurface', storage) 加载。
// reqId 来自该窗口私有的 LocalStorage（不是全局 AppStorage.currentReqId），
// 多实例并发创建时不会串窗。
import fpbridge from 'libfp_bridge.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { FpgSurface, FpgSurfaceCtrl } from '../common/FpgSurface';
import { reqIdForContext } from '../common/FpWindowRegistry';

const DOMAIN = 0x0000;
const TAG = 'page-mainwindow';

const NATIVE_CMD_SHOW_KEYBOARD: number = 6;

interface NativeCommand {
  type: number;
  reqId: number;
  x: number;
  y: number;
  width: number;
  height: number;
  xcId: string;
}

@Entry
@Component
struct MainWindowSurface {
  // 每个 Ability 实例的 loadContent 传入独立 LocalStorage，天然 per-window。
  @LocalStorageProp('reqId') reqId: number = 0;
  private imeCtrl: FpgSurfaceCtrl = new FpgSurfaceCtrl();

  aboutToAppear(): void {
    // LocalStorage 是首选通道；部分版本在页面首帧前不填充 @LocalStorageProp，
    // 用 AbilityContext 身份 → reqId 的模块级映射兜底（同一进程，对象身份稳定）。
    if (this.reqId <= 0) {
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const fallback: number = reqIdForContext(hostCtx);
      if (fallback > 0) this.reqId = fallback;
    }
    hilog.info(DOMAIN, TAG,
      'MainWindowSurface aboutToAppear req=%{public}d shared=%{public}d',
      this.reqId, LocalStorage.getShared()?.get<number>('reqId') ?? -1);
    fpbridge.setNativeCallback((cmdObj: object) => {
      const cmd: NativeCommand = {
        type: cmdObj['type'] as number,
        reqId: cmdObj['reqId'] as number,
        x: cmdObj['x'] as number,
        y: cmdObj['y'] as number,
        width: cmdObj['width'] as number,
        height: cmdObj['height'] as number,
        xcId: cmdObj['xcId'] as string
      };
      this.handleNativeCommand(cmd);
    }, 'keyboard');
  }

  aboutToDisappear(): void {
    fpbridge.releaseKeyboardCallback();
    hilog.info(DOMAIN, TAG, 'MainWindowSurface aboutToDisappear req=%{public}d', this.reqId);
  }

  private handleNativeCommand(cmd: NativeCommand): void {
    switch (cmd.type) {
      case NATIVE_CMD_SHOW_KEYBOARD:
        if (cmd.x > 0) {
          if (this.imeCtrl.showIme) this.imeCtrl.showIme(cmd.x);
        } else {
          if (this.imeCtrl.hideIme) this.imeCtrl.hideIme();
        }
        break;
      default:
        hilog.warn(DOMAIN, TAG, 'unexpected native command type=%d', cmd.type);
        break;
    }
  }

  build() {
    Stack() {
      FpgSurface({ reqId: this.reqId, ctrl: this.imeCtrl })
    }
    .width('100%').height('100%')
  }
}
