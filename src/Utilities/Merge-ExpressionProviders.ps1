function Merge-ExpressionCacheProviders {
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary]$Defaults,
        [System.Collections.IDictionary]$Overrides,
        [switch]$Replace
    )

    if ($Replace -or -not $Defaults -or $Defaults.Count -eq 0) {
        return Validate-ExpressionCacheProviders -Providers $Overrides
    }

    # Start with a copy of the defaults (ordered)
    $merged = [ordered]@{}
    foreach ($key in $Defaults.Keys) { $merged[$key] = $Defaults[$key] }

    if ($Overrides) {
        foreach ($key in $Overrides.Keys) {
            if ($merged.Contains($key)) {
                $base     = $merged[$key]
                $override = $Overrides[$key]
                $mergedValue = Merge-ObjectDeep -Base $base -Override $override

                if ($base.Config -or $override.Config) {
                    $mergedValue.Config = Merge-ExpressionCacheConfig -Base $base.Config -Override $override.Config
                }
                $merged[$key] = $mergedValue
            }
            else {
                $merged[$key] = $Overrides[$key]
            }
        }
    }

    return Validate-ExpressionCacheProviders -Providers $merged
}
