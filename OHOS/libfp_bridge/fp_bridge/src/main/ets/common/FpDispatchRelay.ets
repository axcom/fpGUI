// 跨进程 dispatch 中继（主进程侧，Pascal 所在）
// ==================================================
// 订阅扩展进程发来的 DISPATCH_REQ，调用本进程的 libfp_bridge.so
// （Pascal 动态分发）并把结果发回 DISPATCH_RESP。
// 生命周期：由 Fp_bridgeAbility.onCreate 启动、onDestroy 注销（不依赖页面）。
import { commonEventManager, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import fpbridge from 'libfp_bridge.so';

const DOMAIN = 0x0000;
const TAG = 'FpDispatchRelay';
const REQ_EVENT = 'com.example.ax.fpGUI.DISPATCH_REQ';
const RESP_EVENT = 'com.example.ax.fpGUI.DISPATCH_RESP';
const INVOKE_RESP_EVENT = 'com.example.ax.fpGUI.INVOKE_RESP';

let started: boolean = false;
// 必须持有订阅者引用：局部变量会被 GC，导致动态订阅失效（漏收 REQ 事件）
let relaySubscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;

function respond(clientId: number, reqId: number, result: string): void {
  const data: commonEventManager.CommonEventPublishData = {
    parameters: { clientId: clientId, reqId: reqId, result: result }
  };
  commonEventManager.publish(RESP_EVENT, data, () => {});
}

// 与既有 respond 同构，仅事件名不同：invoke 走专用回程通道，
// 与 DISPATCH_RESP 上的 dispatch 响应结构性隔离（见 §10.4）。
function respondInvoke(clientId: number, reqId: number, result: string): void {
  const data: commonEventManager.CommonEventPublishData = {
    parameters: { clientId: clientId, reqId: reqId, result: result }
  };
  commonEventManager.publish(INVOKE_RESP_EVENT, data, () => {});
}

export function startDispatchRelay(): void {
  if (started) {
    return;
  }
  const info: commonEventManager.CommonEventSubscribeInfo = { events: [REQ_EVENT] };
  try {
    relaySubscriber = commonEventManager.createSubscriberSync(info);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'createSubscriberSync failed: %{public}s', JSON.stringify(e));
    return;
  }
  commonEventManager.subscribe(relaySubscriber,
    (err: BusinessError, data: commonEventManager.CommonEventData) => {
      if (err) {
        hilog.warn(DOMAIN, TAG, 'subscribe err: %{public}s', JSON.stringify(err));
        return;
      }
      const ps = data.parameters;
      if (ps === undefined) {
        return;
      }
      const clientId = ps['clientId'] as number;
      const reqId = ps['reqId'] as number;
      const kind = (ps['kind'] as string) ?? 'call';
      const op = (ps['op'] as string) ?? '';
      const pjson = (ps['params'] as string) ?? '{}';

      if (kind === 'cancel') {
        const jobId = (ps['jobId'] as string) ?? '';
        hilog.info(DOMAIN, TAG, 'relay cancel id=%{public}d job=%{public}s', reqId, jobId);
        try {
          fpbridge.dispatchCancel(jobId);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'cancel failed: %{public}s', JSON.stringify(e));
        }
        respond(clientId, reqId, '{"ok":true,"cancelRequested":true}');
        return;
      }

      if (kind === 'invoke') {
        const method = (ps['method'] as string) ?? '';
        hilog.info(DOMAIN, TAG, 'relay invoke c=%{public}d id=%{public}d m=%{public}s',
          clientId, reqId, method);
        // 主进程 JS 线程直查注册表同步执行（不经 TSFN，不绕 Pascal，无排队）
        // pjson 即 :51 已提取的 (ps['params'] as string) ?? '{}'
        respondInvoke(clientId, reqId, fpbridge.invokeLocal(method, pjson));
        return;
      }

      hilog.info(DOMAIN, TAG, 'relay req c=%{public}d id=%{public}d op=%{public}s',
        clientId, reqId, op);
      // 拦截 showSecondForm：注入预创建 XComponent 的 surfaceId（string 类型）
      let finalParams = pjson;
      if (op === 'showSecondForm') {
        try {
          const parsed = JSON.parse(pjson) as Record<string, string>;
          if (!parsed.surfaceId || parsed.surfaceId === '') {
            const sid = AppStorage.get<string>('embeddedSurfaceId_99') ?? '';
            if (sid !== '') {
              parsed.surfaceId = sid;
              finalParams = JSON.stringify(parsed);
              hilog.info(DOMAIN, TAG, 'relay inject surfaceId=%{public}s into showSecondForm', sid);
            }
          }
        } catch (_e) {}
      }
      fpbridge.dispatch(op, finalParams).then((r: string) => {
        respond(clientId, reqId, r);
      }).catch((e: Error) => {
        respond(clientId, reqId,
          '{"ok":false,"code":"RELAY","error":"relay: ' + (e.message ?? 'error') + '"}');
      });
    });
  started = true;
  hilog.info(DOMAIN, TAG, 'dispatch relay started');
}

export function stopDispatchRelay(): void {
  if (!started || relaySubscriber === undefined) {
    started = false;
    return;
  }
  try {
    commonEventManager.unsubscribe(relaySubscriber, () => {});
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'unsubscribe failed: %{public}s', JSON.stringify(e));
  }
  relaySubscriber = undefined;
  started = false;
  hilog.info(DOMAIN, TAG, 'dispatch relay stopped');
}
