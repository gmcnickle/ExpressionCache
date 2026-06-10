function Get-ProviderStateValue {
    param($Provider,
        [string]$Key,
        [object]$Default = $null
    )

    Invoke-ProviderLockedOperation -Provider $Provider {
        $out = $null
        if ($Provider.State -and $Provider.State.TryGetValue($Key, [ref]$out)) {
            return $out
        }

        return $Default
    }
}
