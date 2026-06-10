param(
    [string]$PythonPath = 'python'
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$Tool = Join-Path $Root 'tools\font_modifier.py'

$fontsKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
Get-ItemProperty $fontsKey |
    Select-Object -Property `
        'Segoe UI (TrueType)',
        'Segoe UI Variable (TrueType)',
        'Segoe UI Bold (TrueType)',
        'Microsoft YaHei & Microsoft YaHei UI (TrueType)',
        'Microsoft YaHei Bold & Microsoft YaHei UI Bold (TrueType)' |
    Format-List

try {
    & $PythonPath $Tool verify
} catch {
    Write-Warning 'Python verification failed. Registry output above is still useful.'
}

