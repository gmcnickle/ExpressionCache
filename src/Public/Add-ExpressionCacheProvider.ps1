<#
.SYNOPSIS
Registers a cache provider with ExpressionCache.

.DESCRIPTION
Add-ExpressionCacheProvider registers a provider specification and (if an Initialize function
is supplied) eagerly initializes it. The provider spec may be a hashtable or PSCustomObject.
It is validated and normalized by Test-ExpressionCacheProviderSpec.

Configuration semantics:
- One-time merge: if the spec contains InitializeArgs, those values are merged into Config
  at registration time (via Merge-ExpressionCacheConfig) and then InitializeArgs is removed.
- No duplicate names: registration fails if a provider with the same Name already exists
  (comparison is case-insensitive).
- Eager initialization: when the spec includes an Initialize function, it is invoked once
  using parameters built from Config (Build-SplatFromConfig). Required parameters are
  enforced (Assert-MandatoryParamsPresent). If Config has an 'Initialized' property,
  it is set to $true upon success.

Expected spec shape (examples below):
- Name or Key (string)     : provider name (e.g., 'LocalFileSystemCache', 'Redis').
- Config (PSCustomObject)  : provider configuration.
- Initialize (string)      : optional function name to prepare backing store.
- GetOrCreate (string)     : function name used to fetch/create cached values.
- ClearCache (string)      : optional function name to clear cache state.
- InitializeArgs (hashtable, optional) : convenience values that will be merged into Config once.

.PARAMETER Provider
A provider specification (hashtable/PSCustomObject). Accepts pipeline input.
May use 'Key' instead of 'Name'; it is normalized during validation.

.INPUTS
System.Object  (provider spec via the pipeline)

.OUTPUTS
PSCustomObject  (the normalized/registered provider spec)

.EXAMPLE
# Register LocalFileSystem provider with explicit functions and config
Add-ExpressionCacheProvider @{
  Key        = 'LocalFileSystemCache'
  Initialize = 'Initialize-LocalFileSystem-Cache'
  GetOrCreate= 'Get-LocalFileSystem-CachedValue'
  ClearCache = 'Clear-LocalFileSystem-Cache'
  Config     = @{
    Prefix      = 'ExpressionCache:v1:MyApp'
    CacheFolder = "$env:TEMP/ExpressionCache"
  }
}

.EXAMPLE
# Register Redis; pass connection details via InitializeArgs (merged into Config once)
Add-ExpressionCacheProvider @{
  Key          = 'Redis'
  Initialize   = 'Initialize-Redis-Cache'
  GetOrCreate  = 'Get-Redis-CachedValue'
  ClearCache   = 'Clear-Redis-Cache'
  Config       = @{
    Prefix   = 'ExpressionCache:v1:MyApp'
    Database = 2
  }
  InitializeArgs = @{
    Host     = '127.0.0.1'
    Port     = 6379
    Password = $env:EXPRCACHE_REDIS_PASSWORD
  }
}

.EXAMPLE
# Register multiple providers via the pipeline
@(
  @{ Key='LocalFileSystemCache'; Config=@{ Prefix='ExpressionCache:v1:MyApp' } }
  @{ Key='Redis'; Config=@{ Prefix='ExpressionCache:v1:MyApp'; Database=2 }; Initialize='Initialize-Redis-Cache'; GetOrCreate='Get-Redis-CachedValue' }
) | Add-ExpressionCacheProvider

.EXAMPLE
# Preview registration/initialization without changing module state
Add-ExpressionCacheProvider @{ Key='LocalFileSystemCache'; Config=@{ Prefix='ExpressionCache:v1:MyApp' } } -WhatIf

.NOTES
- Duplicate names are rejected: "A provider named 'X' is already registered."
- When Initialize is present, missing mandatory parameters (as inferred from the command’s
  signature) will produce a validation error before initialization runs.
- If your provider tracks an Initialized boolean in Config, it will be set to $true after a
  successful Initialize call.

.LINK
Initialize-ExpressionCache
Get-ExpressionCacheProvider
Get-ExpressionCache
New-ExpressionCacheKey
about_CommonParameters
#>
function Add-ExpressionCacheProvider {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Provider
    )

    process {
        if (-not $script:RegisteredStorageProviders) {
            $script:RegisteredStorageProviders = @()
        }

        # Validate/normalize spec (safe to do even under -WhatIf)
        $spec = Test-ExpressionCacheProviderSpec -Spec $Provider

        # One-time merge: InitializeArgs -> Config, then drop InitializeArgs
        if ($spec.PSObject.Properties.Name -contains 'InitializeArgs' -and $spec.InitializeArgs) {
            $spec.Config = Merge-ExpressionCacheConfig -Base $spec.Config -Overrides $spec.InitializeArgs
            $null = $spec.PSObject.Properties.Remove('InitializeArgs')
        }

        # Duplicate check (fail fast, even with -WhatIf)
        $existing = $script:RegisteredStorageProviders |
            Where-Object { $_.Name -eq $spec.Name } |
            Select-Object -First 1
        if ($existing) {
            throw "ExpressionCache: A provider named '$($spec.Name)' is already registered."
        }

        $registered = $false
        $target = "Provider '$($spec.Name)'"

        # Register
        if ($PSCmdlet.ShouldProcess($target, 'Register')) {
            $script:RegisteredStorageProviders += , $spec
            $registered = $true
        }

        # Eager initialize (only if we actually registered above)
        if ($registered -and $spec.Initialize) {
            if ($PSCmdlet.ShouldProcess($target, 'Initialize')) {
                $paramSet = Build-SplatFromConfig -CommandName $spec.Initialize -Config $spec.Config
                Assert-MandatoryParamsPresent -CommandName $spec.Initialize -Splat $paramSet
                & $spec.Initialize @paramSet

                if ($spec.Config.PSObject.Properties.Name -contains 'Initialized') {
                    $spec.Config.Initialized = $true
                }
            }
        }

        return $spec
    }
}
