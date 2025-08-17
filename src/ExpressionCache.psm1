# ExpressionCache.psm1

# --- Module state (shared across all files) ---
$script:Config = $null
$script:RegisteredStorageProviders = @()

$utilitiesFolder = (Join-Path $PSScriptRoot 'Utilities')
# --- Load Utilities ---
Get-ChildItem -Path $utilitiesFolder -Filter *.ps1 -ErrorAction SilentlyContinue |
  Sort-Object Name |
  ForEach-Object { . $_.FullName }

$providersFolder = (Join-Path $PSScriptRoot 'Providers')
# --- Load Providers ---
Get-ChildItem -Path $providersFolder -Filter *.ps1 -ErrorAction SilentlyContinue |
  Sort-Object Name |
  ForEach-Object { . $_.FullName }

$publicFolder = Join-Path $PSScriptRoot 'Public'
# --- Load Public ---
if (Test-Path $publicFolder) {
  $publicFiles = Get-ChildItem -Path $publicFolder -Filter *.ps1 -ErrorAction SilentlyContinue | Sort-Object Name
  foreach ($f in $publicFiles) { . $f.FullName }
  Export-ModuleMember -Function $publicFiles.BaseName
}

$ExecutionContext.SessionState.Module.OnRemove = {
}
