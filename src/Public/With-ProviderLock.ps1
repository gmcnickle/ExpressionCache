function With-ProviderLock {
    param(
        $Provider, 
        [scriptblock]$Body
    )

    $l = Get-ProviderLock $Provider
    $l.EnterWriteLock(); 
    
    try { 
        & $Body 
    } 
    finally { 
        $l.ExitWriteLock() 
    }
}
