
function Get-ProviderConfig {
    param($Provider, [switch]$Raw)

    $cfg = With-ReadLock {
        $Provider.Config
    }

    if ($Raw) { # for internal use only
        return $cfg 
    } 

    return Copy-OrderedShallow $cfg  # external callers get a snapshot
}