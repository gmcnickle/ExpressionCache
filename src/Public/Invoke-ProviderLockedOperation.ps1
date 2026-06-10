function Invoke-ProviderLockedOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Provider,

        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock
    )

    $l = Get-ProviderLock $Provider
    if ($l.IsWriteLockHeld) {
        & $ScriptBlock
        return
    }

    $l.EnterWriteLock()

    try {
        & $ScriptBlock
    }
    finally {
        $l.ExitWriteLock()
    }
}
