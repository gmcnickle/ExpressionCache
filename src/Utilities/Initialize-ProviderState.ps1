function Initialize-ProviderState {
    param($Provider)
    if ($null -eq $Provider.State) {
        Invoke-ProviderLockedOperation -Provider $Provider {
            if ($null -eq $Provider.State) {
                $Provider.State = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]'
            }
        }
    }
}
