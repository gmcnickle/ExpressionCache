function Find-ExpressionCacheProvider {
    param(
        [Parameter(Mandatory)]
        [string]$ProviderName
    )

    With-ReadLock {
        if ($script:RegisteredStorageProviders.Contains($ProviderName)) {
            $script:RegisteredStorageProviders[$ProviderName]
        }
    }
}
