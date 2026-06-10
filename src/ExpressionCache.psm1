# ExpressionCache.psm1

# --- Module metadata (from manifest) ---
$script:moduleData = Test-ModuleManifest -Path (Join-Path $PSScriptRoot 'ExpressionCache.psd1') -ErrorAction SilentlyContinue

# --- Module state (shared across all files) ---
$script:Config = $null
$script:RegisteredStorageProviders = @()

# --- Synchronization primitives (module scope) ---
# Reader/Writer for script-level maps & provider state/config
if (-not $script:StateLock) {
    $script:StateLock = New-Object System.Threading.ReaderWriterLockSlim([System.Threading.LockRecursionPolicy]::NoRecursion)
}

function script:With-ReadLock {
    param(
        [scriptblock]$Body
    )

    if ($script:StateLock.IsReadLockHeld -or $script:StateLock.IsUpgradeableReadLockHeld -or $script:StateLock.IsWriteLockHeld) {
        & $Body; return
    }

    $script:StateLock.EnterReadLock()

    try { 
        & $Body 
    } 
    finally { 
        $script:StateLock.ExitReadLock() 
    }
}

function script:With-WriteLock {
    param(
        [scriptblock]$Body
    )

    if ($script:StateLock.IsWriteLockHeld) { 
        & $Body; return 
    }

    $script:StateLock.EnterWriteLock()

    try { 
        & $Body 
    } 
    finally { 
        $script:StateLock.ExitWriteLock() 
    }
}

function script:Replace-Immutable {
    param(
        [Parameter(Mandatory)]
        [ref]$Target,

        [Parameter(Mandatory)]
        $NewValue
    )

    # Atomic replace under write lock
    With-WriteLock { $Target.Value = $NewValue }
}



$utilitiesFolder = (Join-Path $PSScriptRoot 'Utilities')
# --- Load Utilities ---
Get-ChildItem -Path $utilitiesFolder -Filter *.ps1 -ErrorAction SilentlyContinue |
Sort-Object Name |
ForEach-Object { . $_.FullName }

$providersFolder = (Join-Path $PSScriptRoot 'Providers')
# --- Load Providers ---
Get-ChildItem -Path $providersFolder -Filter *.ps1 -ErrorAction SilentlyContinue |
Sort-Object Name |
ForEach-Object { . $_.FullName }

$publicFolder = Join-Path $PSScriptRoot 'Public'
# --- Load Public ---
if (Test-Path $publicFolder) {
    $publicFiles = Get-ChildItem -Path $publicFolder -Filter *.ps1 -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($f in $publicFiles) { . $f.FullName }
    Export-ModuleMember -Function $publicFiles.BaseName -Alias *
}

$ExecutionContext.SessionState.Module.OnRemove = {
}
