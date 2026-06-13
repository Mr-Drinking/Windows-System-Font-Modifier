param(
    [Parameter(Mandatory=$true)]
    [string]$SourceFamily,
    [string]$PythonPath = 'python',
    [switch]$AllowMissingCjk
)

$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
} catch {
}
if (-not $env:PYTHONIOENCODING) {
    $env:PYTHONIOENCODING = 'utf-8'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-SourceFamily', "`"$SourceFamily`"",
        '-PythonPath', "`"$PythonPath`""
    )
    if ($AllowMissingCjk) {
        $args += '-AllowMissingCjk'
    }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$Tool = Join-Path $Root 'tools\font_modifier.py'
$Dist = Join-Path $Root 'dist\fonts'
$Manifest = Join-Path $Root 'dist\manifest.json'
$BackupDir = Join-Path $Root ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$WindowsFontDir = Join-Path $env:WINDIR 'Fonts'
$FontsKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$SubstitutesHKLM = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
$SubstitutesHKCU = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
$SystemLinkKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'

New-Item -ItemType Directory -Path $Dist -Force | Out-Null

& $PythonPath -c "import fontTools" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Python fontTools is required. Install it before running this tool.'
}

$buildArgs = @($Tool, 'build', '--source-family', $SourceFamily, '--out-dir', $Dist, '--manifest', $Manifest)
if ($AllowMissingCjk) {
    $buildArgs += '--allow-missing-cjk'
}
& $PythonPath @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw 'Font build failed.'
}

$ManifestText = [IO.File]::ReadAllText($Manifest, [Text.Encoding]::UTF8)
$Data = $ManifestText | ConvertFrom-Json

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

function Export-Key {
    param(
        [string]$RegPath,
        [string]$FileName,
        [switch]$Optional
    )
    $target = Join-Path $BackupDir $FileName
    & reg.exe query $RegPath *> $null
    if ($LASTEXITCODE -ne 0) {
        if ($Optional) {
            New-Item -ItemType File -Path (Join-Path $BackupDir "$FileName.missing") -Force | Out-Null
            return
        }
        throw "Registry key not found or not readable: $RegPath"
    }
    & reg.exe export $RegPath $target /y | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Registry export failed: $RegPath"
    }
}

Export-Key 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' 'HKLM-Fonts.reg'
Export-Key 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' 'HKLM-FontSubstitutes.reg'
Export-Key 'HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' 'HKCU-FontSubstitutes.reg' -Optional
Export-Key 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink' 'HKLM-FontLink-SystemLink.reg'
Export-Key 'HKCU\Control Panel\Desktop\WindowMetrics' 'HKCU-WindowMetrics.reg'

function Get-StringValueSnapshot {
    param(
        [string]$Path,
        [string[]]$Names
    )
    $snapshot = [ordered]@{}
    foreach ($name in $Names) {
        $entry = [ordered]@{
            present = $false
            value = $null
        }
        try {
            $value = Get-ItemPropertyValue -Path $Path -Name $name -ErrorAction Stop
            $entry.present = $true
            $entry.value = [string]$value
        } catch {
        }
        $snapshot[$name] = $entry
    }
    return $snapshot
}

$fontRegistryNames = @($Data.font_registry.PSObject.Properties | ForEach-Object { $_.Name })
$fontRegistryBefore = Get-StringValueSnapshot -Path $FontsKey -Names $fontRegistryNames
$fontRegistryBefore | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $BackupDir 'font-registry-before.json') -Encoding UTF8

$substituteNames = @($Data.font_substitutes | ForEach-Object { [string]$_ })
$substitutesBefore = [ordered]@{
    HKLM = Get-StringValueSnapshot -Path $SubstitutesHKLM -Names $substituteNames
    HKCU = Get-StringValueSnapshot -Path $SubstitutesHKCU -Names $substituteNames
}
$substitutesBefore | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $BackupDir 'font-substitutes-before.json') -Encoding UTF8
@($Data.files | ForEach-Object { [string]$_ }) |
    ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $BackupDir 'installed-files-after.json') -Encoding UTF8

[ordered]@{
    source_family = $SourceFamily
    created_at = (Get-Date).ToString('o')
    manifest = $Manifest
} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $BackupDir 'backup-complete.json') -Encoding UTF8

foreach ($file in $Data.files) {
    $source = Join-Path $Dist $file
    $dest = Join-Path $WindowsFontDir $file
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Generated font is missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

foreach ($prop in $Data.font_registry.PSObject.Properties) {
    New-ItemProperty -Path $FontsKey -Name $prop.Name -Value ([string]$prop.Value) -PropertyType String -Force | Out-Null
}

foreach ($key in @($SubstitutesHKLM, $SubstitutesHKCU)) {
    if (-not (Test-Path $key)) {
        New-Item -Path $key -Force | Out-Null
    }
    foreach ($name in $Data.font_substitutes) {
        New-ItemProperty -Path $key -Name ([string]$name) -Value $SourceFamily -PropertyType String -Force | Out-Null
    }
}

function Replace-SystemLink {
    param(
        [string]$ValueName,
        [string[]]$Patterns,
        [string[]]$Replacement
    )
    $items = (Get-ItemProperty -Path $SystemLinkKey -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
    if (-not $items) {
        return
    }
    $updated = @()
    foreach ($item in $items) {
        $matched = $false
        foreach ($pattern in $Patterns) {
            if ($item -match $pattern) {
                if (-not $updated.Contains($Replacement[0])) {
                    $updated += $Replacement
                }
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $updated += $item
        }
    }
    New-ItemProperty -Path $SystemLinkKey -Name $ValueName -Value ([string[]]$updated) -PropertyType MultiString -Force | Out-Null
}

Replace-SystemLink -ValueName 'Segoe UI' -Patterns @('^MSYH\.TTC,Microsoft YaHei UI') -Replacement @(
    "$($Data.generated_files.msyh_regular),Microsoft YaHei UI,128,96",
    "$($Data.generated_files.msyh_regular),Microsoft YaHei UI"
)
Replace-SystemLink -ValueName 'Microsoft YaHei' -Patterns @('^SEGOEUI\.TTF,Segoe UI') -Replacement @(
    "$($Data.generated_files.segoe_regular),Segoe UI,120,80",
    "$($Data.generated_files.segoe_regular),Segoe UI"
)
Replace-SystemLink -ValueName 'Microsoft YaHei UI' -Patterns @('^SEGOEUI\.TTF,Segoe UI') -Replacement @(
    "$($Data.generated_files.segoe_regular),Segoe UI,120,80",
    "$($Data.generated_files.segoe_regular),Segoe UI"
)

function Clear-FontCache {
    Stop-Service -Name FontCache -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Remove-Item -LiteralPath (Join-Path $env:WINDIR 'System32\FNTCACHE.DAT') -Force -ErrorAction SilentlyContinue
    $localServiceFontCache = Join-Path $env:WINDIR 'ServiceProfiles\LocalService\AppData\Local\FontCache'
    if (Test-Path -LiteralPath $localServiceFontCache) {
        Get-ChildItem -LiteralPath $localServiceFontCache -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Start-Service -Name FontCache -ErrorAction SilentlyContinue
}

Clear-FontCache

Write-Host ''
Write-Host 'Windows system font mappings were updated.'
Write-Host "Source family: $SourceFamily"
Write-Host "Backup: $BackupDir"
Write-Host 'Restart Windows before judging WinUI, taskbar, Settings, Start, and IME.'

