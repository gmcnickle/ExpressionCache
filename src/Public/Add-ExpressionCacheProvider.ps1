<#
.SYNOPSIS
Registers a cache provider with ExpressionCache.

.DESCRIPTION
Add-ExpressionCacheProvider registers a provider specification and (if an Initialize function
is supplied) eagerly initializes it. The provider spec may be a hashtable or PSCustomObject.
It is validated and normalized by Test-ExpressionCacheProviderSpec.

Configuration semantics:
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
    # 1) Validate/normalize spec (no lock needed)
    $spec = Test-ExpressionCacheProviderSpec -Spec $Provider
    $target = "Provider '$($spec.Name)'"
    $registered = $false

    # 2) Ensure the registry exists (write-lock, once)
    if ($null -eq $script:RegisteredStorageProviders) {
      $script:StateLock.EnterWriteLock()
      try {
        if ($null -eq $script:RegisteredStorageProviders) {
          $script:RegisteredStorageProviders = [ordered]@{}
        }
      } 
      finally { 
        $script:StateLock.ExitWriteLock() 
      }
    }

    # 3) Atomic "check-then-add" with upgradeable read → write
    $script:StateLock.EnterUpgradeableReadLock()
    try {
      if ($script:RegisteredStorageProviders.Contains($spec.Name)) {`
        throw "ExpressionCache: A provider named '$($spec.Name)' is already registered."
      }

      if ($PSCmdlet.ShouldProcess($target, 'Register')) {
        $script:StateLock.EnterWriteLock()
        try {
          # Re-check under the write lock to avoid a race
          if ($script:RegisteredStorageProviders.Contains($spec.Name)) {
            throw "ExpressionCache: A provider named '$($spec.Name)' is already registered."
          }
          $script:RegisteredStorageProviders[$spec.Name] = $spec
          $registered = $true
        } 
        finally { 
          $script:StateLock.ExitWriteLock() 
        }
      }
    }
    finally { 
      $script:StateLock.ExitUpgradeableReadLock() 
    }

    # 4) Eager initialize OUTSIDE the registry lock
    if ($registered -and $spec.Initialize) {
      if ($PSCmdlet.ShouldProcess($target, 'Initialize')) {
        try {
          $paramSet = Build-SplatFromConfig -CommandName $spec.Initialize -Config $spec.Config
          Assert-MandatoryParamsPresent -CommandName $spec.Initialize -Splat $paramSet
          & $spec.Initialize @paramSet

          Set-ProviderStateValue -Provider $Provider -Key 'Initialized' -Value $true
        } 
        catch {
          # Optional: record failure for diagnostics (don’t hold the module lock here)
          Set-ProviderStateValue -Provider $Provider -Key 'InitializationError' -Value $_.Exception.Message
          throw
        }
      }
    }

    return $spec
  }
}
