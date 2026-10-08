// OpenHarmony 版托盘后端（降级实现）
// 背景：系统托盘（statusBarManager / @kit.DeskTopExtensionKit / trayIcon）为
//   HarmonyOS 专属 API——OpenHarmony SDK 无任何等价声明（ArkTS 静态 import，
//   无法在单文件内按 SDK 分支）。本文件为同公开 API 的空实现：
//   - add/setMenu/remove 仅日志（托盘不可用）
//   - add 立即回传 evType=3 'fail' → Pascal gTrayActive=False →
//     IsSystemTrayAvailable=false → 窗口关闭/退出走既有降级逻辑（不依赖托盘）
// 构建期由 tools/prebuild.ps1 按 build-profile.json5 的 runtimeOS 选择：
//   HarmonyOS   → TrayManager.harmony.ets（完整实现）
//   OpenHarmony → TrayManager.open.ets（本文件）
// 公共导入路径保持 '../common/TrayManager'（Index.ets 零改动）。
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fpbridge from 'libfp_bridge.so';

const DOMAIN = 0x0000;
const TAG = 'fpGUI-tray';

export class TrayManager {
  private static inst: TrayManager | null = null;
  private ctx: common.UIAbilityContext | null = null;

  static getInstance(): TrayManager {
    if (!TrayManager.inst) {
      TrayManager.inst = new TrayManager();
    }
    return TrayManager.inst;
  }

  init(ctx: common.UIAbilityContext): void {
    this.ctx = ctx;
  }

  // OpenHarmony：托盘不可用 → 回传 fail（Pascal 侧降级判定）
  async add(title: string): Promise<void> {
    hilog.warn(DOMAIN, TAG, 'Tray unavailable (OpenHarmony), add ignored');
    fpbridge.onTrayEvent(3, 'fail');
  }

  async setMenu(json: string): Promise<void> {
    hilog.warn(DOMAIN, TAG, 'Tray unavailable (OpenHarmony), setMenu ignored');
  }

  async remove(): Promise<void> {
    hilog.warn(DOMAIN, TAG, 'Tray unavailable (OpenHarmony), remove ignored');
  }
}
