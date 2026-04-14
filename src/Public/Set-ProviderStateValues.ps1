function Set-ProviderStateValues {
    [CmdletBinding()]
    param(
        $Provider,
        [Parameter(Mandatory)][hashtable]$Patch,
        [switch]$NonAtomic  # default is atomic (grouped under provider write lock)
    )

    Ensure-ProviderState $Provider

    if ($NonAtomic) {
        # Fast path, each key atomic but group is not
        foreach ($k in $Patch.Keys) {
            $v = $Patch[$k]
            $null = $Provider.State.AddOrUpdate($k, $v, { param($kk, $old) $v })
        }
        Bump-ProviderStateMeta $Provider
        return
    }

    # Atomic group update
    With-ProviderLock $Provider {
        foreach ($k in $Patch.Keys) {
            $v = $Patch[$k]
            # Direct indexer set is fine under exclusive lock
            $Provider.State[$k] = $v
        }
        Bump-ProviderStateMeta $Provider
    }
}