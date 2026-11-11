import { AbilityConstant, ConfigurationConstant, UIAbility, Want, abilityAccessCtrl } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';
import { inputDevice } from '@kit.InputKit';
import fpbridge from 'libfp_bridge.so';
import { startDispatchRelay, stopDispatchRelay } from '../common/FpDispatchRelay';
import { bindOpenUrlContext, openUrl } from '../common/OpenUrl';
import { APP_ARGS, WANT_PARAM_ARGS } from '../common/FpAppConfig';
import type { Configuration, Context, PermissionRequestResult, Permissions } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'fpbridge-Entry';

let gWindowStage: window.WindowStage | null = null;
let gAbility: UIAbility | null = null;

// ── 启动时申请的 user_grant 权限 ─────────────────────────────────────
// 启动只申请 READ_PASTEBOARD；其它 user_grant 权限先保留在数组中（注释），
// 真正用到对应能力时取消注释即可。
// PC/2in1：READ_PASTEBOARD 首次申请系统默认允许，不弹窗。
// 手机/平板：会弹一次授权框，用户允许后长期有效。
const STARTUP_PERMISSIONS: Array<Permissions> = [
  // debug 签名包会因 grant 失败装不上；且每次启动都会弹授权框。
  // 若将来确需系统剪贴板读取，需在 profile 里加 ACL 并在真正用到时再请求。
  'ohos.permission.READ_PASTEBOARD', // 它是受限权限，需要 profile 的 ACL（系统签名才有）
  // 以下按需开启：
  // 'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY',  // 文档目录
  // 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY',   // Download (下载)
  // 'ohos.permission.READ_WRITE_DCIM_DIRECTORY',       // DCIM (相机目录)
  // 'ohos.permission.READ_WRITE_PICTURES_DIRECTORY',   // Pictures (图片)
  // 'ohos.permission.READ_WRITE_VIDEOS_DIRECTORY',     // Videos (视频)
  // 'ohos.permission.READ_WRITE_MUSIC_DIRECTORY',      // Music (音乐)
  // 'ohos.permission.READ_WRITE_AUDIOS_DIRECTORY',     // Audios (录音/音频)
  // 'ohos.permission.CAMERA',
  // 'ohos.permission.MICROPHONE',
  // 'ohos.permission.CUSTOM_SCREEN_CAPTURE',
  // 'ohos.permission.APPROXIMATELY_LOCATION',
  // 'ohos.permission.LOCATION',
  // 'ohos.permission.ACCESS_BLUETOOTH'
];
let gStartupPermissionsRequested = false;

function requestStartupPermissions(ctx: Context): void {
  if (gStartupPermissionsRequested) return;
  gStartupPermissionsRequested = true;
  if (STARTUP_PERMISSIONS.length === 0) return;   // 无启动权限：不弹任何授权框
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(ctx, STARTUP_PERMISSIONS)
      .then((result: PermissionRequestResult) => {
        hilog.info(DOMAIN, TAG, 'startup permissions=%{public}s authResults=%{public}s',
          JSON.stringify(result.permissions), JSON.stringify(result.authResults));
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'startup permission request failed: %{public}s',
          JSON.stringify(err));
      });
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'startup permission request error: %{public}s',
      JSON.stringify(err));
  }
}

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

// ── 物理键盘探测 ────────────────────────────────────────────────
// Configuration 没有键盘字段，只能查 multimodalInput 的设备表：
// 过滤虚拟设备（软键盘 isVirtual=true），看 sources 里有没有 'keyboard'。
// 变化时单独推 `kbd=0/1;`，Pascal 侧置 CFG_CHANGED_KEYBOARD。
let gKeyboardPushed: number = -1;   // -1 = 尚未推送

async function probeKeyboard(): Promise<void> {
  let has: boolean = false;
  try {
    const ids: number[] = await inputDevice.getDeviceIds();
    for (const id of ids) {
      const dev: inputDevice.InputDeviceData = await inputDevice.getDevice(id);
      if (!dev) continue;
      const isKbd: boolean = dev.sources !== undefined &&
        dev.sources.indexOf('keyboard') >= 0;
      const isVirtual: boolean = dev.isVirtual === true;
      // 诊断：设备表很小，且只在启动/热插拔时打印，便于确认真机与模拟器差异。
      hilog.info(DOMAIN, TAG,
        'input device id=%{public}d name=%{public}s virtual=%{public}s kbd=%{public}s',
        id, dev.name, isVirtual ? '1' : '0', isKbd ? '1' : '0');
      if (!isVirtual && isKbd) has = true;
    }
  } catch (err) {
    // 查询失败（权限/服务异常）时按“没有键盘”处理，让按键栏照常出现。
    hilog.error(DOMAIN, TAG, 'probeKeyboard failed: %{public}s', JSON.stringify(err));
  }
  const v: number = has ? 1 : 0;
  if (v === gKeyboardPushed) return;
  gKeyboardPushed = v;
  const kv: string = 'kbd=' + v + ';';
  try {
    fpbridge.notifyConfiguration(kv);
    hilog.info(DOMAIN, TAG, 'Keyboard pushed: %{public}s', kv);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'notifyConfiguration(kbd) failed: %{public}s',
      JSON.stringify(err));
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
    // 尽早探测物理键盘：kbd KV 若在 Pascal 连接前到达，会在 fp_bridge_init
    // 里补发（pending flush），窗口首帧就能拿到正确的按键栏状态。
    probeKeyboard();
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

    // 物理键盘有无（Configuration 里没有这个字段，靠 inputDevice 探测）：
    // 首查已在 onCreate 发起；这里只挂热插拔监听，变化时重查并按 kbd 推送。
    try {
      inputDevice.on('change', () => {
        probeKeyboard();
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'inputDevice.on(change) failed: %{public}s',
        JSON.stringify(err));
    }

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
    requestStartupPermissions(this.context);
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}