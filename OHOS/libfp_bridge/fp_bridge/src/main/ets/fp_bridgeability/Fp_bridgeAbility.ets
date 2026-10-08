import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';
import fpbridge from 'libfp_bridge.so';
import { startDispatchRelay, stopDispatchRelay } from '../common/FpDispatchRelay';
import { bindOpenUrlContext, openUrl } from '../common/OpenUrl';
import { APP_ARGS, WANT_PARAM_ARGS } from '../common/FpAppConfig';
import type { Configuration } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'fpbridge-Entry';

let gWindowStage: window.WindowStage | null = null;
let gAbility: UIAbility | null = null;

// ── 启动载荷（want.uri/action/entities/parameters 全量 JSON）────────
// 冷启动：Index.ets start(appLib, payload) → C++ argv[1] → RunLazarus；
// 热启动：onNewWant → fpbridge.setLaunchParams(payload) → Pascal 事件。
let gLaunchPayload: string = '';
let gLastWarmPush: string = '';

function buildLaunchPayload(want: Want | null): string {
  if (!want) return '';
  const payload: Record<string, Object> = {};
  if (want.uri !== undefined && want.uri !== null && want.uri !== '') {
    payload['uri'] = want.uri;
  }
  if (want.action !== undefined && want.action !== null && want.action !== '') {
    payload['action'] = want.action;
  }
  if (want.entities !== undefined && want.entities !== null && want.entities.length > 0) {
    payload['entities'] = want.entities;
  }
  if (want.parameters !== undefined && want.parameters !== null &&
    Object.keys(want.parameters).length > 0) {
    payload['parameters'] = want.parameters;
  }
  return JSON.stringify(payload);
}

function setLaunchPayload(want: Want | null): void {
  const payload = buildLaunchPayload(want);
  if (payload === '') return;
  gLaunchPayload = payload;
  // 热启动推送（去重：同一载荷不重复推，Pascal 侧逐条消费）
  if (payload !== gLastWarmPush) {
    gLastWarmPush = payload;
    try {
      fpbridge.setLaunchParams(payload);
      hilog.info(DOMAIN, TAG, 'Warm launch params pushed: %{public}s', payload);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setLaunchParams failed: %{public}s', JSON.stringify(err));
    }
  }
}

export function getLaunchPayload(): string {
  return gLaunchPayload;
}

// ── 命令行参数合并（静态 APP_ARGS + want.parameters['fpArgs']）────────
let gMergedArgs: string = '';

export function getMergedArgs(): string {
  return gMergedArgs;
}

function buildMergedArgs(want: Want | null): string {
  let args = APP_ARGS;
  if (want && want.parameters && want.parameters[WANT_PARAM_ARGS]) {
    const dynamicArgs = String(want.parameters[WANT_PARAM_ARGS] || '');
    if (dynamicArgs.length > 0) {
      args = args.length > 0 ? args + ' ' + dynamicArgs : dynamicArgs;
    }
  }
  return args;
}

// ── 系统 Configuration 首启/变化下发（ArkTS 侧仅"源头转发"）────────
// 设计：
// - Native 可原生读取的字段（den/denKonf/d/i/fs）在 C++ 侧 fp_bridge_init
//   预初始化时读取，Pascal 表装载后一次下发（首帧缩放正确）；
// - 本侧只发不可原生字段（l/c/p/f/fw/mcc/mnc/lc）+ 运行期 direction。
// - 对比：ETS 缓存上次下发 KV，未变化不推送；Pascal 侧另有全局对比兜底。
let gLastPushedCfg = '';

function buildConfigurationKV(cfg: Configuration | null): string {
  if (!cfg) return '';
  let kv = '';
  if (cfg.language !== undefined && cfg.language !== null) {
    kv += `l=${cfg.language};`;
  }
  if (cfg.colorMode !== undefined && cfg.colorMode !== null) {
    kv += `c=${cfg.colorMode};`;
  }
  if (cfg.direction !== undefined && cfg.direction !== null) {
    kv += `d=${cfg.direction};`;
  }
  if (cfg.hasPointerDevice !== undefined && cfg.hasPointerDevice !== null) {
    kv += `p=${cfg.hasPointerDevice ? '1' : '0'};`;
  }
  if (cfg.fontId !== undefined && cfg.fontId !== null && cfg.fontId !== '') {
    kv += `f=${cfg.fontId};`;
  }
  if (cfg.fontWeightScale !== undefined && cfg.fontWeightScale !== null) {
    kv += `fw=${cfg.fontWeightScale.toFixed(4)};`;
  }
  if (cfg.mcc !== undefined && cfg.mcc !== null) {
    kv += `mcc=${cfg.mcc};`;
  }
  if (cfg.mnc !== undefined && cfg.mnc !== null) {
    kv += `mnc=${cfg.mnc};`;
  }
  if (cfg.locale !== undefined && cfg.locale !== null) {
    kv += `lc=${cfg.locale.toString()};`;
  }
  return kv;
}

function pushConfiguration(cfg: Configuration | null): void {
  const kv = buildConfigurationKV(cfg);
  if (kv === '' || kv === gLastPushedCfg) return;
  gLastPushedCfg = kv;
  try {
    fpbridge.notifyConfiguration(kv);
    hilog.info(DOMAIN, TAG, 'Config pushed: %{public}s', kv);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'notifyConfiguration failed: %{public}s', JSON.stringify(err));
  }
}

