// 定时器 ArkUI 注入驱动（TfpgOhosTimer）
// 背景：fpGUI 框架定时器由 fpgCheckTimers 检查，驱动源本为 select 超时轮询
//   （cap 500ms：功耗/精度/后台饿死风险）。改为：本文件以 setInterval 精确
//   tick → fpbridge.timerTick() → C++ → Pascal ohos_timer_tick → WakeChannel.Signal
//   唤醒 select → 事件循环照常 fpgCheckTimers。
// 自适应：Pascal 经命令通道类型 11 通知启停（有活动定时器才起 tick，零轮询）；
//   initTimerDaemon（Index NapiReady 后）用 timerQuery 补查一次，防早期通知丢失。
import fpbridge from 'libfp_bridge.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'fpGUI-timer';

// tick 粒度（ms）—— 可调常量：范围内 10~50 均可，默认 15（UI 帧级）。
export const TimerTickMs = 15;

let gIntervalId = -1;
let gStarted = false;

function tick(): void {
  try {
    fpbridge.timerTick();
  } catch (e) {
    // NAPI 未就绪/so 卸载：静默，下轮重试
  }
}

export function startTimerTick(): void {
  if (gStarted) return;
  gStarted = true;
  gIntervalId = setInterval(tick, TimerTickMs);
  hilog.info(DOMAIN, TAG, 'Timer tick started (%{public}d ms)', TimerTickMs);
}

export function stopTimerTick(): void {
  if (!gStarted) return;
  gStarted = false;
  if (gIntervalId >= 0) {
    clearInterval(gIntervalId);
    gIntervalId = -1;
  }
  hilog.info(DOMAIN, TAG, 'Timer tick stopped');
}

// Index NapiReady 后调用一次：补查当前是否有活动定时器（Pascal 早发通知
// 到达时若 Index 回调尚未注册会被 C++ 丢弃）。返回最近一次状态。
export function initTimerDaemon(): void {
  try {
    const active: number = fpbridge.timerQuery();
    hilog.info(DOMAIN, TAG, 'TimerDaemon init: active=%{public}d', active);
    if (active > 0) {
      startTimerTick();
    }
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'TimerDaemon init failed: %{public}s', String(e));
  }
}