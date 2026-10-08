// 系统文件选择器桥（Pascal TfpgOhosFilePicker → C++ ohos_show_file_picker → 本文件）
// ─────────────────────────────────────────────────────────────────────────
// 四类系统选择器（均无需申请权限，由系统 FileManager/Gallery 拉起）：
//   PickerType.DOCUMENT(0)      → picker.DocumentViewPicker.select（CoreFileKit）
//   PickerType.PHOTO(1)         → photoAccessHelper.PhotoViewPicker（MediaLibraryKit）
//   PickerType.AUDIO(2)         → picker.AudioViewPicker（CoreFileKit）
//   PickerType.DOCUMENT_SAVE(3) → picker.DocumentViewPicker.save（另存为，回传可写 URI）
// Pascal 侧同步阻塞等待结果；本函数 await select() 后把统一格式 JSON 回传：
//   fpbridge.notifyFilePickerResult(reqId, '{"uris":[...],"code":0}')
//   code: 0=成功 -1=用户取消 -2=错误
// 注意：select() 返回的 URI 为只读临时权限，应用退出后失效；持久化需应用层
// 自行 fileIo.persistPermission，且官方警告不要在 pick 回调里立即打开文件。
// save()（type=3）返回的是可写 URI（目标文件已创建/由用户确认覆盖），
// Pascal 侧用 TOhosFileStream(fmCreate) 打开写入即可。
import fpbridge from 'libfp_bridge.so';
import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'fpGUI-picker';

// picker 类型（与 C++ ohos_show_file_picker 的 pickerType 参数一致）
export enum PickerType {
  DOCUMENT = 0,
  PHOTO = 1,
  AUDIO = 2,
  DOCUMENT_SAVE = 3    // 文档"另存为"：DocumentViewPicker.save
}

// Pascal 传来的 optsJson 解析结果
interface PickerOpts {
  suffix?: string[];   // 文档后缀过滤，如 ['.txt', '.pdf']
  max?: number;        // 最大选择数（0/缺省=系统默认，通常 1）
  mime?: string;       // 图片/视频：'image' | 'video' | 'image_video'（缺省=image_video）
  name?: string;       // DOCUMENT_SAVE：预填的新文件名（含后缀，如 'ESC.INF'）
}

function parseOpts(json: string): PickerOpts {
  try {
    return JSON.parse(json) as PickerOpts;
  } catch (_e) {
    return {};
  }
}

// 统一结果回传（保证任何分支都通知一次，避免 Pascal 侧死等至 120s 超时）
function notifyResult(reqId: number, uris: string[], code: number): void {
  const result: string = JSON.stringify({ uris: uris, code: code });
  try {
    fpbridge.notifyFilePickerResult(reqId, result);
  } catch (e) {
    hilog.error(DOMAIN, TAG,
      'notifyResult failed req=%{public}d: %{public}s', reqId, JSON.stringify(e));
  }
}

// 实际拉起系统选择器并回传结果（async：不向调用方抛异常，结果一律走 notifyResult）
async function runPicker(
  context: common.Context,
  reqId: number,
  type: number,
  optsJson: string
): Promise<void> {
  const opts: PickerOpts = parseOpts(optsJson);
  let uris: string[] = [];
  let code: number = 0;
  try {
    switch (type) {
      case PickerType.DOCUMENT: {
        const p: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
        const so: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
        if (opts.suffix !== undefined && opts.suffix.length > 0) {
          so.fileSuffixFilters = opts.suffix;
        }
        if (opts.max !== undefined && opts.max > 0) {
          so.maxSelectNumber = opts.max;
        }
        hilog.info(DOMAIN, TAG, 'document picker req=%{public}d', reqId);
        const r: string[] = await p.select(so);
        uris = r ?? [];
        break;
      }
      case PickerType.PHOTO: {
        const p: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
        const so: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
        if (opts.mime === 'video') {
          so.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
        } else if (opts.mime === 'image') {
          so.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
        } else {
          so.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
        }
        if (opts.max !== undefined && opts.max > 0) {
          so.maxSelectNumber = opts.max;
        }
        hilog.info(DOMAIN, TAG, 'photo picker req=%{public}d mime=%{public}s', reqId, opts.mime ?? 'image_video');
        const r: photoAccessHelper.PhotoSelectResult = await p.select(so);
        uris = r.photoUris ?? [];
        break;
      }
      case PickerType.AUDIO: {
        const p: picker.AudioViewPicker = new picker.AudioViewPicker(context);
        const so: picker.AudioSelectOptions = new picker.AudioSelectOptions();
        if (opts.max !== undefined && opts.max > 0) {
          so.maxSelectNumber = opts.max;
        }
        hilog.info(DOMAIN, TAG, 'audio picker req=%{public}d', reqId);
        const r: string[] = await p.select(so);
        uris = r ?? [];
        break;
      }
      case PickerType.DOCUMENT_SAVE: {
        // 文档"另存为"：save() 返回可写 URI（目标文件由系统创建；
        // 同名时系统 FileManager 弹覆盖确认框，用户确认即可写）。
        const p: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
        const so: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
        if (opts.suffix !== undefined && opts.suffix.length > 0) {
          so.fileSuffixChoices = opts.suffix;
        }
        if (opts.name !== undefined && opts.name.length > 0) {
          // newFileNames 在对话框中预填文件名（用户仍可修改）；API 10+ 稳定字段
          so.newFileNames = [opts.name];
        }
        hilog.info(DOMAIN, TAG, 'document save picker req=%{public}d name=%{public}s',
          reqId, opts.name ?? '');
        const r: string[] = await p.save(so);
        uris = r ?? [];
        break;
      }
      default:
        hilog.error(DOMAIN, TAG, 'unknown picker type=%{public}d req=%{public}d', type, reqId);
        code = -2;
    }
  } catch (e) {
    // 用户取消常见 BusinessError：13900042（picker 取消/未知错误）、13900015；
    // 部分版本 message 含 'cancel'。其余按错误处理。
    const ec: number = (e !== null && e !== undefined && e.code !== undefined) ? e.code : 0;
    const msg: string = (e !== null && e !== undefined && e.message !== undefined)
      ? e.message : JSON.stringify(e);
    if (ec === 13900042 || ec === 13900015 ||
        msg.includes('cancel') || msg.includes('Cancel')) {
      code = -1;
      hilog.info(DOMAIN, TAG, 'picker canceled req=%{public}d code=%{public}d', reqId, ec);
    } else {
      code = -2;
      hilog.error(DOMAIN, TAG,
        'picker failed req=%{public}d code=%{public}d msg=%{public}s', reqId, ec, msg);
    }
  }
  notifyResult(reqId, uris, code);
}

// 拉起文件选择器（fire-and-forget：内部全捕获，完成时自行回传结果）
export function showFilePicker(
  context: common.Context,
  reqId: number,
  type: number,
  optsJson: string
): void {
  runPicker(context, reqId, type, optsJson);
}
