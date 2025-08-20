<#
.SYNOPSIS
Gets a cached value if present; otherwise computes it via a ScriptBlock and caches the result.

.DESCRIPTION
Get-ExpressionCache provides a provider-agnostic "get or create" operation. When a cache entry is
missing or stale, the supplied ScriptBlock is invoked with -Arguments, its result is returned, and
the provider stores it. Keys are either supplied via -Key or generated deterministically from the
ScriptBlock and Arguments.

Provider selection:
- Uses -ProviderName if supplied; otherwise ENV var EXPRESSIONCACHE_PROVIDERNAME; otherwise 'LocalFileSystemCache'.

Freshness:
- Use -MaxAge for “stale if older than…” logic (TTL-like).
- Use -ExpireAtUtc for an absolute expiration time (some providers translate to TTL).

.PARAMETER Key
Optional cache key. If omitted, a stable key is generated from the ScriptBlock and Arguments.
Avoid putting secrets in keys; prefer opaque, stable identifiers.

.PARAMETER ScriptBlock
The computation to run on a cache miss. Invoked with the supplied -Arguments.

.PARAMETER Arguments
Arguments passed positionally to the ScriptBlock.

.PARAMETER ProviderName
Provider to use (e.g., 'LocalFileSystemCache', 'Redis').  Defaults to $env:EXPRCACHE_DEFAULT_PROVIDER, or if thats empty, 'LocalFileSystem'.

.PARAMETER MaxAge
A TimeSpan; cached values older than this are treated as stale and recomputed.

.PARAMETER ExpireAtUtc
An absolute UTC DateTime at which the entry should expire.

.OUTPUTS
System.Object  (whatever the ScriptBlock returns)

.EXAMPLE
# GitHub API (cache repo metadata for 10 minutes)
# Requires a GitHub token in $env:GITHUB_TOKEN. GitHub requires a User-Agent header.
$owner  = 'PowerShell'
$repo   = 'PowerShell'
$url    = "https://api.github.com/repos/$owner/$repo"
$header = @{
  'User-Agent'   = 'ExpressionCache'
  'Authorization' = "Bearer $($env:GITHUB_TOKEN)"
}
Get-ExpressionCache `
  -Key        "github:repos/$owner/$repo" `
  -MaxAge     (New-TimeSpan -Minutes 10) `
  -ScriptBlock {
    param($u, $h)
    Invoke-RestMethod -Uri $u -Headers $h -Method GET
  } `
  -Arguments  $url, $header

.EXAMPLE
# Jira REST API (cache an issue for 15 minutes)
# Assumes $env:JIRA_EMAIL and $env:JIRA_API_TOKEN are set (Atlassian Cloud).
$base   = 'https://yourcompany.atlassian.net'
$issue  = 'PROJ-123'
$basic  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($env:JIRA_EMAIL):$($env:JIRA_API_TOKEN)"))
$header = @{ Authorization = "Basic $basic" }
Get-ExpressionCache `
  -Key        "jira:issue:$issue" `
  -MaxAge     (New-TimeSpan -Minutes 15) `
  -ScriptBlock {
    param($b, $i, $h)
    Invoke-RestMethod -Uri "$b/rest/api/3/issue/$i" -Headers $h -Method GET
  } `
  -Arguments  $base, $issue, $header

.EXAMPLE
# Daily refresh using an absolute expiration (expires at next midnight UTC)
$tomorrowUtcMidnight = [DateTime]::UtcNow.Date.AddDays(1)
Get-ExpressionCache -Key 'daily:report' -ExpireAtUtc $tomorrowUtcMidnight -ScriptBlock {
  # ...expensive computation...
}

.EXAMPLE
# Use Redis provider explicitly for shared cache (password via env)
Get-ExpressionCache `
  -ProviderName 'Redis' `
  -Key 'feature-flags' `
  -MaxAge (New-TimeSpan -Minutes 5) `
  -ScriptBlock { Invoke-RestMethod 'https://api.example.com/flags' -Headers @{ Authorization = "Bearer $env:API_TOKEN" } }

