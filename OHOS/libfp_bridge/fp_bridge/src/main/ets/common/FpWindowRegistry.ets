// ── 多实例主窗注册表 ─────────────────────────────────────────────
// waSizeable 的普通/模态窗通过 FpWindowAbility（multiton）启动新 Ability 实例：
// 每个实例拥有独立的 WindowStage 主窗，这才是系统层面真正的顶层主窗。
// 所有实例与主 Index 页面在同一个进程/JS VM 中，用模块级 Map 共享窗口对象；
// Index 的 subWinMap 登记同一个 Window 代理，窗口命令（move/show/hide/resize/
// destroy）可直接作用于它，无需修改 C++ 命令路由。
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

export interface AbilityWindowEntry {
  win: window.Window;
  stage: window.WindowStage;
  ctx: common.UIAbilityContext;
  // 页面加载延迟到 Index 完成 AppStorage（winHandle_/decH_/titleBar_…）准备之后，
  // 与子窗 setUIContent 的时序保持一致（FpgSurface.aboutToAppear 要读这些键）。
  load: () => Promise<void>;
  loaded: boolean;
}

const entries: Map<number, AbilityWindowEntry> = new Map();
// 最近获得焦点的窗口 reqId。由各 Ability 的 windowEvent 与 Index 共同更新；
// 子窗建到哪个 WindowStage 依赖它（新主窗的激活事件可能早于 Index 的监听器，
// 所以必须在 Ability 侧尽早监听）。
let activeWindowReqId: number = 1;

export function markActiveWindow(reqId: number): void {
  if (reqId > 0) activeWindowReqId = reqId;
}

export function getActiveWindowReqId(): number {
  return activeWindowReqId;
}
// 页面无法直接拿到 reqId 时的兜底：AbilityContext 对象身份 → reqId。
// （LocalStorage 在部分版本/加载时序下可能读不到，见 MainWindowSurface）
const ctxReqIds: Map<common.UIAbilityContext, number> = new Map();

export function bindContextReqId(ctx: common.UIAbilityContext, reqId: number): void {
  ctxReqIds.set(ctx, reqId);
}

export function reqIdForContext(ctx: common.UIAbilityContext | undefined): number {
  if (ctx === undefined) return 0;
  const r: number | undefined = ctxReqIds.get(ctx);
  return r !== undefined ? r : 0;
}

export function registerAbilityWindow(reqId: number, ctx: common.UIAbilityContext,
    stage: window.WindowStage, win: window.Window,
    load: () => Promise<void>): void {
  entries.set(reqId, {
    win: win,
    stage: stage,
    ctx: ctx,
    load: load,
    loaded: false
  });
}

export function getAbilityWindow(reqId: number): window.Window | null {
  const e: AbilityWindowEntry | undefined = entries.get(reqId);
  return e !== undefined ? e.win : null;
}

// 子窗必须建在所属顶层主窗的 WindowStage 上，才会以该主窗为父窗，
// 否则会被挂到 id=1 主窗下 → 从新主窗弹出的对话框被新主窗挡住。
export function getAbilityWindowStage(reqId: number): window.WindowStage | null {
  const e: AbilityWindowEntry | undefined = entries.get(reqId);
  return e !== undefined ? e.stage : null;
}

// Ability 被系统关闭（任务栏 ×/系统回收）时清理注册表，避免残留死窗口对象。
export function unregisterAbilityWindow(reqId: number): void {
  const e: AbilityWindowEntry | undefined = entries.get(reqId);
  if (e !== undefined) {
    ctxReqIds.delete(e.ctx);
  }
  entries.delete(reqId);
}

// 由 Index 在窗口属性/AppStorage 就绪后调用：加载该实例的页面。
export async function loadAbilityWindowContent(reqId: number): Promise<boolean> {
  const e: AbilityWindowEntry | undefined = entries.get(reqId);
  if (e === undefined) return false;
  if (e.loaded) return true;
  e.loaded = true;
  try {
    await e.load();
    return true;
  } catch (_e) {
    entries.delete(reqId);
    return false;
  }
}

// 销毁窗口：结束对应的 Ability 实例（窗口随实例销毁）。
export function closeAbilityWindow(reqId: number): void {
  const e: AbilityWindowEntry | undefined = entries.get(reqId);
  if (e === undefined) return;
  entries.delete(reqId);
  ctxReqIds.delete(e.ctx);
  try {
    e.ctx.terminateSelf().catch(() => {});
  } catch (_e) {}
}

// 退出应用：结束所有顶层主窗实例（主 Ability 的 terminateSelf 不会带上它们）。
export function closeAllAbilityWindows(): void {
  const ids: number[] = [];
  entries.forEach((_e: AbilityWindowEntry, id: number) => { ids.push(id); });
  for (let i = 0; i < ids.length; i++) {
    closeAbilityWindow(ids[i]);
  }
}

// 等待新实例完成 onWindowStageCreate（startAbility 异步，窗口对象稍后才出现）。
// 与 150ms 轮询不同，这里 30ms 起步，避免拖慢 ohos_create_window 的 10s 等待。
export function waitForAbilityWindow(reqId: number, timeoutMs: number): Promise<window.Window | null> {
  return new Promise<window.Window | null>((resolve: (w: window.Window | null) => void) => {
    const startAt: number = Date.now();
    const tick = (): void => {
      const w: window.Window | null = getAbilityWindow(reqId);
      if (w !== null) {
        resolve(w);
        return;
      }
      if (Date.now() - startAt >= timeoutMs) {
        resolve(null);
        return;
      }
      setTimeout(tick, 30);
    };
    tick();
  });
}
