function Validate-ExpressionCacheProviders {
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary]$Providers
    )

    $validated = [ordered]@{}
    # case-insensitive name de-dupe
    $seenNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($key in $Providers.Keys) {
        $raw = $Providers[$key]

        # Guard against accidental arrays (e.g., passing @($spec))
        if ($raw -is [array]) {
            throw "Provider '$key' value must be a single spec object, not an array."
        }

        $spec = Test-ExpressionCacheProviderSpec -Spec $raw  # returns a **hashtable**

        if (-not $seenNames.Add($spec.Name)) {
            throw "Duplicate provider name '$($spec.Name)' detected. Names must be unique (case-insensitive)."
        }

        $validated[$key] = $spec
    }

    return $validated
}
