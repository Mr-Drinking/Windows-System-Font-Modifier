# Windows System Font Modifier

Offline tools for changing Windows system UI fonts by generating local surrogate fonts from a font that is already installed on the computer.

The tool is designed for Windows 10/11 modern UI paths as well as older Win32 UI paths:

- Classic UI: `FontSubstitutes`, `MS Shell Dlg`, and current-user window metrics.
- DirectWrite / WinUI: system font registry mappings for `Segoe UI`, `Segoe UI Variable`, and `Microsoft YaHei`.
- Variable fonts: if the selected source family has a real variable font, the generated `Segoe UI Variable` surrogate remains a real variable font.

No fonts are downloaded. No generated font binaries are committed to this repository.

## Requirements

- Windows 10 or Windows 11.
- Administrator rights for installation and restore.
- Python 3.9+ available as `python`.
- `fontTools` available to that Python environment.
- The source font family must already be installed for the current user or for all users.

Check the Python dependency:

```powershell
python -c "import fontTools; print(fontTools.__version__)"
```

If this fails, install `fontTools` by your preferred offline or managed method before using this tool.

## Quick Start

List installed font families:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\List-InstalledFonts.ps1
```

Install a font as the system UI font:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-SystemFont.ps1 -SourceFamily "Sarasa UI ProDigits SC"
```

Verify registry mappings:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Verify-SystemFont.ps1
```

Restart Windows before judging Settings, taskbar, Start, IME, and other WinUI surfaces.

Restore the previous system font configuration:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Restore-SystemFont.ps1
```

## What Gets Changed

`Install-SystemFont.ps1` does the following:

1. Builds generated surrogate fonts under `dist/fonts/`.
2. Copies those generated fonts to `%WINDIR%\Fonts`.
3. Backs up relevant registry keys under `backups/<timestamp>/`.
4. Updates system font registry entries:
   - `Segoe UI`
   - `Segoe UI Variable`
   - `Microsoft YaHei`
   - `Microsoft YaHei UI`
5. Updates classic fallback settings.
6. Clears the Windows font cache.

It does not overwrite Microsoft font files such as `segoeui.ttf`, `SegUIVar.ttf`, or `msyh.ttc`.

## Variable Font Behavior

If the source family includes a real variable font with an `fvar` table, this tool uses it for the generated `Segoe UI Variable` surrogate.

The build is VF-first. With a VF source, it generates a small set of variable surrogate fonts instead of expanding a CJK variable font into many static files:

- one generated `Segoe UI` VF;
- one generated `Segoe UI Variable` VF;
- one generated `Microsoft YaHei` / `Microsoft YaHei UI` VF collection.

If no variable font is available, the tool falls back to static surrogate files. That fallback usually works, but WinUI text weights and optical sizing may be less faithful.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\List-InstalledFonts.ps1 -VariableOnly
```

to see installed families with variable font files.

See [docs/VARIABLE_FONTS.md](docs/VARIABLE_FONTS.md) for details.

## Safety

This tool changes system-level font registry entries. It is reversible, but it is still a system customization.

Before using it on a machine you care about:

- Create a restore point or backup.
- Keep the generated `backups/` directory.
- Test with a font that includes common weights: Regular, Bold, Light/Semibold, and preferably a real VF.

See [docs/SAFETY.md](docs/SAFETY.md) for recovery notes.

## Notes

- This project does not distribute any generated fonts.
- Generated fonts are named with a `WSFM-` prefix and are ignored by Git.
- The scripts do not download fonts or call any remote API.
- The selected source font remains subject to its own license.
- If you publish generated fonts, verify the source font license and naming/trademark rules first.
