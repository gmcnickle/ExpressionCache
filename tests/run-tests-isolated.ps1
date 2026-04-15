param(
    [ValidateSet('powershell','pwsh')]
    [string]$Engine = 'powershell',
    [string]$Path = "$PSScriptRoot",
    [switch]$Debug
)

<#
.SYNOPSIS
    Runs Pester tests in a fully isolated child process.
    This prevents Pester/runspace crashes from taking down the parent terminal.
#>

$scriptBody = @'
param([string]$TestPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.3 -Force

$modulePath = Join-Path (Join-Path (Join-Path $TestPath '..') 'src') 'ExpressionCache.psd1' | Resolve-Path
Remove-Module ExpressionCache -ErrorAction SilentlyContinue
Import-Module $modulePath -Force

$conf = [PesterConfiguration]::Default
$conf.Run.Path = @($TestPath)
$conf.Run.Exit = $true
$conf.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $conf
'@

$tempFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
try {
    Set-Content -Path $tempFile -Value $scriptBody -Encoding UTF8

    $resolvedPath = Resolve-Path $Path
    Write-Host "Running tests with $Engine (isolated process)..." -ForegroundColor Cyan
    Write-Host "Test path: $resolvedPath" -ForegroundColor Cyan
    Write-Host "Temp script: $tempFile" -ForegroundColor DarkGray

    & $Engine -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tempFile -TestPath $resolvedPath
    $exitCode = $LASTEXITCODE
    Write-Host "`nChild process exited with code: $exitCode" -ForegroundColor $(if ($exitCode -eq 0) { 'Green' } else { 'Red' })
    exit $exitCode
} finally {
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}
