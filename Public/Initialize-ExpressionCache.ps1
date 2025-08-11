function Initialize-ExpressionCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter()]
        [object[]]$Providers  # optional additional providers
    )

    $script:Config = [pscustomobject]@{
        AppName = $AppName
        Version = $Script:moduleData.ModuleVersion
    }

    $defaultCacheFolder =
        if ($IsWindows) { Join-Path $Env:LOCALAPPDATA "ExpressionCache\$AppName" }
        else            { Join-Path $HOME ".cache/ExpressionCache/$AppName" }

    # Start clean
    $script:RegisteredStorageProviders = @()

    $builtin = [pscustomobject]@{
        Name        = 'LocalFileSystemCache'
        Description = 'Stores cached expressions in the local file system.'
        Config      = [pscustomobject]@{
            CacheVersion    = 1 #$script:Config.Version
            CacheFolder     = $defaultCacheFolder
            MaximumAge      = (Get-Date).AddDays(-7)
            Initialized     = $false
        }
        ReadFromCache = 'Get-LocalFileSystem-CachedValue'
        Initialize    = 'Initialize-LocalFileSystemCache'
    }

    Add-ExpressionCacheProvider -Provider $builtin | Out-Null

    # Optional extras
    foreach ($p in ($Providers | Where-Object { $_ })) {
        Add-ExpressionCacheProvider -Provider $p | Out-Null
    }

    # (Optional) Return the registry for convenience
    return $script:RegisteredStorageProviders
}
