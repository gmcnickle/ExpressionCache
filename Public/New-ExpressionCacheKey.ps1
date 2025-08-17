<#
.SYNOPSIS
Generates a stable cache key from a ScriptBlock and its arguments.

.DESCRIPTION
Creates a deterministic key (hash) that changes when the ScriptBlock content or the supplied
Arguments change. Argument order matters.

.PARAMETER ScriptBlock
The ScriptBlock used to compute the value.

.PARAMETER Arguments
Arguments that will be passed to the ScriptBlock when computing the value.

.OUTPUTS
System.String

.EXAMPLE
$sb = { param($x,$y) $x + $y }
New-ExpressionCacheKey -ScriptBlock $sb -Arguments 1,2
#>
function New-ExpressionCacheKey {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private helper; Does not execute ScriptBlock.')]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$Arguments
    )

    $src = ($ScriptBlock.ToString() -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' '
    $Arguments = if ($Arguments) { ($Arguments | ConvertTo-Json -Depth 5) } else { '' }
    
    "$src|$Arguments" | Get-ExpressionCacheHash
}
