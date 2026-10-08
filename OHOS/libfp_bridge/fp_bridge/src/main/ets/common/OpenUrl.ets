/*
 * fpGUI OHOS bridge — ArkTS side: open URL / document with system handler.
 *
 * Registered with the native bridge once during ability start:
 *     import fpbridge from 'libfp_bridge.so';
 *     import { bindOpenUrlContext, openUrl } from '../common/OpenUrl';
 *     bindOpenUrlContext(this.context);
 *     fpbridge.registerOpenUrl(openUrl);
 *
 * Uses two strategies:
 *   1. API 12+ : openLink()  — the recommended high-level API that asks the
 *      system to choose the default app for the URL / file type.
 *   2. Fallback : startAbility() with want action 'ohos.want.action.viewData'
 *      and the URL as uri, for older API levels.
 */

import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'fpGUI_openUrl';

let ctx: common.UIAbilityContext | null = null;

/** Bind the ability context. Call from Fp_bridgeAbility.onWindowStageCreate(). */
export function bindOpenUrlContext(c: common.UIAbilityContext): void {
  ctx = c;
}

/**
 * Open a URL (http/https/mailto/...) or a local document with the system
 * default handler.  Safe to call from the native bridge (JS thread).
 */
export async function openUrl(url: string): Promise<void> {
  if (!url) {
    return;
  }
  if (!ctx) {
    hilog.error(DOMAIN, TAG, 'openUrl: ability context not bound');
    return;
  }

  // ---- Strategy 1: openLink (API 12+, recommended) ---------------------
  // openLink picks the default browser / document viewer automatically.
  // Available as a typed method on UIAbilityContext since API 12.
  try {
    await ctx.openLink(url);
    return;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'openLink failed, falling back to startAbility: %{public}s', JSON.stringify(e));
  }

  // ---- Strategy 2: startAbility with viewData want --------------------
  const want: Want = {
    action: 'ohos.want.action.viewData',
    uri: url,
  };
  try {
    await ctx.startAbility(want);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'startAbility(viewData) failed for %{public}s: %{public}s',
      url, JSON.stringify(e));
  }
}