// libfp_bridge.so NAPI 类型声明（反向桥接版）
// ArkTS 通过 import fpbridge from 'libfp_bridge.so' 调用

// ── 启动 Pascal 应用 ──
// appLibName: 不带 lib 前缀与 .so 后缀，如 'helloworld' → libhelloworld.so
// launchPayload: 启动载荷 JSON（want.uri/action/entities/parameters 全量，可空）→ argv[1] → RunLazarus
// appArgs: 命令行参数（空格分隔；-b debug / key=value 风格，可空）→ Pascal ICmdLineParams
export const start: (appLibName: string, launchPayload?: string, appArgs?: string) => void;

// ── 热启动载荷推送（onNewWant）──
// payload 为 JSON 串：{"uri","action","entities","parameters"} → Pascal OnOhosLaunchParams 事件
export const setLaunchParams: (payload: string) => void;

// ── ETS 就绪信号 ──
export const setEtsReady: () => void;

// ── 沙箱路径设置 ──
// ArkTS onWindowStageCreate 中调用，传入 context 的全部目录属性
// 必须在 start() 前调用，使 C++ ohos_get_user_dir 返回真实沙箱路径
// 参数顺序对应 ohos_get_user_dir 的 dirType：
//   0=filesDir 1=cacheDir 2=tempDir 3=resourceDir 4=databaseDir
//   5=preferencesDir 6=bundleCodeDir 7=distributedFilesDir 8=cloudFileDir
export const setSandboxPaths: (
  filesDir: string, cacheDir: string, tempDir: string,
  resourceDir: string, databaseDir: string, preferencesDir: string,
  bundleCodeDir: string, distributedFilesDir: string, cloudFileDir: string
) => void;

// ── 原生回调注册（替代轮询） ──
// C++ 通过 napi_threadsafe_function 调用此回调投递命令。
// cmd.type: 0=create, 1=move, 2=show, 3=hide, 4=destroy, 5=shake, 6=show_keyboard,
//           7=resize, 8=tray_add, 9=tray_menu, 10=tray_remove, 11=timer_state,
//           12=pointer_style, 13=drag_start, 14=dnd_enabled, 15=window_state,
//           16=window_opacity, 17=window_title, 18=window_attributes
// 第二参数选择通道：'window'（Index 页面）或 'keyboard'（当前可见 WindowSurface 页面）
export const setNativeCallback: (callback: (cmd: object) => void, cbType?: string) => void;

// 注销当前页面的键盘回调（WindowSurface aboutToDisappear 调用）
export const releaseKeyboardCallback: () => void;

// ── 打开 URL / 文档 ──
// Pascal fpgOpenURL → C++ ohos_open_url → 本回调（JS 线程执行）
// ArkTS 侧用 openLink（API 12+）或 startAbility(viewData) 交给系统处理
export const registerOpenUrl: (callback: (url: string) => void) => void;

// ── Surface 就绪 ──
// ETS 在 XComponent.onLoad() 中调用
export const onSurfaceReady: (reqId: number, xcId: string, surfaceId: string, surfW?: number, surfH?: number) => void;

// ── 窗口属性 ──
export const onWindowResized: (reqId: number, w: number, h: number) => void;
export const onWindowMoved: (reqId: number, x: number, y: number) => void;
export const onWindowClosed: (reqId: number) => void;
export const queryCanClose: (reqId: number) => number;
export const refreshWindow: (reqId: number) => void;
export const setMainWindowDec: (decW: number, decH: number) => void;
export const setWindowDec: (reqId: number, decW: number, decH: number) => void;

// ── 事件注入 ──
export const onTouchEvent: (reqId: string, x: number, y: number, action: number) => void;
export const onMouseEvent: (reqId: string, x: number, y: number, action: number, button: number) => void;
export const onWheelEvent: (reqId: string, x: number, y: number, delta: number) => void;
export const onHoverEvent: (reqId: string, x: number, y: number) => void;
export const onKeyEvent: (keyCode: number, action: number, modifiers: number, unicode: number) => void;
export const onTextInput: (text: string) => void;
export const onDeleteChars: (count: number) => void;
export const onDeleteRightChars: (count: number) => void;
export const onImeMoveCursor: (direction: number) => void;
// ETS 主动请求显示/隐藏软键盘（状态同步，仅日志；弹/收由 FpgSurface 自行完成）
export const showKeyboard: (show: number) => void;

// ── 辅助 ──
export const getModalReqId: () => number;

