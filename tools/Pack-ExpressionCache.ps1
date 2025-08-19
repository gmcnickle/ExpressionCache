param(
  [string]$OutDir = "Staging",
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$moduleName = 'ExpressionCache'
$repoRoot   = Split-Path $PSScriptRoot -Parent
$srcRoot    = Join-Path $repoRoot "src"
$stageRoot  = Join-Path $repoRoot "$OutDir\$moduleName"

if ($Clean -and (Test-Path (Join-Path $repoRoot $OutDir))) {
    Remove-Item -Recurse -Force (Join-Path $repoRoot $OutDir)
}

New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

# Copy everything under /src
Copy-Item -Recurse -Force $srcRoot\* $stageRoot

# Validate manifest
Test-ModuleManifest (Join-Path $stageRoot "$moduleName.psd1") |
    Select-Object Name, Version, RootModule, Path | Format-List

Write-Host "Staged module at $stageRoot"
