function Add-LocalFileSystemProvider()
{
    $defaultCacheFolder =
        if ($IsWindows) { 
            Join-Path $Env:LOCALAPPDATA "ExpressionCache\$AppName" 
        }
        else { 
            Join-Path $HOME ".cache/ExpressionCache/$AppName" 
        }

    $localfilesystem = [pscustomobject]@{
        Name        = 'LocalFileSystemCache'
        Description = 'Stores cached expressions in the local file system.'
        Config      = [pscustomobject]@{
            CacheVersion    = 1 
            CacheFolder     = $defaultCacheFolder
            MaximumAge      = (Get-Date).AddDays(-7)
            Initialized     = $false
        }
        ReadFromCache = 'Get-LocalFileSystem-CachedValue'
        Initialize    = 'Initialize-LocalFileSystemCache'
    }

    Add-ExpressionCacheProvider -Provider $localfilesystem | Out-Null
}

function Add-RedisProvider()
{
    $redis = [pscustomobject]@{
        Name     = 'redis-default'
        Config   = [PSCustomObject]@{
            Host     = '127.0.0.1'
            Port     = 6379
            Database = 2
            Prefix   = 'ExpressionCache:v1'
            Password = "ChangeThisPassword!"
        }
        ReadFromCache = 'Get-Redis-CachedValue'
        Initialize    = 'Initialize-Redis'
    }    

    Add-ExpressionCacheProvider -Provider $redis | Out-Null
}

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

    $script:RegisteredStorageProviders = @()

    Add-LocalFileSystemProvider
    Add-RedisProvider

    foreach ($p in ($Providers | Where-Object { $_ })) {
        Add-ExpressionCacheProvider -Provider $p | Out-Null
    }

    return $script:RegisteredStorageProviders
}
