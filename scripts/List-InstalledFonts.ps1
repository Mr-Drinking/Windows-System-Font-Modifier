param(
    [switch]$VariableOnly,
    [string]$PythonPath = 'python'
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..')
$Tool = Join-Path $Root 'tools\font_modifier.py'

$args = @($Tool, 'list')
if ($VariableOnly) {
    $args += '--variable-only'
}

& $PythonPath @args

