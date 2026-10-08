// 跨进程 dispatch 代理（StatusBarView 扩展进程侧）
// ================================================
// StatusBarView 由 StatusBarViewExtensionAbility 承载，运行在独立进程
// （com.example.ax.fpGUI:statusBarView），该进程内没有启动 Pascal 应用，
// 因此 fpbridge.dispatch 会返回 "dispatch not connected"。
// 这里通过 commonEvent 把请求中继到主进程（Pascal 所在），由主进程调用
// fpbridge.dispatch 后回传结果。
import { commonEventManager, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'FpDispatchProxy';
const REQ_EVENT = 'com.example.ax.fpGUI.DISPATCH_REQ';
const RESP_EVENT = 'com.example.ax.fpGUI.DISPATCH_RESP';

interface PendingEntry {
  resolve: (value: string) => void;
  reject: (reason: Error) => void;
  timer: number;
}

// 进程内唯一客户端 id（避免多扩展实例 reqId 碰撞）
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
  const info: commonEventManager.CommonEventSubscribeInfo = { events: [RESP_EVENT] };
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
        return;   // 其它扩展实例的响应
      }
      const reqId = ps['reqId'] as number;
      const result = (ps['result'] as string) ?? '';
      const p = pending.get(reqId);
      if (p !== undefined) {
        pending.delete(reqId);
        clearTimeout(p.timer);
        p.resolve(result);
      }
    });
}

// 经主进程中继调用 Pascal 注册的 dispatch 处理器，返回结果 JSON 字符串。
export function dispatchViaMain(op: string, params: string,
    timeoutMs: number = 8000): Promise<string> {
  ensureSubscriber();
  return new Promise<string>((resolve, reject) => {
    const reqId = ++seq;
    const timer = setTimeout(() => {
      pending.delete(reqId);
      reject(new Error('dispatchViaMain timeout (main process/relay unavailable)'));
    }, timeoutMs);
    pending.set(reqId, { resolve: resolve, reject: reject, timer: timer });

    const data: commonEventManager.CommonEventPublishData = {
      parameters: { clientId: CLIENT_ID, reqId: reqId, op: op, params: params }
    };
    commonEventManager.publish(REQ_EVENT, data, (err: BusinessError) => {
      if (err) {
        const p = pending.get(reqId);
        if (p !== undefined) {
          pending.delete(reqId);
          clearTimeout(p.timer);
        }
        reject(new Error('publish dispatch req failed: ' + JSON.stringify(err)));
      }
    });
  });
}

// 请求取消某异步作业（透传到主进程 fpbridge.dispatchCancel）。
// 注：当前 API 不回传起步 jobId；本函数供已持有 jobId 的调用方使用。
export function cancelViaMain(jobId: string, timeoutMs: number = 3000): Promise<string> {
  ensureSubscriber();
  return new Promise<string>((resolve, reject) => {
    const reqId = ++seq;
    const timer = setTimeout(() => {
      pending.delete(reqId);
      reject(new Error('cancelViaMain timeout'));
    }, timeoutMs);
    pending.set(reqId, { resolve: resolve, reject: reject, timer: timer });

    const data: commonEventManager.CommonEventPublishData = {
      parameters: {
        clientId: CLIENT_ID, reqId: reqId, kind: 'cancel', jobId: jobId
      }
    };
    commonEventManager.publish(REQ_EVENT, data, (err: BusinessError) => {
      if (err) {
        const p = pending.get(reqId);
        if (p !== undefined) {
          pending.delete(reqId);
          clearTimeout(p.timer);
        }
        reject(new Error('publish cancel failed: ' + JSON.stringify(err)));
      }
    });
  });
}
