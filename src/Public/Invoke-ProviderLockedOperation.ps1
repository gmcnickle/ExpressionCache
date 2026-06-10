function Invoke-ProviderLockedOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Provider,

        [Parameter(Mandatory, Position = 0)]
        [Alias('ScriptBlock')]
        [scriptblock]$Operation
    )

    $l = Get-ProviderLock $Provider
    if ($l.IsWriteLockHeld) {
        & $Operation
        return
    }

    $l.EnterWriteLock()

    try {
        & $Operation
    }
    finally {
        $l.ExitWriteLock()
    }
}
