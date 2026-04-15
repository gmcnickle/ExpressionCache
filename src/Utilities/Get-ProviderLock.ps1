function Get-ProviderLock {
    param($Provider)
    if (-not $Provider.__Lock) {
        # Initialize once; contention here is negligible
        $Provider.__Lock = New-Object System.Threading.ReaderWriterLockSlim(
            [System.Threading.LockRecursionPolicy]::NoRecursion)
    }
    $Provider.__Lock
}
