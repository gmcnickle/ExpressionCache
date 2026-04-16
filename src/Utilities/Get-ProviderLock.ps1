# Dedicated sync object for serializing lazy lock creation
if (-not $script:__LockInitGuard) {
    $script:__LockInitGuard = New-Object object
}

function Get-ProviderLock {
    param($Provider)
    if (-not $Provider.__Lock) {
        # Double-checked locking: serialize only the first initialization
        [System.Threading.Monitor]::Enter($script:__LockInitGuard)
        try {
            if (-not $Provider.__Lock) {
                $Provider.__Lock = New-Object System.Threading.ReaderWriterLockSlim(
                    [System.Threading.LockRecursionPolicy]::NoRecursion)
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($script:__LockInitGuard)
        }
    }
    $Provider.__Lock
}
