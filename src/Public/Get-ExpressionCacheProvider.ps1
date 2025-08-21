<#
.SYNOPSIS
Gets a registered cache provider by name.

.DESCRIPTION
Returns the provider object previously registered via Initialize-ExpressionCache. Useful for
inspection during tests or for provider-specific operations (e.g., reading the cache folder path).

.PARAMETER Name
The provider name (e.g., 'LocalFileSystemCache', 'Redis').

.OUTPUTS
PSCustomObject (provider), or $null if not found.

.EXAMPLE
Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
#>
function Get-ExpressionCacheProvider { 
    param(
        [string]$ProviderName,
        [switch]$NoFallback
    ) 

    if ($script:RegisteredStorageProviders.Contains($ProviderName)) {
        return $script:RegisteredStorageProviders[$ProviderName]
    }

    if ($NoFallback)
    {
        return
    }

    return $script:RegisteredStorageProviders
}
