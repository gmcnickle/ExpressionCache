# ExpressionCache.psm1

# --- Module state (shared across all files) ---
$script:Config = $null
$script:RegisteredStorageProviders = @()

# --- Load Utilities ---
Get-ChildItem -Path (Join-Path $PSScriptRoot 'Utilities') -Filter *.ps1 -ErrorAction SilentlyContinue |
  Sort-Object Name |
  ForEach-Object { . $_.FullName }

# --- Load Providers ---
Get-ChildItem -Path (Join-Path $PSScriptRoot 'Providers') -Filter *.ps1 -ErrorAction SilentlyContinue |
  Sort-Object Name |
  ForEach-Object { . $_.FullName }

# --- Load Public ---
$publicDir = Join-Path $PSScriptRoot 'Public'
$publicFiles = @()
if (Test-Path $publicDir) {
  $publicFiles = Get-ChildItem -Path $publicDir -Filter *.ps1 -ErrorAction SilentlyContinue | Sort-Object Name
  foreach ($f in $publicFiles) { . $f.FullName }
}

if ($publicFiles) {
  Export-ModuleMember -Function $publicFiles.BaseName
}

$ExecutionContext.SessionState.Module.OnRemove = {
}
