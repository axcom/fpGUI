// fpGUI 动态分发 ArkTS 便捷包装
// =============================
// libfp_bridge.so 的 dispatch(op, paramsJson) 返回原始 JSON 字符串；
// dispatchAsync 统一 JSON.stringify 入参并 JSON.parse 出参。
import fpbridge from 'libfp_bridge.so';

// 调用 Pascal RegisterSync/RegisterAsync 注册的处理器，返回解析后的对象。
// 例：const r = await dispatchAsync('statusbar.ping', { from: 'ets' });
export async function dispatchAsync(op: string, params: object): Promise<object> {
  const raw: string = await fpbridge.dispatch(op, JSON.stringify(params));
  return JSON.parse(raw) as object;
}

// 泛型版本：调用方自行指定结果类型。
export async function dispatchObject<T>(op: string, params: object): Promise<T> {
  const raw: string = await fpbridge.dispatch(op, JSON.stringify(params));
  return JSON.parse(raw) as T;
}

// 异步作业便捷调用（与同步同签名；返回值在 Pascal 后台线程完成后 resolve）。
export function dispatchAsyncText(op: string, paramsJson: string): Promise<string> {
  return fpbridge.dispatch(op, paramsJson);
}

// 原始入口（不解析 JSON）：需要自行处理错误信封时使用。
export function dispatchRaw(op: string, paramsJson: string): Promise<string> {
  return fpbridge.dispatch(op, paramsJson);
}

// 取消进行中的异步分发（jobId 来自起步响应）。
export function dispatchCancel(jobId: string): void {
  fpbridge.dispatchCancel(jobId);
}
