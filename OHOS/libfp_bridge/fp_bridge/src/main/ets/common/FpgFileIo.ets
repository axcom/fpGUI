// 系统文件流桥（Pascal TOhosFileStream → C++ ohos_file_io → 本文件）
// ─────────────────────────────────────────────────────────────────────────
// 对文件选择器授权的 file:// URI 做同步随机读写。所有 fs API 均使用 *Sync 版本，
// 在命令派发（JS 线程）内一次完成并立即 notifyFileIoResult 回传，Pascal 侧同步等待。
//
// 命令字段（NativeCommand，type=21）：
//   x=子操作(FileIoOp)  y=参数（open 时=OpenMode 位掩码，其余操作=ETS 句柄 id）
//   offset/length=文件偏移/长度  payload=URI（open/stat/delete）  data=写数据 ArrayBuffer
// 回复 JSON：{"code":0,"errCode":0,"handle":1,"n":123,"size":456}
//   code=0 成功，-2=错误；read 额外回传 data（实际字节数 n 的 ArrayBuffer）
import fpbridge from 'libfp_bridge.so';
// 本工程 SDK 的 @kit.CoreFileKit 不导出 fs（编译报 arkts 10505001），
// 统一用稳定模块 @ohos.file.fs 的默认导出；fs.File/fs.Stat 与 *Sync API 不变。
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'fpGUI-fileio';

// 文件流子操作（与 C++ FileIoOp、Pascal TFileIoOp 严格一致）
export enum FileIoOp {
  OPEN = 0,
  READ = 1,
  WRITE = 2,
  TRUNCATE = 3,
  FSYNC = 4,
  CLOSE = 5,
  STAT = 6,
  DELETE = 7
}

// 与 Index.ets NativeCommand 中文件流用到的字段对齐（显式接口，禁 any）
export interface FileIoCommand {
  reqId: number;
  x: number;
  y: number;
  offset: number;
  length: number;
  payload: string;
  data: ArrayBuffer;
}

// 已打开句柄表：handle id → fs.File（Pascal 侧 TOhosFileStream 一一对应）
const openHandles: Map<number, fs.File> = new Map();
let nextHandleId: number = 1;

// 统一回传（read 带 data，其余操作 data 省略）
function reply(reqId: number, code: number, errCode: number,
  handle: number, n: number, size: number, data?: ArrayBuffer): void {
  const json: string =
    '{"code":' + code.toString() +
    ',"errCode":' + errCode.toString() +
    ',"handle":' + handle.toString() +
    ',"n":' + n.toString() +
    ',"size":' + size.toString() + '}';
  try {
    if (data !== undefined) {
      fpbridge.notifyFileIoResult(reqId, json, data);
    } else {
      fpbridge.notifyFileIoResult(reqId, json);
    }
  } catch (e) {
    hilog.error(DOMAIN, TAG,
      'reply failed req=%{public}d: %{public}s', reqId, JSON.stringify(e));
  }
}

// 从 catch 到的对象提取 BusinessError.code。ArkTS 禁止 in 运算符
// （arkts-no-in），用 Record 索引取值 + typeof 判定；非 BusinessError 抛出返回 0。
function errorCodeOf(e: Object): number {
  const v: Object = (e as Record<string, Object>)['code'];
  return (typeof v === 'number') ? v as number : 0;
}

function fail(reqId: number, e: Object, where: string): void {
  const ec: number = errorCodeOf(e);
  hilog.error(DOMAIN, TAG, '%{public}s failed code=%{public}d: %{public}s',
    where, ec, JSON.stringify(e));
  reply(reqId, -2, ec, 0, 0, -1);
}

function fsizeFd(fd: number): number {
  try {
    return fs.statSync(fd).size;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'statSync(fd) failed: %{public}s', JSON.stringify(e));
    return -1;
  }
}

function doOpen(cmd: FileIoCommand): void {
  // openSync(uri, mode)：mode 为 OpenMode 位掩码（READ_ONLY/READ_WRITE/CREATE/TRUNC...），
  // 直接透传 Pascal 侧按 fmOpenRead/fmCreate 等翻译的结果。
  const file: fs.File = fs.openSync(cmd.payload, cmd.y);
  const handle: number = nextHandleId++;
  openHandles.set(handle, file);
  const size: number = fsizeFd(file.fd);
  hilog.info(DOMAIN, TAG, 'open h=%{public}d fd=%{public}d mode=%{public}d size=%{public}d',
    handle, file.fd, cmd.y, size);
  reply(cmd.reqId, 0, 0, handle, 0, size);
}

