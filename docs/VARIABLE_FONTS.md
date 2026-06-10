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

## 本工具的稳定策略

Windows 对 VF 的支持并不是每个系统组件都一样好。为了减少设置、任务栏、输入法、旧程序之间的差异，本工具默认走稳定策略：

- 普通 `Segoe UI` 条目使用静态字体。
- 普通 `Microsoft YaHei` / `Microsoft YaHei UI` 条目使用静态 `.ttc`。
- 只有 `Segoe UI Variable` 在源字体有 VF 时保留真 VF。

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

## 关于 opsz 轴

微软原始 `SegUIVar.ttf` 通常有：

- `wght`
- `opsz`

不少开源中文 VF 只有：

- `wght`

本工具不会伪造 `opsz`。没有真实轮廓变化的假 `opsz` 轴只会让元数据看起来相似，不会让渲染真正更接近原版 Segoe UI Variable。
