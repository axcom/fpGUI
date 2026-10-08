// 跨进程 arkTS_Invoke 代理（StatusBarView 扩展进程侧）
// ================================================
// 扩展进程无 Pascal、无业务 ArkTS 注册，经 commonEvent 中继到主进程执行。
// 与 FpDispatchProxy.dispatchViaMain 同构，但：
//  - 请求走既有 DISPATCH_REQ（kind='invoke'，与既有 kind='cancel' 同款模式）；
//  - 回程走专用 INVOKE_RESP，**不订 DISPATCH_RESP** —— 与 FpDispatchProxy
//    结构性隔离，clientId/reqId 即使同值也互不可见（§10.4 撞号问题由此消除，
//    FpDispatchProxy 无需任何改动）。
import { commonEventManager, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'FpInvokeProxy';
const REQ_EVENT = 'com.example.ax.fpGUI.DISPATCH_REQ';
const INVOKE_RESP_EVENT = 'com.example.ax.fpGUI.INVOKE_RESP';

interface PendingEntry {
  resolve: (v: string) => void;
  reject: (e: Error) => void;
  timer: number;
}

// 进程内唯一客户端 id（与 FpDispatchProxy 同款算法；通道已隔离，
// 此 id 只用于本通道内区分多个扩展实例）
const CLIENT_ID: number = Date.now() % 1000000007;
const pending: Map<number, PendingEntry> = new Map<number, PendingEntry>();
let seq: number = 0;
let subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;
let subscribing: boolean = false;

function ensureSubscriber(): void {
  if (subscriber !== undefined || subscribing) {
    return;
  }
  subscribing = true;
  const info: commonEventManager.CommonEventSubscribeInfo = { events: [INVOKE_RESP_EVENT] };
  try {
    subscriber = commonEventManager.createSubscriberSync(info);
  } catch (e) {
    subscribing = false;
    hilog.error(DOMAIN, TAG, 'createSubscriberSync failed: %{public}s', JSON.stringify(e));
    return;
  }
  commonEventManager.subscribe(subscriber,
    (err: BusinessError, data: commonEventManager.CommonEventData) => {
      if (err) {
        hilog.warn(DOMAIN, TAG, 'subscribe err: %{public}s', JSON.stringify(err));
        return;
      }
      const ps = data.parameters;
      if (ps === undefined) {
        return;
      }
      if ((ps['clientId'] as number) !== CLIENT_ID) {
        return;
      }
      const reqId = ps['reqId'] as number;
      const result = (ps['result'] as string) ?? '';
      const p = pending.get(reqId);
      if (p !== undefined) {
        pending.delete(reqId);
        clearTimeout(p.timer);
        p.resolve(result);          // 成功与错误信封统一 resolve，调用方 JSON 判断 ok
      }
    });
}

// 经主进程执行已注册的 ArkTS 方法，返回结果 JSON 字符串。
export function invokeViaMain(method: string, params: string,
    timeoutMs: number = 8000): Promise<string> {
  ensureSubscriber();
  return new Promise<string>((resolve, reject) => {
    const reqId = ++seq;
    const timer = setTimeout(() => {
      pending.delete(reqId);
      reject(new Error('invokeViaMain timeout (main process/relay unavailable)'));
    }, timeoutMs);
    pending.set(reqId, { resolve: resolve, reject: reject, timer: timer });
    const data: commonEventManager.CommonEventPublishData = {
      parameters: {
        clientId: CLIENT_ID, reqId: reqId,
        kind: 'invoke', method: method, params: params
      }
    };
    commonEventManager.publish(REQ_EVENT, data, (err: BusinessError) => {
      if (err) {
        const p = pending.get(reqId);
        if (p !== undefined) {
          pending.delete(reqId);
          clearTimeout(p.timer);
        }
        reject(new Error('publish invoke req failed: ' + JSON.stringify(err)));
      }
    });
  });
}
