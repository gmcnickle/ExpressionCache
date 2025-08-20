[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Bump,

    [Parameter(Mandatory)]
    [string]$ManifestPath  # e.g. ./ExpressionCache.psd1
)

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

# Read current ModuleVersion from the psd1 (as text for formatting-preservation)
$text = Get-Content -LiteralPath $ManifestPath -Raw
$match = [regex]::Match($text, "^\s*ModuleVersion\s*=\s*'(?<ver>[^']+)'\s*$", 'Multiline')
if (-not $match.Success) {
    throw "Could not find ModuleVersion = 'x.y.z' in $ManifestPath"
}

$current = $match.Groups['ver'].Value
# Basic SemVer x.y.z (ignores pre-release/build metadata on purpose)
if ($current -notmatch '^(?<maj>\d+)\.(?<min>\d+)\.(?<pat>\d+)$') {
    throw "ModuleVersion must be simple SemVer (x.y.z). Found: $current"
}

$maj = [int]$Matches['maj']; $min = [int]$Matches['min']; $pat = [int]$Matches['pat']
switch ($Bump) {
    'major' { $maj++; $min = 0; $pat = 0 }
    'minor' { $min++; $pat = 0 }
    'patch' { $pat++ }
}
$newVersion = "$maj.$min.$pat"

# Replace only the ModuleVersion line
$updated = [regex]::Replace(
    $text,
    "^\s*ModuleVersion\s*=\s*'[^']+'\s*$",
    "ModuleVersion = '$newVersion'",
    'Multiline'
)

Set-Content -LiteralPath $ManifestPath -Value $updated -NoNewline
Write-Host "Bumped $current -> $newVersion"
# Emit for GitHub Actions
"NEW_VERSION=$newVersion" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
