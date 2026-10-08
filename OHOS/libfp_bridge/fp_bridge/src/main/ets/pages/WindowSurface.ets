import fpbridge from 'libfp_bridge.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FpgSurface, FpgSurfaceCtrl } from '../common/FpgSurface';

const DOMAIN = 0x0000;
const TAG = 'page-window';

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
struct WindowSurface {
  // reqId is read ONCE at page construction (see aboutToAppear). It must NOT
  // be a reactive @StorageLink to the shared 'currentReqId' key: that key is
  // overwritten by every later-created window, so the main window's page
  // would silently start reporting ITS touches as the popup's reqId after
  // the popup closes (misrouted events + stale-rect coordinate garbage).
  @State reqId: number = 0;
  private imeCtrl: FpgSurfaceCtrl = new FpgSurfaceCtrl();

  aboutToAppear(): void {
    // Pin this page's own reqId (Index.ets sets 'currentReqId' right before
    // setUIContent loads this page, so the read is per-window correct).
    // One-shot on purpose: a later-created window must not rebind us.
    this.reqId = AppStorage.get<number>('currentReqId') ?? 0;
    /* Keyboard callback channel: window management commands (0-5) go to the
      Index page ('window' channel); SHOW_KEYBOARD (6) is routed by C++ to
      this page ('keyboard' channel), the currently visible WindowSurface.
      Pages are stacked: registering pushes, aboutToDisappear pops, so the
      previous window's page resumes receiving keyboard commands. */
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
    hilog.info(DOMAIN, TAG, 'WindowSurface: keyboard callback registered');
  }

  aboutToDisappear(): void {
    fpbridge.releaseKeyboardCallback();
    hilog.info(DOMAIN, TAG, 'WindowSurface: keyboard callback released');
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
        hilog.warn(DOMAIN, TAG, 'WindowSurface: unexpected native command type=%d', cmd.type);
    }
  }

  build() {
    Stack() {
      // XComponent/IME/事件转发全部在公共组件 FpgSurface 内
      FpgSurface({ reqId: this.reqId, ctrl: this.imeCtrl })
    }
    .width('100%').height('100%')
  }
}
