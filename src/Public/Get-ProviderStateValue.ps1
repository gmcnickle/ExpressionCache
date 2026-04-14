function Get-ProviderStateValue {
    param($Provider,
        [string]$Key,
        [object]$Default = $null
    )

    $out = $null
    if ($Provider.State -and $Provider.State.TryGetValue($Key, [ref]$out)) { 
        return $out 
    } 
    else { 
        return $Default 
    }
}
