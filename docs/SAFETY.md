# 安全和恢复

这个工具会修改系统字体相关注册表。它不会覆盖微软原始字体文件，但仍然可能造成界面显示异常。

## 使用前建议

1. 创建系统还原点。
2. 确认你能打开管理员 PowerShell。
3. 选择字形完整的字体，尤其是要覆盖中文界面时。缺少常见中文字形的字体会被默认拒绝安装。
4. 保留 `backups/` 文件夹。

## 自动备份

每次安装都会创建：

```text
backups/<timestamp>/
```

里面包含：

- 字体注册表备份。
- HKLM 和 HKCU 的 `FontSubstitutes` 备份。
- `FontLink\SystemLink` 备份。
- 当前用户窗口字体设置备份。
- 被修改字体项的 JSON 快照。
- 被修改 `FontSubstitutes` 值的 JSON 快照。
- 本次安装写入的生成字体文件清单。

## 普通恢复

运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Restore-SystemFont.ps1
```

然后重启 Windows。

恢复脚本会恢复到所选备份创建时的状态。第一次安装前的备份通常对应 Windows 默认配置；如果你已经连续安装过多个字体，最近备份对应的是上一次配置。

恢复时，脚本会按快照删除安装时新增的 `FontSubstitutes` 值，并只清理本次安装写入且恢复后不再被注册表引用的 `WSFM-*` 字体文件。

## 指定备份恢复

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Restore-SystemFont.ps1 -BackupDir ".\backups\20260611-000000"
```

然后重启 Windows。

## 如果界面文字严重异常

1. 尽量打开管理员 PowerShell。
2. 运行恢复脚本。
3. 重启。

如果正常模式难以操作，可以进入安全模式或 Windows 恢复环境后再恢复注册表。

## 系统更新

Windows 大版本更新、系统修复、`sfc` / `dism` 可能恢复部分默认字体配置。更新后如果字体回到默认状态，重新运行安装脚本即可。

