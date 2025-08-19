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
function Copy-PSCustomObject {
  param([Parameter(Mandatory)][pscustomobject]$InputObject)
  $copy = [pscustomobject]@{}
  foreach ($p in $InputObject.PSObject.Properties) {
    # shallow copy is fine for our flat configs
    Add-Member -InputObject $copy -NotePropertyName $p.Name -NotePropertyValue $p.Value
  }
  return $copy
}

function Initialize-ExpressionCache {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$AppName,
    [object[]]$Providers
  )

  $script:Config = [pscustomobject]@{
    AppName = $AppName
    Version = $Script:moduleData.ModuleVersion
  }
  $script:RegisteredStorageProviders = @()

  $defaults = Get-DefaultProviders

  # Treat -Providers as an allow-list when present; otherwise use defaults
  $explicit = $PSBoundParameters.ContainsKey('Providers') -and $Providers -and $Providers.Count -gt 0
  $selected = @()

  if (-not $explicit) {
    $selected = @($defaults.LocalFileSystemCache, $defaults.Redis)
  } else {
    foreach ($hint in ($Providers | Where-Object { $_ })) {
      $resolved = Resolve-Provider -Hint $hint -DefaultMap $defaults
      if (-not $resolved) { continue }

      # If matches a known default, overlay config onto a *clone* of the default
      $defaultMatch = switch -Regex ($resolved.Name) {
        '^LocalFileSystemCache$' { $defaults.LocalFileSystemCache; break }
        '^Redis$'                { $defaults.Redis; break }
      }

      if ($defaultMatch) {
        $mergedConfig = Copy-PSCustomObject $defaultMatch.Config
        if ($resolved.PSObject.Properties['Config'] -and $resolved.Config -is [System.Collections.IDictionary]) {
          Merge-ExpressionCacheConfig -Base $mergedConfig -Overrides $resolved.Config | Out-Null
        }

        # Build a merged spec keeping default hooks
        $selected += [pscustomobject]@{
          Name        = $defaultMatch.Name
          GetOrCreate = $defaultMatch.GetOrCreate
          Initialize  = $defaultMatch.Initialize
          ClearCache  = $defaultMatch.ClearCache
          Config      = $mergedConfig
        }
      }
      else {
        # Custom provider: use as-is (caller must supply functions & Config)
        $selected += $resolved
      }
    }
  }

  foreach ($p in $selected) {
    Add-ExpressionCacheProvider -Provider $p | Out-Null
  }

  return $script:RegisteredStorageProviders
}





