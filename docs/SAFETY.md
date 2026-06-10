# Safety and Recovery

This tool modifies registry settings used by Windows font discovery and UI fallback.

It does not overwrite Microsoft font files, but an incorrect font mapping can still cause broken UI rendering, missing glyphs, or unreadable text.

## Backups

Each install creates a timestamped backup under:

```text
backups/<yyyyMMdd-HHmmss>/
```

The backup contains exported registry keys and a JSON snapshot of changed font registry values.

Keep these files until you are sure the new font works.

## Restore

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Restore-SystemFont.ps1
```

Then restart Windows.

## If Text Becomes Unreadable

1. Boot into Safe Mode or Windows Recovery Environment if needed.
2. Run the restore script from an elevated PowerShell.
3. Restart Windows.

If PowerShell text is unreadable, use the `.reg` files in the newest backup directory to restore the registry keys manually.

## Windows Updates

Feature updates or system repair commands may restore some registry entries. Re-run the installer if the system falls back to the default fonts after an update.

