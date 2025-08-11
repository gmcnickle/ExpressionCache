function Get-ExpressionCache {
    [CmdletBinding()]
    param(
        [string]$Key,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock]$ScriptBlock,

        [object[]]$Arguments,

        [string]$StorageType = 'LocalFileSystemCache'
    )

    begin {
        if (-not $script:RegisteredStorageProviders) {
            throw "ExpressionCache: Module not initialized. Call Initialize-ExpressionCache first."
        }

        $strategy = $script:RegisteredStorageProviders |
            Where-Object { $_.Name -eq $StorageType } |
            Select-Object -First 1

        if (-not $strategy) {
            throw "ExpressionCache: Storage type '$StorageType' not registered."
        }

        # Lazy init once per invocation
        if (-not $strategy.Config.Initialized -and $strategy.Initialize) {
            $paramSet = Build-SplatFromConfig -CommandName $strategy.Initialize -Config $strategy.Config
            Assert-MandatoryParamsPresent -CommandName $strategy.Initialize -Splat $paramSet
            & $strategy.Initialize @paramSet
            if ($strategy.Config.PSObject.Properties.Name -contains 'Initialized') {
                $strategy.Config.Initialized = $true
            }
        }

        $providerFunc = $strategy.ReadFromCache
        if (-not (Get-Command $providerFunc -ErrorAction SilentlyContinue)) {
            throw "ExpressionCache: Provider function '$providerFunc' not found."
        }

        # Decide cache version once
        $cacheVersion = if ($strategy.Config.PSObject.Properties.Name -contains 'CacheVersion' -and $strategy.Config.CacheVersion) {
            $strategy.Config.CacheVersion
        } else {
            $script:Config.Version
        }
    }

    process {
        # Auto-generate a stable key if not provided
        $keyToUse = if ($Key) { $Key } else { New-ExpressionCacheKey -ScriptBlock $ScriptBlock -Arguments $Arguments }

        & $providerFunc `
            -Key          $keyToUse `
            -ScriptBlock  $ScriptBlock `
            -Arguments    $Arguments `
            -CacheFolder  $strategy.Config.CacheFolder `
            -MaximumAge   $strategy.Config.MaximumAge `
            -CacheVersion $cacheVersion
    }

    end { }
}
