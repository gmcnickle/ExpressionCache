function Initialize-ExpressionCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,        
        [System.Collections.IDictionary]$Providers,
        [switch]$ReplaceProviders
    )

    $script:Config = [pscustomobject]@{
        AppName = $AppName
        Version = $Script:moduleData.ModuleVersion
    }

    $script:RegisteredStorageProviders = [ordered]@{}

    $defaults = Get-DefaultProviders   # returns [ordered] hashtable
    $merged = Merge-ExpressionCacheProviders -Defaults $defaults -Overrides $Providers -Replace:$ReplaceProviders

    foreach ($key in $merged.Keys) {
        Add-ExpressionCacheProvider -Provider $merged[$key] | Out-Null
    }

    $script:RegisteredStorageProviders = $merged
    return $merged
}
