function With-ProviderLock {
    param(
        $Provider, 
        [scriptblock]$Body
    )

    $l = Get-ProviderLock $Provider
    if ($l.IsWriteLockHeld) {
        & $Body
        return
    }

    $l.EnterWriteLock()

    try {
        & $Body
    }
    finally {
        $l.ExitWriteLock()
    }
}
