function Ensure-ProviderState {
    param($Provider)
    if ($null -eq $Provider.State) {
        With-ProviderLock $Provider {
            if ($null -eq $Provider.State) {
                $Provider.State = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, object]'
            }
        }
    }
}
