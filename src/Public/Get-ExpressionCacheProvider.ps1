<#
.SYNOPSIS
Gets a registered cache provider by name.

.DESCRIPTION
Returns the provider object previously registered via Initialize-ExpressionCache. Useful for
inspection during tests or for provider-specific operations (e.g., reading the cache folder path).

.PARAMETER ProviderName
The provider name (e.g., 'LocalFileSystemCache', 'Redis').

.OUTPUTS
PSCustomObject (provider), or $null if not found.

.EXAMPLE
Get-ExpressionCacheProvider -ProviderName 'LocalFileSystemCache'
#>
function Get-ExpressionCacheProvider { 
    param(
        [string]$ProviderName,
        [switch]$NoFallback
    ) 

    $result = With-ReadLock {
        if ($ProviderName -and $script:RegisteredStorageProviders.Contains($ProviderName)) {
            $script:RegisteredStorageProviders[$ProviderName]
        }
    }

    if ($null -ne $result) {
        return $result
    }

    # When a specific name was requested but not found, warn and return $null
    if ($ProviderName) {
        Write-Warning "ExpressionCache: provider '$ProviderName' is not registered."
        return
    }

    # No name given — return all providers
    return With-ReadLock { $script:RegisteredStorageProviders }
}
