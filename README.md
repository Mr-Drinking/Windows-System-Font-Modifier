# Windows System Font Modifier

把 Windows 系统界面字体换成你电脑上已经安装好的字体。

这个工具是离线的：**不下载字体，不访问网络，不自带字体文件**。你先在 Windows 里安装好想用的字体，然后用本工具把它生成成 Windows 系统 UI 会识别的 surrogate 字体，再写入相关注册表。

## 它能改什么

它会尽量覆盖这些地方：

- 传统 Win32 界面：文件资源管理器、旧式对话框、部分桌面程序。
- DirectWrite / WinUI：设置、开始菜单、任务栏、搜索、部分输入法界面。
- 中文 fallback：`Microsoft YaHei` / `Microsoft YaHei UI`。
- 英文 UI：`Segoe UI` / `Segoe UI Variable`。

它不会覆盖微软原始字体文件，例如：

- `segoeui.ttf`
- `SegUIVar.ttf`
- `msyh.ttc`

## 先说风险

这是系统级字体修改，不是 Windows 官方提供的普通设置项。

使用前建议：

1. 创建系统还原点。
2. 保留本工具生成的 `backups/` 文件夹。
3. 第一次先选一个字形完整、字重完整的字体。
4. 修改后必须重启 Windows，再判断效果。

恢复方法见下面的「恢复默认/恢复上一次配置」。

## 准备工作

你需要：

1. Windows 10 或 Windows 11。
2. 管理员权限。
3. Python 3.9 或更新版本。
4. Python 里已经安装 `fontTools`。
5. 你想使用的字体已经安装到这台电脑。

检查 Python 和 fontTools：

```powershell
python -c "import fontTools; print(fontTools.__version__)"
```

如果这条命令报错，先安装 `fontTools`。本工具不负责联网安装依赖。

## 最简单用法

### 1. 下载本仓库

下载 ZIP，解压到一个普通文件夹，例如：

```text
D:\Tools\Windows-System-Font-Modifier
```

### 2. 打开 PowerShell

在这个文件夹里打开 PowerShell。

如果你不知道怎么做：

1. 打开解压后的文件夹。
2. 在空白处按住 `Shift`，点右键。
3. 选择「在终端中打开」或「在此处打开 PowerShell」。

### 3. 列出电脑里已安装的字体

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\List-InstalledFonts.ps1
```

如果你只想看可变字体：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\List-InstalledFonts.ps1 -VariableOnly
```

输出示例：

```text
VF  Noto Sans SC  wght
VF  Sarasa UI ProDigits SC  wght
--  Microsoft YaHei
```

左边是 `VF` 的字体表示它有 variable font。优先选这种。

### 4. 复制你要用的字体名

比如你看到：

```text
VF  Sarasa UI ProDigits SC  wght
```

那字体名就是：

```text
Sarasa UI ProDigits SC
```

### 5. 安装为系统字体

把下面命令里的字体名换成你自己的：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-SystemFont.ps1 -SourceFamily "Sarasa UI ProDigits SC"
```

系统会弹 UAC 管理员确认，点「是」。

如果你选的是大型中文 VF，第一次生成静态实例可能需要几分钟，属于正常现象。

执行完会看到类似：

```text
Windows system font mappings were updated.
Source family: Sarasa UI ProDigits SC
Backup: ...\backups\20260611-000000
Restart Windows before judging WinUI, taskbar, Settings, Start, and IME.
```

### 6. 重启 Windows

必须重启。只重启资源管理器通常不够。

重启后再看：

- 设置
- 任务栏
- 开始菜单
- 搜索
- 输入法
- 文件资源管理器

## 验证当前映射

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Verify-SystemFont.ps1
```

它会显示当前 `Segoe UI`、`Segoe UI Variable`、`Microsoft YaHei` 等注册表项指向了哪些生成字体。

## 恢复默认/恢复上一次配置

恢复最近一次安装前的备份：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Restore-SystemFont.ps1
```

然后重启 Windows。

如果你要指定某个备份目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Restore-SystemFont.ps1 -BackupDir ".\backups\20260611-000000"
```

## VF 字体到底怎么处理

Windows 日常界面对 VF 的支持并不均匀，所以本工具默认不把普通系统字体项直接指向 VF。

如果你选择的源字体本身有 VF，也就是 `List-InstalledFonts.ps1 -VariableOnly` 里能看到它，那么本工具会这样做：

- `Segoe UI Variable`：保留生成后的真 VF。
- `Segoe UI` / `Segoe UI Bold` / `Segoe UI Semibold` / `Segoe UI Light` 等普通项：从 VF 里提取对应静态实例。
- `Microsoft YaHei` / `Microsoft YaHei UI`：从 VF 里提取静态实例，再打包成 Windows 需要的 `.ttc`。

也就是说：**如果源字体只有 VF，普通 `Segoe UI` 会使用从 VF 提取出来的静态字体；只有 `Segoe UI Variable` 会继续使用真 VF。**

普通 `Segoe UI` 相关项会按原 Windows 字重生成：

```text
Regular     400
Semilight   350
Light       300
Semibold    600
Bold        700
Black       900
```

如果源 VF 的 `wght` 轴范围没有覆盖某个值，工具会使用源字体允许的最接近轮廓，但生成字体暴露给 Windows 的字重仍保持对应的 Segoe UI 字重。

## 斜体怎么处理

如果源字体族里有真正的 Italic / Oblique，工具会优先使用它。

如果没有，工具会为这些项生成机械拉斜版本：

- `Segoe UI Italic`
- `Segoe UI Bold Italic`
- `Segoe UI Semibold Italic`
- `Segoe UI Light Italic`
- `Segoe UI Semilight Italic`
- `Segoe UI Black Italic`

这些是静态字体文件，名字和字重仍然按原 Segoe UI 项写入。

合成斜体主要针对 TrueType `.ttf` 轮廓做机械拉斜。少数 CFF/OTF 字体可能只能写入斜体元数据，不一定能真实改动轮廓。

注意：

- 原版 `SegUIVar.ttf` 有 `wght` 和 `opsz` 轴。
- 很多开源中文 VF 只有 `wght` 轴。
- 本工具不会伪造 `opsz` 轴，因为没有真实轮廓变化的假轴对渲染没有帮助。

更多说明见 [docs/VARIABLE_FONTS.md](docs/VARIABLE_FONTS.md)。

## 生成了哪些东西

安装时会生成：

```text
dist/fonts/WSFM-*.ttf
dist/fonts/WSFM-*.ttc
dist/manifest.json
backups/<timestamp>/
```

其中：

- `dist/` 是生成字体和 manifest。
- `backups/` 是恢复用备份。
- `WSFM-` 开头的字体文件会复制到 `C:\Windows\Fonts`。

这些生成文件不会提交到 Git。

## License

本仓库代码使用 MIT License，见 [LICENSE](LICENSE)。

注意：

- MIT License 只覆盖本仓库的脚本和文档。
- 用户选择的源字体仍然受它自己的字体许可证约束。
- 本工具生成的 surrogate 字体不建议公开分发，除非你确认源字体许可证和命名/商标要求允许这么做。
