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
import { fileUri } from '@kit.CoreFileKit';
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

  // ---- Local file: turn the sandbox path into a shareable FileUri ------
  let target: string = url;
  if (target.startsWith('file://')) {
    target = target.substring(7);
  }
  let localFile: boolean = false;
  if (target.startsWith('/')) {
    localFile = true;
    try {
      target = new fileUri.FileUri(target).toString();
      hilog.info(DOMAIN, TAG, 'local file uri: %{public}s', target);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'FileUri conversion failed: %{public}s', JSON.stringify(e));
      target = url;
    }
  }

  // ---- Strategy 1: openLink (API 12+, recommended) ---------------------
  // openLink handles web/app links; local files go through viewData below
  // so the read grant flag reaches the viewer.
  if (!localFile) {
    try {
      await ctx.openLink(target);
      return;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'openLink failed, falling back to startAbility: %{public}s', JSON.stringify(e));
    }
  }

  // ---- Strategy 2: startAbility with viewData want --------------------
  const want: Want = {
    action: 'ohos.want.action.viewData',
    uri: target,
  };
  if (localFile) {
    want.type = 'application/pdf';
    // FLAG_AUTH_READ_URI_PERMISSION lets the viewer read the app's file URI.
    want.flags = 1;
  }
  try {
    await ctx.startAbility(want);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'startAbility(viewData) failed for %{public}s: %{public}s',
      target, JSON.stringify(e));
  }
}