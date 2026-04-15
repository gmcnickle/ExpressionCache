function Set-ProviderState {
    [CmdletBinding()]
    param(
        $Provider,
        [Parameter(Mandatory)][hashtable]$NewState
    )
    $dict = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]'
    foreach ($k in $NewState.Keys) {
        $null = $dict.TryAdd($k, $NewState[$k])
    }
    With-ProviderLock $Provider {
        $Provider.State = $dict
        Bump-ProviderStateMeta $Provider
    }
}