function Update-ProviderStateMeta {
    param($Provider)
    $rev = 0
    if ($Provider.State -and $Provider.State.TryGetValue('StateRevision', [ref]$rev)) { }
    $null = $Provider.State.AddOrUpdate('StateRevision', ($rev + 1), { param($k,$old) $old + 1 })
    $null = $Provider.State.AddOrUpdate('StateLastChangedUtc', [DateTime]::UtcNow, { param($k,$old) [DateTime]::UtcNow })
}
