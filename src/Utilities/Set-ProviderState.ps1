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
    Invoke-ProviderLockedOperation -Provider $Provider {
        $Provider.State = $dict
        Update-ProviderStateMeta $Provider
    }
}
