param(
    [string]$BackupDir = ''
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($BackupDir) {
        $args += @('-BackupDir', "`"$BackupDir`"")
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait
    exit
}

$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $BackupDir) {
    $latest = Get-ChildItem -LiteralPath (Join-Path $Root 'backups') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw 'No backup directory found.'
    }
    $BackupDir = $latest.FullName
}

foreach ($file in @(
    'HKLM-Fonts.reg',
    'HKLM-FontSubstitutes.reg',
    'HKLM-FontLink-SystemLink.reg',
    'HKCU-WindowMetrics.reg'
)) {
    $path = Join-Path $BackupDir $file
    if (Test-Path -LiteralPath $path) {
        & reg.exe import $path | Out-Null
    }
}

$windowsFontDir = Join-Path $env:WINDIR 'Fonts'
Get-ChildItem -LiteralPath $windowsFontDir -Filter 'WSFM-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

Stop-Service -Name FontCache -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item -LiteralPath (Join-Path $env:WINDIR 'System32\FNTCACHE.DAT') -Force -ErrorAction SilentlyContinue
Start-Service -Name FontCache -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "Restored from: $BackupDir"
Write-Host 'Restart Windows before judging the result.'

