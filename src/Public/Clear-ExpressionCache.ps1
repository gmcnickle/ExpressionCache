<#
.SYNOPSIS
Clears cache data for a given provider.

.DESCRIPTION
Clears the cache for a registered ExpressionCache provider. This delegates to the provider’s
`ClearCache` hook via `Invoke-ExpressionCacheProviderHook`. If the provider does not implement
a `ClearCache` hook, an error is thrown.

Supports -WhatIf / -Confirm via ShouldProcess.

.PARAMETER ProviderName
The name of the registered provider to clear (e.g., 'LocalFileSystemCache', 'Redis').

.PARAMETER Force
Passed through to the provider hook when supported. Providers may use it to perform destructive
clears (e.g., delete all files, issue broad key deletions).

.INPUTS
None

.OUTPUTS
None

.EXAMPLE
# Preview without making changes
Clear-ExpressionCache -ProviderName LocalFileSystemCache -WhatIf

.EXAMPLE
# Clear Redis cache (provider must implement ClearCache)
Clear-ExpressionCache -ProviderName Redis -Force

.NOTES
- This command does not fall back to provider-specific ad hoc clearing if the hook is missing;
  implement a ClearCache function on the provider to participate.
- Use Get-ExpressionCacheProvider to inspect provider configuration before clearing.

.LINK
Get-ExpressionCacheProvider
Invoke-ExpressionCacheProviderHook
about_CommonParameters
#>
function Clear-ExpressionCache {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
  param(
    [Parameter(Mandatory)]
    [string]$ProviderName,
    [switch]$Force
  )

  $provider = Get-ExpressionCacheProvider -Name $ProviderName
  if (-not $provider) {
    throw "ExpressionCache: Provider '$ProviderName' not registered."
  }

  $target = "Provider '$ProviderName'"

  if ($PSCmdlet.ShouldProcess($target, 'Clear cache')) {
    try {
      # Delegate to the provider’s ClearCache hook (if implemented)
      $arguments = @{
        ProviderName = $ProviderName
        Force        = [bool]$Force
      }

      # This utility should map only supported parameters to the hook
      Invoke-ExpressionCacheProviderHook -ProviderName $ProviderName -Hook 'ClearCache' -Arguments $arguments | Out-Null
    }
    catch {
      # Surface a friendly error if the hook is missing or failed
      $msg = $_.Exception.Message
      if ($msg -match '(?i)(not\s+found|missing|no\s+such\s+hook)') {
        throw "ExpressionCache: Provider '$ProviderName' does not implement a ClearCache hook."
      }
      throw "ExpressionCache: Failed to clear provider '$ProviderName'. $_"
    }
  }
}
