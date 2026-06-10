# Variable Fonts

Windows 11 and modern Windows 10 builds use `Segoe UI Variable` in many WinUI and shell surfaces. Mapping that entry to a static font can work, but it is not equivalent to a real variable font.

## Preferred Path

Use a source family that includes a real TrueType variable font:

- It should contain an `fvar` table.
- It should usually contain a `gvar` table.
- A `wght` axis is the most important axis for UI use.

The installer detects a variable source face and generates a new font whose internal family name is `Segoe UI Variable` while keeping the source variable tables.

For a VF source, the installer also maps the non-variable Segoe UI registry entries to a generated `Segoe UI` VF surrogate. This keeps installation fast and preserves variable interpolation instead of materializing many static CJK instances.

## Static Fallback

If no VF is found, the installer generates a static `Segoe UI Variable` surrogate from the selected Regular face.

That fallback is less faithful:

- WinUI may synthesize weights.
- Some title or caption weights may look too light or too heavy.
- Optical size behavior is not preserved.

The fallback is still useful for compatibility, but a real VF source is strongly preferred.

Static fallback may generate more files and may take longer for very large CJK families.

## Axes

Microsoft's original `SegUIVar.ttf` has `wght` and `opsz` axes. Many open-source UI variable fonts only have `wght`.

This tool does not fabricate an `opsz` axis. A fake `opsz` axis can make metadata look closer but does not improve rendering unless the glyph variations actually exist.
