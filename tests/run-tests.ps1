param(
#  [string]$Path = "$PSScriptRoot/ExpressionCache.Tests.ps1",
  [string]$Path = "$PSScriptRoot",
  [switch]$Debug
)

Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.3 -Force

Remove-Module ExpressionCache -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot/../src/ExpressionCache.psd1" -Force   # or: "$PSScriptRoot/.."

# Build a Pester v5 config and use ONLY -Configuration
$conf = [PesterConfiguration]::Default #New-PesterConfiguration
$conf.Run.Path = @($Path)
$conf.Run.Exit = $true
$conf.Output.Verbosity = 'Detailed'


Invoke-Pester -Configuration $conf