.NOTES
- Do not embed secrets in cache keys. Pass tokens/headers via -Arguments or environment variables.
- Null results are not cached; if you need to cache “not found” results, wrap them in a sentinel object.
- When designing keys, include all inputs that affect the result (e.g., URL path + query, tenant, locale).
.LINK
New-ExpressionCacheKey
Initialize-ExpressionCache
Get-ExpressionCacheProvider
about_CommonParameters
#>
function Get-ExpressionCache {
  [CmdletBinding(DefaultParameterSetName = 'ByMaxAge')]
  param(
    [string]$ProviderName,

    [Parameter(Mandatory)]
    [scriptblock]$ScriptBlock,

    [object[]]$Arguments,

    [string]$Key,

    # A) Keep for this long (default)
    [Parameter(ParameterSetName = 'ByMaxAge')]
    [TimeSpan]$MaxAge,

    # B) Expire at this absolute time (UTC or local; normalized inside)
    [Parameter(ParameterSetName = 'ByAbsolute')]
    [DateTime]$ExpireAtUtc,

    # C) Sliding expiration: renew TTL on reads
    [Parameter(ParameterSetName = 'BySliding')]
    [TimeSpan]$SlidingAge
  )

  begin {
    if (-not $script:RegisteredStorageProviders) {
      throw "Module not initialized. Call Initialize-ExpressionCache first."
    }

    if (-not $ProviderName) {
        $ProviderName = $env:EXPRCACHE_DEFAULT_PROVIDER

        if (-not $ProviderName) { 
          $ProviderName = 'LocalFileSystemCache' 
        }
    }

    $strategy = $script:RegisteredStorageProviders |
    Where-Object { $_.Name -eq $ProviderName } |
    Select-Object -First 1

    if (-not $strategy) {
      throw "Provider '$ProviderName' not registered."
    }

    # Lazy init once per invocation
    if (-not $strategy.State.Initialized -and $strategy.Initialize) {

      $initSplat = Build-CallableSplat -CommandName $strategy.Initialize `
        -Config $strategy.Config `
        -PreferArgs `
        -Log -LogPrefix 'Init'

      Assert-MandatoryParamsPresent -CommandName $strategy.Initialize -Splat $initSplat

      & $strategy.Initialize @initSplat

      Write-Verbose "[Get-ExpressionCache] Provider '$ProviderName' initialized."
    }

    $providerFunc = $strategy.GetOrCreate
    if (-not (Get-Command $providerFunc -ErrorAction SilentlyContinue)) {
      throw "Provider function '$providerFunc' not found."
    }

    $cacheVersion = if ($strategy.Config.PSObject.Properties.Name -contains 'CacheVersion' -and $strategy.Config.CacheVersion) {
      $strategy.Config.CacheVersion
    }
    else {
      $script:Config.Version
    }
  }

  process {
    # Auto-generate a stable key if not provided
    $keyToUse = if ($Key) { $Key } else { New-ExpressionCacheKey -ScriptBlock $ScriptBlock -Arguments $Arguments }

    $defaultPolicy = $strategy.Config.DefaultPolicy
    $defaultMaxAge = $strategy.Config.DefaultMaxAge
    $policy = Resolve-CachePolicy -MaxAge $MaxAge -ExpireAtUtc $ExpireAtUtc -SlidingAge $SlidingAge -DefaultPolicy $defaultPolicy -DefaultMaxAge $defaultMaxAge

    # Base args common to all providers
    $runtimeArgs = @{
      ProviderName = $ProviderName
      Key          = $keyToUse
      ScriptBlock  = $ScriptBlock
      Arguments    = $Arguments
      CacheVersion = $cacheVersion
      Policy       = $policy
    }

    # Provider-specific extras (e.g., LocalFS needs CacheFolder)
    if ($strategy.Config.PSObject.Properties.Name -contains 'CacheFolder' -and $strategy.Config.CacheFolder) {
      $runtimeArgs.CacheFolder = $strategy.Config.CacheFolder
    }

    $splat = Build-CallableSplat -CommandName $providerFunc `
      -Config $strategy.Config `
      -Arguments $runtimeArgs `
      -PreferArgs `
      -Log -LogPrefix 'Provider'

    Write-Verbose "[Get-ExpressionCache] Invoking provider '$providerFunc' with $($splat.Keys.Count) params. Key='$keyToUse' Mode=$($policy.Mode) TTL=$($policy.TtlSeconds)s"
    & $providerFunc @splat
  }

  end { }
}
