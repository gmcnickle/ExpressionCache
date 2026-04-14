function Get-ProviderLock {
    param($Provider)
    if (-not $Provider.__Lock) {
        # Initialize once; contention here is negligible
        $Provider.__Lock = [System.Threading.ReaderWriterLockSlim]::new(
            [System.Threading.LockRecursionPolicy]::NoRecursion)
    }
    $Provider.__Lock
}
