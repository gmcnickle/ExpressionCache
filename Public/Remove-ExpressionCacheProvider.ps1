function Remove-ExpressionCacheProvider {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ProviderName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [switch]$PassThru
    )

    begin { $removed = @() }

    process {
        $matchesFound = $script:RegisteredStorageProviders |
                   Where-Object { $_.Name -eq $Name }

        if (-not $matchesFound) {
            Write-Warning "ExpressionCache: No provider named '$Name'."
            return
        }

        foreach ($prov in $matchesFound) {
            if ($PSCmdlet.ShouldProcess($prov.Name, 'Remove storage provider')) {
                # Optional teardown hook (if you add one in provider specs later)
                if ($prov.PSObject.Properties.Name -contains 'Deinitialize' -and $prov.Deinitialize) {
                    try { & $prov.Deinitialize } catch { Write-Verbose "Deinitialize failed for '$($prov.Name)': $_" }
                }

                # Remove this specific instance
                $script:RegisteredStorageProviders =
                    @($script:RegisteredStorageProviders | Where-Object { $_ -ne $prov })

                if ($PassThru) { $removed += ,$prov }
            }
        }
    }

    end {
        if ($PassThru -and $removed) { $removed }
    }
}
