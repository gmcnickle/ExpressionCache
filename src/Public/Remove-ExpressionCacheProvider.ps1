<#
.SYNOPSIS
Removes a registered ExpressionCache provider.

.DESCRIPTION
Removes a provider from the module’s registered provider list. Supports -WhatIf / -Confirm via
ShouldProcess. If the provider spec includes an optional Teardown hook, it is invoked before
removal (errors are logged as Verbose and do not stop removal).

- Name matching is case-insensitive.
- If no provider with the given name exists, a warning is written and nothing is removed.
- Use -PassThru to return the removed provider object(s).

.PARAMETER ProviderName
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
Remove-ExpressionCacheProvider -ProviderName Redis -Confirm

.EXAMPLE
# Preview without changing state
Remove-ExpressionCacheProvider -ProviderName LocalFileSystemCache -WhatIf

.EXAMPLE
# Pipe provider objects (ValueFromPipelineByPropertyName) and capture what was removed
$removed = Get-ExpressionCacheProvider -ProviderName Redis |
  Remove-ExpressionCacheProvider -PassThru -Confirm:$false

.EXAMPLE
# Remove multiple by name via the pipeline
'Redis','LocalFileSystemCache' | Remove-ExpressionCacheProvider -Confirm:$false

.EXAMPLE
# Suppress the "not found" warning if the provider may not exist
Remove-ExpressionCacheProvider -ProviderName 'DoesNotExist' -ErrorAction SilentlyContinue

.NOTES
- If the provider spec exposes a Teardown command, it is invoked prior to removal.
  Failures during teardown are written as Verbose messages.
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
        [Alias('Name')]
        [ValidateNotNullOrEmpty()]
        [string]$ProviderName,

        [switch]$PassThru
    )

    begin { $removed = @() }

    process {
        $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName -ErrorAction Ignore

        if (-not $provider) {
            Write-Error -Message "ExpressionCache: Provider '$ProviderName' is not registered." `
                -Category ObjectNotFound `
                -TargetObject $ProviderName
            return
        }

        if ($PSCmdlet.ShouldProcess($providerName, 'Remove storage provider')) {

            if ($provider.Contains('Teardown') -and $provider.Teardown) {
                try {
                    Invoke-ExpressionCacheProviderHook `
                        -ProviderName $ProviderName `
                        -Hook Teardown `
                        -Arguments @{ ProviderName = $ProviderName } | Out-Null
                }
                catch {
                    Write-Verbose "Teardown failed for '$($provider.Name)': $_"
                }
            }

            # Remove this specific instance
            With-WriteLock {
                $script:RegisteredStorageProviders.Remove($ProviderName)
            }

            if ($PassThru) { 
                $removed += , $provider 
            }
        }
    }

    end {
        if ($PassThru -and $removed) { 
            $removed 
        }
    }
}
