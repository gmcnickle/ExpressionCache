function Resolve-Provider {
    param(
        [Parameter(Mandatory)] 
        $Hint,

        [Parameter(Mandatory)] 
        $DefaultMap  # from Get-DefaultProviders
    )

    switch ($Hint.GetType().FullName) {
        'System.String' {
            # Treat as a default key alias
            if ($DefaultMap.Contains($Hint)) {
                return $DefaultMap[$Hint]
            }
            # Allow matching by provider Name too
            $byName = $DefaultMap.Values | Where-Object { $_.Name -eq $Hint }

            if ($byName) { 
                return $byName 
            }

            throw "Unknown provider key or name '$Hint'."
        }

        default {
            # If it looks like a full provider, use it as-is
            if ($Hint.PSObject.Properties.Name -contains 'GetOrCreate' -and $Hint.PSObject.Properties.Name -contains 'Initialize') {
                return $Hint
            }

            # Otherwise treat it as an override onto a default
            # Prefer 'Key' to pick the default entry; fallback to Name matching
            $key = $Hint.Key
            $base =
            if ($key -and $DefaultMap.Contains($key)) {
                $DefaultMap[$key]
            } 
            elseif ($Hint.Name) {
                $DefaultMap.Values | Where-Object { $_.Name -eq $Hint.Name } | Select-Object -First 1
            }

            if (-not $base) { 
                throw "Could not match override to a default provider (Key/Name missing or unknown)." 
            }

            return (Merge-ObjectDeep $base $Hint)
        }
    }
}
