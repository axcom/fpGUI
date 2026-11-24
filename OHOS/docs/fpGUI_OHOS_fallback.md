# OHOS 字体回退与 fonts.ini

## 1. 背景

fpGUI 控件的 `Font` 只能指定一种字体。一个 Memo 使用 Arial 时，英文由 Arial 绘制，但 Arial 文件本身没有中文字形。

OHOS 的 ArkUI 文本组件会由系统自动做字体回退，但 fpGUI 的绘制走低层 `OH_Drawing`：

```text
Memo.Font = Arial
  → OH_Drawing 使用 Arial typeface
  → 遇到“中”没有字形
  → TextBlob 直接画 .notdef（问号）
```

因此必须在渲染层显式实现字体回退（Font Linking）。这不是“每个 Memo 指定两种字体”，而是“主字体缺字形时切换到回退字体”。

另外，应用沙箱不能通过 `/system/fonts/...` 路径读取系统字体，`FileExists` 会失败；系统字体必须通过 FontMgr API 获取。

## 2. 设计目标

- 应用只提供字体文件和可选配置，不修改 fpGUI 框架。
- 没有配置文件时也能工作：自动扫描系统字体和应用字体。
- 应用可以指定“基础字体 → 中文字体”的优先顺序。
- 支持文件名字体、系统字体家族名、沙箱字体路径。
- 回退字体必须真正包含目标字符；不能只看文件是否存在。
- 保留 Arial 英文字形，只对缺失的中文字形切换字体。

## 3. fonts.ini 格式

文件位置：

```text
resfile/fonts.ini
```

也可以放在 `resfile/fonts/fonts.ini`；框架会按 `OhosFindFontFile` 的搜索目录查找。

格式：

```ini
# 基础字体 = 回退候选，按顺序用逗号分隔
Arial=SimSun
Times New Roman=SimSun
Calibri=Microsoft YaHei

# 所有字体都会在显式映射后追加这一组公共兜底
*=simsun.ttc,HarmonyOS Sans SC
```

规则：

- `#` 或 `;` 开头的行是注释。
- 空行忽略。
- 键是 Memo 的基础字体名，大小写不敏感。
- 值按逗号分隔，前一个字体找不到或不含目标字符时继续试下一个。
- `*` 是所有字体的公共兜底列表：先使用显式映射，再追加 `*` 的候选。
- 文件不存在时，框架使用自身默认列表 + 系统字体 + 沙箱扫描。

候选的写法：

| 写法 | 含义 |
|---|---|
| `simsun.ttc` | 应用沙箱字体文件，按文件名查找；文件不存在时该候选直接失败，不再转系统家族 |
| `simsun.ttc#1` | TTC 字体集合的索引 1（NSimSun） |
| `SimSun` | 先按文件名候选查找；找不到再按系统字体家族查找 |
| `HarmonyOS Sans SC` | 系统字体家族名，通过 FontMgr 解析 |
| `file:simsun.ttc` | 强制按文件解析 |
| `family:HarmonyOS Sans SC` | 强制按系统家族解析 |

注意：不要写 `/system/fonts/...` 绝对路径。应用沙箱下 `FileExists` 会失败，必须使用系统字体家族名。

## 4. 回退顺序

对一个 Memo 的字体：

```text
1. 主字体（例如 arial.ttf）
2. fonts.ini 中该基础字体的显式候选列表（按顺序）
3. fonts.ini 中 `*` 的公共兜底候选（按顺序）
4. 系统 FontMgr 按目标字符匹配
5. 扫描应用字体目录（resfile、resfile/fonts、filesDir/fonts、libs/<abi>/fonts）
6. 框架默认列表
```

`OhosCJKFontFiles` 现在只是第 5 步的框架默认值，默认为空。应用不应修改这个常量来配置自己的字体，使用 `fonts.ini` 即可。

如果没有 `fonts.ini`：

```text
主字体
  → 系统 FontMgr 按字符匹配
  → 应用字体扫描
```

这满足“先系统、后沙箱”的默认行为。

## 5. 实现说明

### 5.1 文件与函数

外部 fpGUI：

- `framework/src/main/pascal/corelib/ohos/fpg_ohos_drawing.pas`
  - 修正 `OH_Drawing_FontMgrMatchFamilyStyleCharacter` 的 `bcp47` 参数：
    C API 是 `const char* bcp47[]`，Pascal 绑定必须是 `PPChar`。