// ── 系统托盘（HarmonyOS trayIcon，仅 2in1/PC） ──
// 托盘事件：0=左键点击, 1=右键点击, 2=菜单项选中(menuId), 3=add 结果回传("ok"/"fail")
export const onTrayEvent: (eventType: number, menuId: string) => void;

// ── 系统 Configuration ──
// kv 格式：紧凑 k=v;k2=v2;...（值不含 ';' 与 '='）
export const notifyConfiguration: (kv: string) => void;

// ── 定时器 ArkUI 注入 ──
export const timerTick: () => void;
export const timerQuery: () => number;

// ── 系统拖拽（Unified Drag & Drop） ──
export const onDragEvent: (reqId: string, kind: number, x: number, y: number, summaryJson: string) => void;
export const onDropEvent: (reqId: string, x: number, y: number, recordsJson: string) => number;
export const onDragEnd: (sessionId: number, result: number) => void;
export const isDndEnabled: (reqId: number) => boolean;

// ── 窗口状态缓存（v10） ──
// ETS windowStatusChange 事件触发时调用，更新 C++ 侧 per-window 状态缓存
// state: OHOS WindowStatusType（0=UNDEFINED 1=FULL_SCREEN 2=MAXIMIZE 3=MINIMIZE 4=FLOATING 5=SPLIT_SCREEN）
export const updateWindowState: (reqId: number, state: number) => void;

// ── 动态分发（Registry-Dispatch） ──
// 调用 Pascal 侧 RegisterSync/RegisterAsync 注册的 opType：
//   op     — 业务处理器名（大小写不敏感），如 'statusbar.ping'
//   params — JSON 字符串；无参传 '{}'
// 返回 Promise：resolve = 处理器返回的 JSON 字符串；reject = 未连接/已取消。
export const dispatch: (op: string, params: string) => Promise<string>;
// 取消进行中的异步分发（jobId 来自 dispatch 起步响应，可选）
export const dispatchCancel: (jobId: string) => void;

// ── 系统文件选择器结果回传（ETS FpgFilePicker → C++ → Pascal） ──
// reqId 与 ohos_show_file_picker 发起时一致；resultJson 为
// '{"uris":["file://..."],"code":0}'，code: 0=成功 -1=用户取消 -2=错误。
export const notifyFilePickerResult: (reqId: number, resultJson: string) => void;

// ── 系统文件流操作结果回传（ETS FpgFileIo → C++ → Pascal） ──
// reqId 与命令 21(ohos_file_io) 发起时一致。
// resultJson: '{"code":0,"n":123,"size":456,"handle":1}'
//   code=0 成功；handle=open 分配的句柄 id；n=read 字节数/write 字节数；size=操作后文件大小。
// data: 读操作返回的字节（其余操作传空 ArrayBuffer 或省略）。
export const notifyFileIoResult: (reqId: number, resultJson: string, data?: ArrayBuffer) => void;

// ── arkTS_Invoke：Pascal → ArkTS 方法注册（v13） ──
// 注册单个方法，name 为点分路径（如 'ui.showToast'），大小写归一（内部以小写一致）。
// fn 与注册同名，参数 string（JSON 串），需要 this 的方法请先 .bind(obj)。
export const registerInvokeMethod: (name: string, fn: (params: string) => string) => void;

// 命名空间/整体对象注册（推荐）：obj 沿原型链取自有属性（含非枚举的
// class 方法，以 class 实例传入即可），Object.prototype 的 'constructor'
// 不外露；函数自动 bind 到 obj 后注册为 'prefix.key'，子对象递归为 'prefix.sub.key'，
// 递归深度 8，方法总数上限 512，'_' 开头的键跳过，同名后注册覆盖先注册。
// 传入 function 时退化为 registerInvokeMethod(prefix, fn)。
export const registerInvokeNamespace: (prefix: string, obj: object | Function) => void;

// 可选统一分发接口：注册后所有未命中方法时以 (method, params) => string 调用。
export const registerInvokeDispatcher: (fn: (method: string, params: string) => string) => void;

export const unregisterInvokeMethod: (name: string) => void;
// 全清位：清空方法表 + 分发器（Ability onDestroy / 热重启时调用）。
export const clearInvokeMethods: () => void;
// 已注册方法的展示名列表（原始大小写，与入参一致）。
export const listInvokeMethods: () => string[];
// JS 线程直查注册表同步执行（跨进程 relay 自测用；
// 永不抛异常，失败以错误信封字符串返回）。
export const invokeLocal: (method: string, params: string) => string;