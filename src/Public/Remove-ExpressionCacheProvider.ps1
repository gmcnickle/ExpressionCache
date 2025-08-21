<#
.SYNOPSIS
Removes a registered ExpressionCache provider.

.DESCRIPTION
Removes a provider from the module’s registered provider list. Supports -WhatIf / -Confirm via
ShouldProcess. If the provider spec includes an optional Deinitialize hook, it is invoked before
removal (errors are logged as Verbose and do not stop removal).

- Name matching is case-insensitive.
- If no provider with the given name exists, a warning is written and nothing is removed.
- Use -PassThru to return the removed provider object(s).

.PARAMETER Name
The provider name to remove (e.g., 'LocalFileSystemCache', 'Redis').
Accepts pipeline input by value (string) or by property name (objects with a Name or ProviderName property).

.PARAMETER PassThru
When set, outputs the removed provider object(s). Without this switch, the command is silent on success.

.INPUTS
System.String
Objects with a Name or ProviderName property (ValueFromPipelineByPropertyName)

.OUTPUTS
None, unless -PassThru is specified; then PSCustomObject (the removed provider spec).

.EXAMPLE
# Remove by name (with confirmation prompt)
Remove-ExpressionCacheProvider -Name Redis -Confirm

.EXAMPLE
# Preview without changing state
Remove-ExpressionCacheProvider -Name LocalFileSystemCache -WhatIf

.EXAMPLE
# Pipe provider objects (ValueFromPipelineByPropertyName) and capture what was removed
$removed = Get-ExpressionCacheProvider -Name Redis |
  Remove-ExpressionCacheProvider -PassThru -Confirm:$false

.EXAMPLE
# Remove multiple by name via the pipeline
'Redis','LocalFileSystemCache' | Remove-ExpressionCacheProvider -Confirm:$false

.EXAMPLE
# Suppress the "not found" warning if the provider may not exist
Remove-ExpressionCacheProvider -Name 'DoesNotExist' -WarningAction SilentlyContinue

.NOTES
- If the provider spec exposes a Deinitialize function, it is invoked prior to removal.
  Failures during deinitialization are written as Verbose messages.
- This command updates module state ($script:RegisteredStorageProviders).

.LINK
Add-ExpressionCacheProvider
Get-ExpressionCacheProvider
Clear-ExpressionCache
about_CommonParameters
#>
function Remove-ExpressionCacheProvider {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$ProviderName,

        [switch]$PassThru
    )

    begin { $removed = @() }

    process {
        $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName

        if (-not $provider) {
            Write-Warning "ExpressionCache: No provider named '$ProviderName'."
            return
        }

        if ($PSCmdlet.ShouldProcess($providerName, 'Remove storage provider')) {

            # Optional teardown hook (if you add one in provider specs later)
            if ($provider.Name -contains 'Deinitialize' -and $provider.Deinitialize) {
                try { & $provider.Deinitialize } catch { Write-Verbose "Deinitialize failed for '$($provider.Name)': $_" }
            }

            # Remove this specific instance
            $script:RegisteredStorageProviders.Remove($ProviderName)

            if ($PassThru) { 
                $removed += , $prov 
            }
        }
    }

    end {
        if ($PassThru -and $removed) { 
            $removed 
        }
    }
}
