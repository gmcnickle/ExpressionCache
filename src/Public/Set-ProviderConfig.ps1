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
    $Provider.ConfigRevision = 1 + ($Provider.ConfigRevision ?? 0)
    $Provider.ConfigLastChangedUtc = [DateTime]::UtcNow
  }
}