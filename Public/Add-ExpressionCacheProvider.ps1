function Add-ExpressionCacheProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Provider
    )

    process {
        if (-not $script:RegisteredStorageProviders) 
        { 
            $script:RegisteredStorageProviders = @() 
        }

        $spec = Test-ExpressionCacheProviderSpec -Spec $Provider

        # Merge any InitializeArgs -> Config (once), then drop InitializeArgs to avoid drift
        if ($spec.PSObject.Properties.Name -contains 'InitializeArgs' -and $spec.InitializeArgs) {
            $spec.Config = Merge-ExpressionCacheConfig -Base $spec.Config -Overrides $spec.InitializeArgs
            
            $null = $spec.PSObject.Properties.Remove('InitializeArgs')
        }

        # Prevent duplicates by Name (case-insensitive)
        $existing = $script:RegisteredStorageProviders | Where-Object { $_.Name -eq $spec.Name } | Select-Object -First 1

        if ($existing) {
            throw "ExpressionCache: A provider named '$($spec.Name)' is already registered."
        }

        $script:RegisteredStorageProviders += ,$spec

        # Eager initialize (from Config) if an Initialize function is provided
        if ($spec.Initialize) {
            $paramSet = Build-SplatFromConfig -CommandName $spec.Initialize -Config $spec.Config
            Assert-MandatoryParamsPresent -CommandName $spec.Initialize -Splat $paramSet

            & $spec.Initialize @paramSet

            if ($spec.Config.PSObject.Properties.Name -contains 'Initialized') {
                $spec.Config.Initialized = $true
            }
        }

        return $spec
    }
}
