param(
  [string]$Path = "$PSScriptRoot/ExpressionCache.Tests.ps1",
  [switch]$Debug
)

Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.3 -Force

Remove-Module ExpressionCache -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../ExpressionCache.psd1" -Force   # or: "$PSScriptRoot/.."

# Build a Pester v5 config and use ONLY -Configuration
$conf = New-PesterConfiguration
$conf.Run.Path = $Path
$conf.Output.Verbosity = 'Detailed'


Invoke-Pester -Configuration $conf
