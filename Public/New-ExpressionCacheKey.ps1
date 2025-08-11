function New-ExpressionCacheKey {
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions','',
        Justification='Private helper; Does not execute ScriptBlock.'
    )]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$Arguments
    )

    $src  = ($ScriptBlock.ToString() -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' '
    $Arguments = if ($Arguments) { ($Arguments | ConvertTo-Json -Depth 5) } else { '' }
    
    "$src|$Arguments" | Get-ExpressionCacheHash
}
