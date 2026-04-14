function Set-ProviderState {
    [CmdletBinding()]
    param(
        $Provider,
        [Parameter(Mandatory)][hashtable]$NewState
    )
    $dict = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
    foreach ($k in $NewState.Keys) {
        $null = $dict.TryAdd($k, $NewState[$k])
    }
    With-ProviderLock $Provider {
        $Provider.State = $dict
        Bump-ProviderStateMeta $Provider
    }
}