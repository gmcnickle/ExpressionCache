function Set-ProviderStateValue {
    param(
        $Provider,
        [string]$Key,
        [object]$Value
    )

    Initialize-ProviderState $Provider

    $null = $Provider.State.AddOrUpdate($Key, $Value, { param($k, $old) $Value })
}
