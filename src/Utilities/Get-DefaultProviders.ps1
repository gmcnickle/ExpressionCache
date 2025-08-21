function Get-DefaultProviders {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Intentional plural for clarity: returns multiple providers.')]

    # TODO: Move this to localfilesystem init... (pass appname)
    $defaultCacheFolder =
        if ($IsWindows) {
            Join-Path $Env:LOCALAPPDATA "ExpressionCache\$($script:Config.AppName)"
        } else {
            Join-Path $HOME ".cache/ExpressionCache/$($script:Config.AppName)"
        }

    # Return an ordered hashtable keyed by short provider key; values are hashtables
    $providers = [ordered]@{
        LocalFileSystemCache = @{
            Name        = 'LocalFileSystemCache'
            Description = 'Stores cached expressions in the local file system.'
            Config      = @{
                ProviderName  = 'LocalFileSystemCache'
                CacheVersion  = 1
                CacheFolder   = $defaultCacheFolder
                DefaultMaxAge = (New-TimeSpan -Days 1)
            }
            GetOrCreate = 'Get-LocalFileSystem-CachedValue'
            Initialize  = 'Initialize-LocalFileSystem-Cache'
            ClearCache  = 'Clear-LocalFileSystem-Cache'   
        }

        Redis = @{
            # Align Name with key to avoid key/name mismatch downstream
            Name   = 'Redis'
            Config = @{
                ProviderName  = 'Redis'   # used as key/identifier consistently
                Host          = '127.0.0.1'
                Port          = 6379
                Database      = 2
                Prefix        = "ExpressionCache:v$($Script:moduleData.ModuleVersion.Major):$($script:Config.AppName)"
                Password      = if ($env:EXPRCACHE_REDIS_PASSWORD) { $env:EXPRCACHE_REDIS_PASSWORD } else { 'ChangeThisPassword!' }
                DefaultMaxAge = (New-TimeSpan -Days 1)
                DeferClientCreation = $true
            }
            GetOrCreate = 'Get-Redis-CachedValue'
            Initialize  = 'Initialize-Redis-Cache'
            ClearCache  = 'Clear-Redis-Cache'             
        }
    }

    return $providers
}
