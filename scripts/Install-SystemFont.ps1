param(
    [Parameter(Mandatory=$true)]
    [string]$SourceFamily,
    [string]$PythonPath = 'python'
)

$ErrorActionPreference = 'Stop'

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
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait
    exit
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
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

& $PythonPath -c "import fontTools" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Python fontTools is required. Install it before running this tool.'
}

& $PythonPath $Tool build --source-family $SourceFamily --out-dir $Dist --manifest $Manifest
if ($LASTEXITCODE -ne 0) {
    throw 'Font build failed.'
}

$ManifestText = [IO.File]::ReadAllText($Manifest, [Text.Encoding]::UTF8)
$Data = $ManifestText | ConvertFrom-Json

function Export-Key {
    param([string]$RegPath, [string]$FileName)
    $target = Join-Path $BackupDir $FileName
    & reg.exe export $RegPath $target /y | Out-Null
}

Export-Key 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' 'HKLM-Fonts.reg'
Export-Key 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' 'HKLM-FontSubstitutes.reg'
Export-Key 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink' 'HKLM-FontLink-SystemLink.reg'
Export-Key 'HKCU\Control Panel\Desktop\WindowMetrics' 'HKCU-WindowMetrics.reg'

$changed = [ordered]@{}
$current = Get-ItemProperty $FontsKey
foreach ($prop in $Data.font_registry.PSObject.Properties) {
    $changed[$prop.Name] = $current.($prop.Name)
}
$changed | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $BackupDir 'font-values-before.json') -Encoding UTF8

foreach ($file in $Data.files) {
    $source = Join-Path $Dist $file
    $dest = Join-Path $WindowsFontDir $file
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Generated font is missing: $source"
    }
    if (-not (Test-Path -LiteralPath $dest)) {
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
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

