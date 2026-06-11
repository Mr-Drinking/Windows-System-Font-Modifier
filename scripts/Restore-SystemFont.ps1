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
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
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

$FontsKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$SubstitutesHKLM = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
$SubstitutesHKCU = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'

function Import-KeyFile {
    param([string]$FileName)
    $path = Join-Path $BackupDir $FileName
    if (Test-Path -LiteralPath $path) {
        & reg.exe import $path | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Registry import failed: $path"
        }
    }
}

foreach ($file in @(
    'HKLM-Fonts.reg',
    'HKLM-FontSubstitutes.reg',
    'HKCU-FontSubstitutes.reg',
    'HKLM-FontLink-SystemLink.reg',
    'HKCU-WindowMetrics.reg'
)) {
    Import-KeyFile $file
}

function Restore-StringValueSnapshot {
    param(
        [string]$Path,
        [object]$Snapshot
    )
    if (-not $Snapshot) {
        return
    }
    foreach ($prop in $Snapshot.PSObject.Properties) {
        $entry = $prop.Value
        if ($entry.present) {
            if (-not (Test-Path -LiteralPath $Path)) {
                New-Item -Path $Path -Force | Out-Null
            }
            New-ItemProperty -Path $Path -Name $prop.Name -Value ([string]$entry.value) -PropertyType String -Force | Out-Null
        } elseif (Test-Path -LiteralPath $Path) {
            Remove-ItemProperty -Path $Path -Name $prop.Name -ErrorAction SilentlyContinue
        }
    }
}

$fontRegistrySnapshotPath = Join-Path $BackupDir 'font-registry-before.json'
if (Test-Path -LiteralPath $fontRegistrySnapshotPath) {
    $fontRegistrySnapshot = Get-Content -LiteralPath $fontRegistrySnapshotPath -Raw | ConvertFrom-Json
    Restore-StringValueSnapshot -Path $FontsKey -Snapshot $fontRegistrySnapshot
}

$substitutesSnapshotPath = Join-Path $BackupDir 'font-substitutes-before.json'
if (Test-Path -LiteralPath $substitutesSnapshotPath) {
    $substitutesSnapshot = Get-Content -LiteralPath $substitutesSnapshotPath -Raw | ConvertFrom-Json
    Restore-StringValueSnapshot -Path $SubstitutesHKLM -Snapshot $substitutesSnapshot.HKLM
    Restore-StringValueSnapshot -Path $SubstitutesHKCU -Snapshot $substitutesSnapshot.HKCU
}

if (Test-Path -LiteralPath (Join-Path $BackupDir 'HKCU-FontSubstitutes.reg.missing')) {
    Remove-Item -LiteralPath $SubstitutesHKCU -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-ReferencedGeneratedFontFiles {
    $referenced = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $fontProperties = Get-ItemProperty -Path $FontsKey -ErrorAction SilentlyContinue
    if (-not $fontProperties) {
        return ,$referenced
    }
    foreach ($prop in $fontProperties.PSObject.Properties) {
        if ($prop.Value -is [string] -and $prop.Value -like 'WSFM-*') {
            [void]$referenced.Add([IO.Path]::GetFileName($prop.Value))
        }
    }
    return ,$referenced
}

$windowsFontDir = Join-Path $env:WINDIR 'Fonts'
$referencedGeneratedFonts = Get-ReferencedGeneratedFontFiles
$installedFilesPath = Join-Path $BackupDir 'installed-files-after.json'
if (Test-Path -LiteralPath $installedFilesPath) {
    $cleanupCandidates = @(Get-Content -LiteralPath $installedFilesPath -Raw | ConvertFrom-Json | ForEach-Object { [string]$_ })
} else {
    $cleanupCandidates = @(Get-ChildItem -LiteralPath $windowsFontDir -Filter 'WSFM-*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}
foreach ($file in $cleanupCandidates) {
    if (-not $referencedGeneratedFonts.Contains($file)) {
        Remove-Item -LiteralPath (Join-Path $windowsFontDir $file) -Force -ErrorAction SilentlyContinue
    }
}

Stop-Service -Name FontCache -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item -LiteralPath (Join-Path $env:WINDIR 'System32\FNTCACHE.DAT') -Force -ErrorAction SilentlyContinue
$localServiceFontCache = Join-Path $env:WINDIR 'ServiceProfiles\LocalService\AppData\Local\FontCache'
if (Test-Path -LiteralPath $localServiceFontCache) {
    Get-ChildItem -LiteralPath $localServiceFontCache -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
Start-Service -Name FontCache -ErrorAction SilentlyContinue

Write-Host ''
Write-Host "Restored from: $BackupDir"
Write-Host 'Restart Windows before judging the result.'

