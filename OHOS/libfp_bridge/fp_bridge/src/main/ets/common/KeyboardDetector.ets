// 物理键盘检测（"PC 模式"判定——不弹软键盘）
// 背景：deviceInfo.deviceType 在 OpenHarmony 模拟器上返回 'tablet'
//   （BMSExt/SCB 按兼容 tablet 处理）→ 此前 IS_PC_DEVICE 只判 '2in1' 失效，
//   触屏判定下 showTextInput 弹软键盘。
// 方案：@kit.InputKit inputDevice 物理键盘检测（最贴合 PC 语义）：
//   - initKeyboardDetector：遍历设备 → getKeyboardTypeSync === ALPHABETIC_KEYBOARD
//   - 注册 on('change') 热插拔监听，动态更新
// 真平板（无物理键盘）→ 不弹软键盘的判定不成立 → 保留软键盘（不误伤）
import { inputDevice } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'fpGUI-Keyboard';

let gHasPhysicalKeyboard: boolean = false;
let gMonitorStarted: boolean = false;

export function hasPhysicalKeyboard(): boolean {
  return gHasPhysicalKeyboard;
}

async function refresh(): Promise<void> {
  try {
    let found = false;
    const list = await inputDevice.getDeviceList();
    for (let i = 0; i < list.length; ++i) {
      try {
        if (inputDevice.getKeyboardTypeSync(list[i]) === inputDevice.KeyboardType.ALPHABETIC_KEYBOARD) {
          found = true;
          break;
        }
      } catch (_e) {}
    }
    gHasPhysicalKeyboard = found;
    hilog.info(DOMAIN, TAG, 'KeyboardDetector: physical=%{public}d devices=%{public}d',
      found ? 1 : 0, list.length);
  } catch (_e) {
    gHasPhysicalKeyboard = false;
    hilog.warn(DOMAIN, TAG, 'KeyboardDetector: refresh failed, assuming no physical kb');
  }
}

export function initKeyboardDetector(): void {
  refresh().catch(() => {});
  if (gMonitorStarted) return;
  gMonitorStarted = true;
  try {
    inputDevice.on('change', () => {
      hilog.info(DOMAIN, TAG, 'KeyboardDetector: input device changed, recheck');
      refresh().catch(() => {});
    });
  } catch (_e) {
    hilog.warn(DOMAIN, TAG, 'KeyboardDetector: on(change) unavailable');
  }
}
