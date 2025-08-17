function Invoke-ExpressionCacheProviderHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProviderName,

        [Parameter(Mandatory)]
        [ValidateSet('ClearCache', 'GetOrCreate', 'Initialize')]
        [string]$Hook,

        [hashtable]$Arguments = @{}
    )

    $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName
    if (-not $provider) { 
        throw "ExpressionCache: Provider '$ProviderName' not found." 
    }

    $fnName = $provider.$Hook
    
    if (-not $fnName) { 
        Write-Verbose "ExpressionCache: Invoke-ExpressionCacheProviderHook requested, but hook '$Hook' was not found on provider '$ProviderName'"
        return $false 
    }

    $fn = Get-Item -LiteralPath ("Function:{0}" -f $fnName) -ErrorAction SilentlyContinue
    if (-not $fn) { 
        throw "ExpressionCache: Hook '$Hook' for provider '$ProviderName' points to '$fnName', but the function was not found." 
    }

    & $fn @Arguments

    return $true
}