// 12/24 小时制 + 日期格式（settings；@ohos.settings 无观察者，按约定仅启动读一次）。
// 值：TIME_FORMAT='12'/'24'；DATE_FORMAT='mm/dd/yyyy'|'dd/mm/yyyy'|'yyyy/mm/dd'（均不含 ';'/'='）。
// 走同一 notifyConfiguration 通道（g_pendingConfig 兜底时序），Pascal 仅存储对比幂等。
function readDateTimeFormat(): void {
  if (!gAbility) return;
  try {
    const ctx = gAbility.context;
    Promise.all([
      settings.getValue(ctx, settings.date.TIME_FORMAT, settings.domainName.USER_PROPERTY),
      settings.getValue(ctx, /*settings.date.DATE_FORMAT*/'dateFormat', settings.domainName.USER_PROPERTY)]).then((vals: string[]): void => {
      const kv = `tf=${vals[0]};df=${vals[1]};`;
      fpbridge.notifyConfiguration(kv);
      hilog.info(DOMAIN, TAG, 'DateTimeFormat pushed: %{public}s', kv);
    }).catch((err: Error): void => {
      const msg: string = (err && (err as Error).message) ? (err as Error).message : String(err);
      //hilog.error(DOMAIN, TAG, 'read DateTimeFormat failed: %{public}s', msg);
      hilog.error(DOMAIN, TAG, 'read DateTimeFormat failed: err=%{public}s, type=%{public}s',
        JSON.stringify(err), typeof err);
    });
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'read DateTimeFormat error: %{public}s | %{public}s',
      String(err), JSON.stringify(err));
  }
}

export function getWindowStage(): window.WindowStage | null {
  return gWindowStage;
}

// 主窗口（Ability 应用窗口）：供 Index.ets 控制尺寸/位置/全屏/装饰
export function getMainWindow(): window.Window | null {
  if (gWindowStage === null) return null;
  try {
    return gWindowStage.getMainWindowSync();
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'getMainWindow failed: %{public}s', JSON.stringify(err));
    return null;
  }
}

export function terminateAbility(): void {
  if (gAbility) {
    try {
      gAbility.context.terminateSelf();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}s', JSON.stringify(err));
    }
  } else {
    hilog.warn(DOMAIN, TAG, 'terminateAbility: gAbility is null, skipping');
  }
}

export default class Fp_bridgeAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    gAbility = this;
    setLaunchPayload(want);   // 冷启动：捕获 want.uri/action/entities/parameters
    gMergedArgs = buildMergedArgs(want);  // 合并静态参数和 want 动态参数
    if (gMergedArgs.length > 0) {
      hilog.info(DOMAIN, TAG, 'Merged appArgs: %{public}s', gMergedArgs);
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate (exit-friendly)');
    // 跨进程 dispatch 中继：随 Ability 生命周期（不依赖 Index 页面）
    startDispatchRelay();
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 热启动：更新合并参数
    setLaunchPayload(want);
    gMergedArgs = buildMergedArgs(want);
    hilog.info(DOMAIN, TAG, 'onNewWant: appArgs=%{public}s', gMergedArgs);
  }

  onDestroy(): void {
    stopDispatchRelay();
    gAbility = null;
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    gWindowStage = windowStage;

    // 沙箱路径注入：必须在 start() 前调用，使 C++ ohos_get_user_dir 返回真实沙箱路径
    try {
      const ctx = this.context;
      fpbridge.setSandboxPaths(
        ctx.filesDir, ctx.cacheDir, ctx.tempDir,
        ctx.resourceDir, ctx.databaseDir, ctx.preferencesDir,
        ctx.bundleCodeDir, ctx.distributedFilesDir, ctx.cloudFileDir
      );
      hilog.info(DOMAIN, TAG, 'setSandboxPaths: files=%{public}s cache=%{public}s temp=%{public}s',
        ctx.filesDir, ctx.cacheDir, ctx.tempDir);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setSandboxPaths failed: %{public}s', JSON.stringify(err));
    }

    // 打开 URL / 文档回调注册：Pascal fpgOpenURL → ohos_open_url → openUrl
    try {
      bindOpenUrlContext(this.context);
      fpbridge.registerOpenUrl(openUrl);
      hilog.info(DOMAIN, TAG, 'OpenUrl callback registered');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'registerOpenUrl failed: %{public}s', JSON.stringify(err));
    }

    // 首启补推不可原生字段（原生 scale 类字段已由 C++ fp_bridge_init 下发）。
    try {
      pushConfiguration(this.context.config);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'init config push failed: %{public}s', JSON.stringify(err));
    }

    // 启动读一次 12/24 小时制 + 日期格式（settings；无观察者，不轮询）。
    readDateTimeFormat();

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load Index page: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Index page loaded');
    });
  }

  // 系统配置变化（语言/深浅色/横竖屏/指针设备/字体缩放/网络等）。
  // 首次启动不触发；首启值由以上 this.context.config 补推。
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onConfigurationUpdate');
    pushConfiguration(newConfig);
  }

  onWindowStageDestroy(): void {
    gWindowStage = null;
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}