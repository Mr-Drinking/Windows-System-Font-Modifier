param(
    [switch]$VariableOnly,
    [string]$PythonPath = 'python'
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

$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$Tool = Join-Path $Root 'tools\font_modifier.py'

$args = @($Tool, 'list')
if ($VariableOnly) {
    $args += '--variable-only'
}

& $PythonPath @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

