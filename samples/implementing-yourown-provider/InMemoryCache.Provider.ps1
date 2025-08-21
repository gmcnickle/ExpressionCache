# InMemoryCache.Provider.ps1
using namespace System.Collections.Concurrent
using namespace System.Threading

# ------------ module/process-scoped state ------------
$script:IM_Cache = [ConcurrentDictionary[string, object]]::new()
$script:IM_Expiry = [ConcurrentDictionary[string, datetime]]::new()
$script:IM_Locks = [ConcurrentDictionary[string, SemaphoreSlim]]::new()
$script:IM_Prefix = ''
$script:IM_DefaultTtl = [TimeSpan]::FromMinutes(30)


function script:Get-IM-Key([string]$Key, [string]$CacheVersion) {
    if ([string]::IsNullOrWhiteSpace($CacheVersion)) { 
        $CacheVersion = 'v0' 
    }

    if ($script:IM_Prefix) { 
        return "$($script:IM_Prefix):$($CacheVersion):$Key" 
    }

    return "$($CacheVersion):$Key"
}

function script:Test-IM-Expired([string]$fqKey, [datetime]$nowUtc) {

    [datetime]$exp = [datetime]::MinValue 
    if ($script:IM_Expiry.TryGetValue($fqKey, [ref]$exp)) {
        return ($exp -le $nowUtc)
    }

    $true
}

function Initialize-InMemoryCache {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Prefix = '',

        [Parameter()]
        [TimeSpan]$DefaultTtl = [TimeSpan]::FromMinutes(30)
    )

    $script:IM_Prefix = $Prefix
    $script:IM_DefaultTtl = $DefaultTtl
}

function Clear-InMemory-Cache {
    $script:IM_Cache.Clear()
    $script:IM_Expiry.Clear()

    foreach ($p in $script:IM_Locks.GetEnumerator()) { 
        $p.Value.Dispose() 
    }

    $script:IM_Locks.Clear()
}

function Get-OrCreate-InMemory-Cache {
    param(
        [string]$Key,
        [string]$ProviderName,
        [scriptblock]$ScriptBlock,
        [object[]]$Arguments,
        $CachePolicy,
        [string]$CacheVersion
    )

    $fqKey = (Get-IM-Key $Key $CacheVersion)
    $now   = [DateTime]::UtcNow

    $force = $false
    $ttl   = $script:IM_DefaultTtl

    if ($null -ne $CachePolicy) {
        if ($CachePolicy.PSObject.Properties.Match('ForceRefresh').Count -gt 0) {
            $force = [bool]$CachePolicy.ForceRefresh
        }
        if ($CachePolicy.PSObject.Properties.Match('MaxAge').Count -gt 0 -and $CachePolicy.MaxAge -is [TimeSpan]) {
            $ttl = [TimeSpan]$CachePolicy.MaxAge
        }
    }

    if (-not $force) {
        [object]$existing = $null                # <-- predeclare for StrictMode
        if ($script:IM_Cache.TryGetValue($fqKey, [ref]$existing)) {
            if (-not (Test-IM-Expired $fqKey $now)) {
                return $existing
            }
        }
    }

    # per-key gate to ensure single compute
    $sem = $script:IM_Locks.GetOrAdd($fqKey, { [SemaphoreSlim]::new(1, 1) })
    $null = $sem.Wait()
    try {
        if (-not $force) {
            [object]$val2 = $null               # <-- predeclare for StrictMode
            if ($script:IM_Cache.TryGetValue($fqKey, [ref]$val2)) {
                if (-not (Test-IM-Expired $fqKey $now)) {
                    return $val2
                }
            }
        }

        $Arguments = if ($Arguments) { $Arguments } else { @() }
        $val = & $ScriptBlock @Arguments

        $script:IM_Cache[$fqKey]  = $val
        $script:IM_Expiry[$fqKey] = $now + $ttl
        return $val
    }
    finally {
        $sem.Release() | Out-Null
    }
}


# ---------- Provider facade (matches your contract) ----------
function New-InMemoryCacheProvider {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name = 'InMemoryCache',

        [Parameter()]
        [string]$Prefix = '',

        [Parameter()]
        [TimeSpan]$DefaultTtl = [TimeSpan]::FromMinutes(30)
    )

    @{
        Name       = $Name
        Type       = 'InMemory'
        Config     = @{
            Prefix       = $Prefix
            DefaultTtl   = $DefaultTtl
            CacheVersion = 1.0
        }

        GetOrCreate = 'Get-OrCreate-InMemory-Cache'
        Initialize = 'Initialize-InMemoryCache'
        ClearCache = 'Clear-InMemory-Cache'
    }
}
