# 可变字体说明

Windows 11 和较新的 Windows 10 会在很多现代界面里使用 `Segoe UI Variable`。这类界面包括设置、开始菜单、任务栏、搜索、输入法候选窗等。

## 推荐选择 VF 字体

优先选择带 `VF` 标记的字体：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\List-InstalledFonts.ps1 -VariableOnly
```

输出示例：

```text
VF  Noto Sans SC  wght
VF  Sarasa UI ProDigits SC  wght
```

`wght` 表示它有字重轴，可以在 Regular、Bold、Light 等字重之间插值。

VF 标记只说明字体有可变轴，不代表它包含中文。安装脚本默认会检查常见 CJK 字形；如果源字体缺少这些字形，它不会直接注册成 `Microsoft YaHei` / `微软雅黑` 的替身。

## 本工具的稳定策略

Windows 对 VF 的支持并不是每个系统组件都一样好。为了减少设置、任务栏、输入法、旧程序之间的差异，本工具默认走稳定策略：

- 普通 `Segoe UI` 条目使用静态字体。
- 普通 `Microsoft YaHei` / `Microsoft YaHei UI` 条目使用静态 `.ttc`。
- 只有 `Segoe UI Variable` 在源字体有 VF 时保留真 VF。

如果你安装的字体同时提供静态家族和 VF 家族，可以使用混合来源：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-SystemFont.ps1 -SourceFamily "Sarasa Ui PropDigits SC" -SegoeVariableSourceFamily "Sarasa Ui VF PropDigits SC"
```

这会让普通 `Segoe UI` / `Microsoft YaHei` 条目从静态家族生成，保留静态 hinting；`Segoe UI Variable` 和对应的 `FontSubstitutes` 则使用 VF 家族。这个模式适合静态字体在小字号 UI 下更清晰、但现代 WinUI 仍希望使用 VF 的情况。

## 如果源字体只有 VF

如果一个字体家族「只有 VF，没有单独的 Regular/Bold/Light 静态文件」，本工具会从 VF 里提取静态实例给普通系统字体项使用。

举例：

- `Segoe UI` 提取 `wght=400`。
- `Segoe UI Semilight` 提取 `wght=350`。
- `Segoe UI Light` 提取 `wght=300`。
- `Segoe UI Semibold` 提取 `wght=600`。
- `Segoe UI Bold` 提取 `wght=700`。
- `Segoe UI Black` 提取 `wght=900`。

这些生成字体的 Windows 字重元数据会保持原 Segoe UI 语义。若源字体的 `wght` 轴范围没有覆盖目标值，工具会使用源字体允许的最接近轮廓，但仍把生成字体标成对应的目标字重。

大型中文 VF 提取静态实例会比直接映射 VF 慢，也会生成更多文件。这里优先考虑 Windows 各类界面的稳定性。

## 如果没有斜体

如果源字体族里没有 Italic / Oblique，工具会生成机械拉斜版本给这些条目使用：

- `Segoe UI Italic`
- `Segoe UI Bold Italic`
- `Segoe UI Semibold Italic`
- `Segoe UI Light Italic`
- `Segoe UI Semilight Italic`
- `Segoe UI Black Italic`

这种斜体不等于字体设计师手工绘制的真 Italic，但比把斜体项直接映射到直立体更符合 Windows 的字体语义。

合成斜体主要针对 TrueType `.ttf` 轮廓做坐标变换。少数 CFF/OTF 字体可能只能写入斜体元数据，不一定能真实改动轮廓。

## 没有 VF 时

如果源字体没有 VF，本工具会使用最接近目标字重的已安装静态字体来生成 surrogate。`Segoe UI Variable` 会退化为静态 Regular surrogate。

## UI 指标对齐

字体的字面大小不只由字号决定，也会受到 ascender、descender、lineGap 等垂直指标影响。为了减少标题栏、菜单、输入法候选窗等 UI 里的文字偏上、偏下或行高突变，生成字体会按微软原始字体的指标进行对齐。

对齐时不会直接复制原始数值，而是按 `unitsPerEm` 比例缩放。例如原始 `Segoe UI` 是 2048 UPM，而来源字体是 1000 UPM，则原始 ascent 会先换算到 1000 UPM 再写入生成字体。

参考来源优先使用 Windows 原始字体文件名，而不是当前注册表映射。因此重复运行安装脚本时，即使注册表已经指向 `WSFM-*`，仍会继续以 `segoeui.ttf`、`SegUIVar.ttf`、`msyh.ttc` 等原始文件作为指标参考。

## 关于 opsz 轴

微软原始 `SegUIVar.ttf` 通常有：

- `wght`
- `opsz`

不少开源中文 VF 只有：

- `wght`

本工具不会伪造 `opsz`。没有真实轮廓变化的假 `opsz` 轴只会让元数据看起来相似，不会让渲染真正更接近原版 Segoe UI Variable。
