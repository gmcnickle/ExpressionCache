<#
.SYNOPSIS
Initializes ExpressionCache and registers cache providers.

.DESCRIPTION
Initialize-ExpressionCache sets up module-wide state (e.g., AppName used in key prefixes) and
registers one or more providers. Each provider is a hashtable with a 'Key' and a 'Config'.

❗ CONFIGURATION SEMANTICS
- Replacement, not merge: when you pass a Config for a built-in or previously-registered provider,
  the supplied object becomes the provider’s **entire** Config. Defaults/previous values are NOT merged.
  Any omitted settings will be unset (or fall back to the provider’s own internal defaults if it has them).
- Re-initializing: calling Initialize-ExpressionCache again with the same provider Key updates that
  provider using the same replacement semantics.

Tip: If you want to modify just one or two settings while keeping the rest of the defaults, copy the
current config first (see examples) and then change the keys you care about.

.PARAMETER AppName
Application name used in key prefixes/namespacing.

.PARAMETER Providers
One or more provider definitions of the form:
@{ Key = '<ProviderName>'; Config = @{ ... provider settings ... } }
The supplied Config **replaces** any existing/default config for that provider (no merge).

.OUTPUTS
The list of registered provider objects.

.EXAMPLE
# Initialize with defaults only (LocalFileSystemCache)
Initialize-ExpressionCache -AppName 'MyApp'

.EXAMPLE
# Replace LocalFileSystemCache config entirely (no merge)
Initialize-ExpressionCache -AppName 'MyApp' -Providers @(
  @{ Key='LocalFileSystemCache'; Config = @{
        Prefix = 'ExpressionCache:v1:MyApp'
        CacheFolder = "$env:TEMP\ExpressionCache"
     } }
)

.EXAMPLE
# Preserve defaults but tweak one setting: copy then modify
$prov = Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
$cfg  = [pscustomobject]@{}               # shallow clone of current config
$prov.Config.PSObject.Properties | ForEach-Object {
  Add-Member -InputObject $cfg -MemberType NoteProperty -Name $_.Name -Value $_.Value
}
$cfg.Prefix = 'ExpressionCache:v1:MyApp'
Initialize-ExpressionCache -AppName 'MyApp' -Providers @(@{ Key='LocalFileSystemCache'; Config = $cfg })

.EXAMPLE
# Add/replace a Redis provider config (password via env var)
Initialize-ExpressionCache -AppName 'MyApp' -Providers @(
  @{ Key='Redis'; Config = @{
        Host     = '127.0.0.1'
        Port     = 6379
        Database = 2
        Prefix   = 'ExpressionCache:v1:MyApp'
        Password = $env:EXPRCACHE_REDIS_PASSWORD
     } }
)

.LINK
Get-ExpressionCache
Get-ExpressionCacheProvider
New-ExpressionCacheKey
#>
function Initialize-ExpressionCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter()]
        [object[]]$Providers
    )

    $script:Config = [pscustomobject]@{
        AppName = $AppName
        Version = $Script:moduleData.ModuleVersion
    }

    $script:RegisteredStorageProviders = @()

    $defaults = Get-DefaultProviders

    # Start with the module's standard providers (order matters)
    $selected = @(
        $defaults.LocalFileSystemCache
        $defaults.Redis
    )

    # If the caller passes overrides/replacements, apply them
    foreach ($hint in ($Providers | Where-Object { $_ })) {
        $resolved = Resolve-Provider -Hint $hint -DefaultMap $defaults

        # If same .Name exists, replace; else append
        $names = $selected | Select-Object -ExpandProperty Name
        $existingIndex = [array]::IndexOf($names, $resolved.Name)  # -1 if not found

        if ($existingIndex -ge 0) { 
            $selected[$existingIndex] = $resolved 
        }
        else { 
            $selected += $resolved 
        }
    }

    # Register them
    foreach ($p in $selected) {
        Add-ExpressionCacheProvider -Provider $p | Out-Null
    }

    return $script:RegisteredStorageProviders
}

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

function Resolve-Provider {
    param(
        [Parameter(Mandatory)] 
        $Hint,

        [Parameter(Mandatory)] 
        $DefaultMap  # from Get-DefaultProviders
    )

    switch ($Hint.GetType().FullName) {
        'System.String' {
            # Treat as a default key alias
            if ($DefaultMap.Contains($Hint)) {
                return $DefaultMap[$Hint]
            }
            # Allow matching by provider Name too
            $byName = $DefaultMap.Values | Where-Object { $_.Name -eq $Hint }

            if ($byName) { 
                return $byName 
            }

            throw "Unknown provider key or name '$Hint'."
        }

        default {
            # If it looks like a full provider, use it as-is
            if ($Hint.PSObject.Properties.Name -contains 'GetOrCreate' -and $Hint.PSObject.Properties.Name -contains 'Initialize') {
                return $Hint
            }

            # Otherwise treat it as an override onto a default
            # Prefer 'Key' to pick the default entry; fallback to Name matching
            $key = $Hint.Key
            $base =
            if ($key -and $DefaultMap.Contains($key)) {
                $DefaultMap[$key]
            } 
            elseif ($Hint.Name) {
                $DefaultMap.Values | Where-Object { $_.Name -eq $Hint.Name } | Select-Object -First 1
            }

            if (-not $base) { 
                throw "Could not match override to a default provider (Key/Name missing or unknown)." 
            }

            return (Merge-ObjectDeep $base $Hint)
        }
    }
}


function Merge-ObjectDeep {
    param(
        [Parameter(Mandatory)] 
        $Base,
        
        [Parameter(Mandatory)] 
        $Override
    )

    if ($null -eq $Override) { 
        return $Base 
    }

    # For hashtables and PSCustomObjects, walk properties
    if ($Base -is [hashtable] -or $Base -is [pscustomobject]) {

        $result = if ($Base -is [hashtable]) { 
            @{} 
        } 
        else { 
            [pscustomobject]@{} 
        }

        $allKeys = @(if ($Base -is [hashtable]) { $Base.Keys } else { $Base.PSObject.Properties.Name }) + @(if ($Override -is [hashtable]) { $Override.Keys } else { $Override.PSObject.Properties.Name }) | Select-Object -Unique

        foreach ($k in $allKeys) {
            $b = if ($Base -is [hashtable]) { 
                $Base[$k] 
            } 
            else { 
                $Base.$k 
            }

            $o = if ($Override -is [hashtable]) { 
                $Override[$k] 
            } 
            else { 
                $Override.$k 
            }

            if ($null -ne $o -and ($b -is [hashtable] -or $b -is [pscustomobject])) {
                $result | Add-Member -NotePropertyName $k -NotePropertyValue (Merge-ObjectDeep $b $o)
            } 
            elseif ($null -ne $o) {
                $result | Add-Member -NotePropertyName $k -NotePropertyValue $o
            } 
            else {
                $result | Add-Member -NotePropertyName $k -NotePropertyValue $b
            }
        }
        return $result
    }

    # For scalars/arrays: override wins if provided, else base
    if ($null -ne $Override) { 
        return $Override 
    } 
    else { 
        return $Base 
    }
}



