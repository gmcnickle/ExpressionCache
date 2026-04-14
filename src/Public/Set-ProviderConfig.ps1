function Set-ProviderConfig {
  param(
    $Provider, 
    [Parameter(Mandatory)]
    [hashtable]$NewConfig
  )

  # Build a new ordered table, then atomically replace under write lock
  $cloned = Copy-OrderedShallow $NewConfig

  With-WriteLock {
    $Provider.Config = $cloned
    $rev = if ($null -eq $Provider.ConfigRevision) { 0 } else { $Provider.ConfigRevision }
    $Provider.ConfigRevision = 1 + $rev
    $Provider.ConfigLastChangedUtc = [DateTime]::UtcNow
  }
}