function doRead(cmd: FileIoCommand): void {
  const file: fs.File | undefined = openHandles.get(cmd.y);
  if (file === undefined) {
    reply(cmd.reqId, -2, 0, cmd.y, 0, -1);
    return;
  }
  const want: number = cmd.length;
  const buf: ArrayBuffer = new ArrayBuffer(want);
  // ReadOptions.offset 为文件偏移（pread 语义，不移动共享句柄读写位置）
  const n: number = fs.readSync(file.fd, buf, { offset: cmd.offset, length: want });
  // 短读（EOF）时只回传实际字节，避免 Pascal 收到尾部零字节
  const out: ArrayBuffer = (n === want) ? buf : buf.slice(0, n);
  reply(cmd.reqId, 0, 0, cmd.y, n, fsizeFd(file.fd), out);
}

function doWrite(cmd: FileIoCommand): void {
  const file: fs.File | undefined = openHandles.get(cmd.y);
  if (file === undefined) {
    reply(cmd.reqId, -2, 0, cmd.y, 0, -1);
    return;
  }
  // WriteOptions.offset 为文件偏移（pwrite 语义）
  const n: number = fs.writeSync(file.fd, cmd.data,
    { offset: cmd.offset, length: cmd.data.byteLength });
  reply(cmd.reqId, 0, 0, cmd.y, n, fsizeFd(file.fd));
}

function doTruncate(cmd: FileIoCommand): void {
  const file: fs.File | undefined = openHandles.get(cmd.y);
  if (file === undefined) {
    reply(cmd.reqId, -2, 0, cmd.y, 0, -1);
    return;
  }
  fs.truncateSync(file.fd, cmd.length);
  reply(cmd.reqId, 0, 0, cmd.y, 0, fsizeFd(file.fd));
}

function doFsync(cmd: FileIoCommand): void {
  const file: fs.File | undefined = openHandles.get(cmd.y);
  if (file === undefined) {
    reply(cmd.reqId, -2, 0, cmd.y, 0, -1);
    return;
  }
  fs.fsyncSync(file.fd);
  reply(cmd.reqId, 0, 0, cmd.y, 0, fsizeFd(file.fd));
}

function doClose(cmd: FileIoCommand): void {
  const file: fs.File | undefined = openHandles.get(cmd.y);
  if (file === undefined) {
    // 重复关闭按成功处理（幂等），避免 Pascal finally 路径报错
    reply(cmd.reqId, 0, 0, cmd.y, 0, -1);
    return;
  }
  fs.closeSync(file);
  openHandles.delete(cmd.y);
  reply(cmd.reqId, 0, 0, cmd.y, 0, -1);
}

function doStat(cmd: FileIoCommand): void {
  // 不开句柄取大小：供 FileExists / URI 预检；不存在或无权限抛错 → code=-2
  const st: fs.Stat = fs.statSync(cmd.payload);
  reply(cmd.reqId, 0, 0, 0, 0, st.size);
}

function doDelete(cmd: FileIoCommand): void {
  // 删除 picker 授权 URI（能否成功取决于授权类型与文件管理器实现）
  fs.unlinkSync(cmd.payload);
  reply(cmd.reqId, 0, 0, 0, 0, -1);
}

// 命令 21 入口（由 Index.handleNativeCommand 同步调用）
export function handleFileIo(cmd: FileIoCommand): void {
  try {
    switch (cmd.x) {
      case FileIoOp.OPEN:
        doOpen(cmd);
        break;
      case FileIoOp.READ:
        doRead(cmd);
        break;
      case FileIoOp.WRITE:
        doWrite(cmd);
        break;
      case FileIoOp.TRUNCATE:
        doTruncate(cmd);
        break;
      case FileIoOp.FSYNC:
        doFsync(cmd);
        break;
      case FileIoOp.CLOSE:
        doClose(cmd);
        break;
      case FileIoOp.STAT:
        doStat(cmd);
        break;
      case FileIoOp.DELETE:
        doDelete(cmd);
        break;
      default:
        hilog.error(DOMAIN, TAG, 'unknown fileio op=%{public}d req=%{public}d',
          cmd.x, cmd.reqId);
        reply(cmd.reqId, -2, 0, 0, 0, -1);
    }
  } catch (e) {
    fail(cmd.reqId, e as Object, 'fileio op' + cmd.x.toString());
  }
}