- `framework/src/main/pascal/corelib/ohos/fpg_ohos.pas`
  - `OhosFontFallbackCandidates`：读取 `fonts.ini`，返回基础字体的候选列表。
  - `OhosResolveFontToken`：解析文件/家族名，返回 typeface。
  - `OhosTrySystemTypefaceForChar`：调用 FontMgr 按字符匹配系统字体，并用 `中` 验证。
  - `OhosScanAppFontFiles`：扫描应用字体目录。
  - `TfpgOhosFontResource.BuildFallbackChain`：窗口路径按新顺序构建 fallback。
- `framework/src/main/pascal/corelib/ohos/fpg_ohos_agg_fontresource.pas`
  - `TfpgOhosAggFontResource.BuildFallbackTypefaces`：离屏 Agg 路径按同一顺序构建 fallback。
  - `SelectDrawFont` / `MeasureLogicalChar` / `GetTextWidth` 使用 fallback 字体。
  - 回退字体和逻辑字体同步字号。

### 5.2 系统字体解析

系统字体路径不可读时，使用：

```pascal
OH_Drawing_FontMgrMatchFamilyStyleCharacter(
  fontMgr,
  'sans-serif',
  style,
  bcp47,       // array[0..0] of PChar，值为 'zh-Hans'
  1,
  Ord('中')
);
```

返回值必须验证：

```pascal
OH_Drawing_FontMeasureText(font, '中', 3, TEXT_ENCODING_UTF8, nil, @w);
if w > 0 then
  接受该 typeface
else
  TypefaceDestroy;
```

这样不会因为 API 返回一个不含中文字形的默认 typeface 而误判成功。

### 5.3 缓存与性能

- `fonts.ini` 只解析一次。
- 每个字体资源构建一次 fallback 链；绘制时按字符选择，不重复创建 FontMgr。
- 应用字体目录扫描只取应用目录，不扫描 `/system/fonts`，避免系统字体目录不可读。
- 如果字体很多，建议用 `fonts.ini` 明确指定，避免自动扫描顺序不确定。

## 6. 使用步骤

以“英文 Arial、中文宋体”为例：

1. 把 `arial.ttf` 放到 `resfile`。
2. 把有授权的宋体文件放到 `resfile`，例如 `simsun.ttc`。
3. 创建 `resfile/fonts.ini`：

```ini
Arial=SimSun
*=simsun.ttc,HarmonyOS Sans SC
```

`Arial` 会先使用 `SimSun`，再使用 `*` 的 `simsun.ttc`、`HarmonyOS Sans SC`。
`SimSun` 会按文件名候选找到 `simsun.ttc`；如果找不到，再尝试系统家族（裸字体名才允许转系统家族）。

4. 报表 Memo 仍设置 `Font.Name = Arial`，不要改成宋体。
5. 重新构建 HAP。

日志中应看到：

```text
FONT FALLBACK CONFIG: fonts.ini
FONT FALLBACK FILE: simsun.ttc#0
FONT FALLBACK SYSTEM: FontMgr:char:sans-serif
```

如果只有系统字体，没有应用字体，日志应出现 `FONT FALLBACK SYSTEM`，中文由系统 CJK 字体显示。

## 7. 注意事项

- **不能在一个 Memo 内同时指定两种字体**。本方案是渲染层回退，不是改变了 Font 属性的字体模型。
- 不同 Memo 需要不同中文字体时：
  - 每个 Memo 用不同的基础字体并配置不同映射；或
  - 拆成多个 Memo；或
  - 以后扩展 `CJKFontName` 属性。
- 系统优先还是应用优先由 `fonts.ini` 的候选顺序决定。如果宋体必须在系统字体之前，把 `SimSun` 放在第一位。
- 不同字体版本的度量不同，会影响换行和分页；打印场景建议把字体文件随应用固定，而不是依赖系统字体升级。
- `simsun.ttc` 是字体集合，当前按索引 0 加载；NSimSun 需要 `simsun.ttc#1`。
- 粗体/斜体没有独立文件时会合成；系统字体命中真实粗体 style 时不再叠加 fake bold。
- `fonts.ini` 使用 UTF-8 保存；文件名大小写敏感的设备上建议使用实际文件名。

## 8. 验证

OHOS：

```text
CELLULARSELFTEST PASS pages=1 views=9 size=794x1123 ink=13812
```

日志验证：

```text
FONT FALLBACK CONFIG: fonts.ini
FONT FALLBACK FILE: simsun.ttc#0
FONT FALLBACK SYSTEM: FontMgr:char:sans-serif
```

- 没有 fonts.ini、没有沙箱 CJK 字体时，如仅保留 Arial.ttf，仍通过系统 FontMgr 显示中文；日志只有 FONT FALLBACK SYSTEM。


