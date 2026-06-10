function Invoke-ExpressionCacheProviderHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProviderName,

        [Parameter(Mandatory)]
        [ValidateSet('ClearCache', 'GetOrCreate', 'Initialize', 'Teardown')]
        [string]$Hook,

        [hashtable]$Arguments = @{}
    )

    $provider = Find-ExpressionCacheProvider -ProviderName $ProviderName
    if (-not $provider) { 
        throw "ExpressionCache: Provider '$ProviderName' not found." 
    }

    $fnName = $provider.$Hook
    
    if (-not $fnName) { 
        Write-Verbose "ExpressionCache: Invoke-ExpressionCacheProviderHook requested, but hook '$Hook' was not found on provider '$ProviderName'"
        return $false 
    }

    $command = Get-Command -Name $fnName -CommandType Function, Cmdlet, ExternalScript -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "ExpressionCache: Hook '$Hook' for provider '$ProviderName' points to '$fnName', but the function was not found."
    }

    $splat = New-CallableSplat -CommandName $fnName `
        -Config $provider.Config `
        -Arguments $Arguments `
        -PreferArgs

    & $fnName @splat

    return $true
}
