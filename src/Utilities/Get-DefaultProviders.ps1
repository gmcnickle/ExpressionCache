function Get-DefaultProviders {
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Intentional plural for clarity: returns multiple providers.')]

    # TODO: Move this to localfilesystem init... (pass appname)
    $defaultCacheFolder =
    if ($IsWindows) {
        Join-Path $Env:LOCALAPPDATA "ExpressionCache\$($script:Config.AppName)"
    }
    else {
        Join-Path $HOME ".cache/ExpressionCache/$($script:Config.AppName)"
    }

    # Return an ordered hashtable keyed by a short provider key
    [ordered]@{
        LocalFileSystemCache = [pscustomobject]@{
            Name        = 'LocalFileSystemCache'
            Description = 'Stores cached expressions in the local file system.'
            Config      = [pscustomobject]@{
                ProviderName  = 'LocalFileSystemCache'
                CacheVersion  = 1
                CacheFolder   = $defaultCacheFolder
                DefaultMaxAge = (New-TimeSpan -Days 1)
                Initialized   = $false
            }

            GetOrCreate = 'Get-LocalFileSystem-CachedValue'
            Initialize  = 'Initialize-LocalFileSystem-Cache'
            ClearCache  = 'Clear-LocalFileSystem-Cache'
        }

        Redis                = [pscustomobject]@{
            Name        = 'redis-default'
            Config      = [pscustomobject]@{
                ProviderName  = 'redis-default' # used as key
                Host          = '127.0.0.1'
                Port          = 6379
                Database      = 2
                DefaultMaxAge = (New-TimeSpan -Days 1)
                Prefix        = "ExpressionCache:v$($Script:moduleData.ModuleVersion.Major):$($script:Config.AppName)"
                Password      = $env:EXPRCACHE_REDIS_PASSWORD ?? 'ChangeThisPassword!'
            }

            GetOrCreate = 'Get-Redis-CachedValue'
            Initialize  = 'Initialize-Redis-Cache'
            ClearCache  = 'Clear-Redis-Cache'
        }
    }
}
