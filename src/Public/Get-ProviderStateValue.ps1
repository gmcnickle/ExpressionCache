function Get-ProviderStateValue {
    param($Provider,
        [string]$Key,
        [object]$Default = $null
    )

    With-ProviderLock $Provider {
        $out = $null
        if ($Provider.State -and $Provider.State.TryGetValue($Key, [ref]$out)) {
            return $out
        }

        return $Default
    }
}
