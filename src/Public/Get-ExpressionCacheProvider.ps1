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
    [CmdletBinding()]
    param(
        [Alias('Name')]
        [string]$ProviderName
    )

    $result = if ($ProviderName) {
        Find-ExpressionCacheProvider -ProviderName $ProviderName
    }

    if ($null -ne $result) {
        return $result
    }

    # A specifically requested resource follows normal Get-* semantics:
    # write a non-terminating error and return no object.
    if ($ProviderName) {
        Write-Error -Message "ExpressionCache: Provider '$ProviderName' is not registered." `
            -Category ObjectNotFound `
            -TargetObject $ProviderName
        return
    }

    # No name given — return all providers
    return With-ReadLock { $script:RegisteredStorageProviders }
}
