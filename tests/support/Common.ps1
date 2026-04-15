param([string]$ModulePath)

# Import module once for the test runspace
if (-not (Get-Module ExpressionCache)) {
    Import-Module $ModulePath -ErrorAction Stop
}

function Ensure-ExpressionCacheInitialized {
    $providers = $null
    try {
        # Any harmless call that assumes init; adjust if needed
        $providers = Get-ExpressionCacheProvider
    } catch {
    }
    finally {
        if (-not $providers) {
            Initialize-ExpressionCache -AppName 'ExpressionCache-Pester' | Out-Null
        }
    }
}

function Reset-Providers-ForTests {
    try {
        $all = Get-ExpressionCacheProvider
        foreach ($p in $all) {
            Remove-ExpressionCacheProvider -ProviderName $p.Name -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        Initialize-ExpressionCache -AppName 'ExpressionCache-Pester' | Out-Null
    }
}

# --- AUDIT LOG ---
# 2026-04-15: Added Invoke-ParallelRunspace for PS 5.1 concurrency tests (see audit log for details)

function Invoke-ParallelRunspace {
    <#
    .SYNOPSIS
        Runs a scriptblock in parallel using runspace pools (PS 5.1+).
    .PARAMETER InputObject
        The collection to process in parallel.
    .PARAMETER ScriptBlock
        The scriptblock to invoke. Receives $_ as input.
    .PARAMETER ThrottleLimit
        Maximum number of concurrent runspaces.
    .PARAMETER ArgumentList
        Additional arguments to pass to the scriptblock.
    .OUTPUTS
        Array of results, in input order.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        [object[]]$InputObject,
        [Parameter(Mandatory, Position=1)]
        [scriptblock]$ScriptBlock,
        [int]$ThrottleLimit = 8,
        [object[]]$ArgumentList,
        [hashtable]$Variables
    )

    $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if ($Variables) {
        foreach ($kv in $Variables.GetEnumerator()) {
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry($kv.Key, $kv.Value, $null)
            $initialState.Variables.Add($entry)
        }
    }

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $initialState, [System.Management.Automation.Host.PSHost]$Host)
    $runspacePool.Open()
    $runspaces = @()

    # Convert scriptblock to string so it can be re-created in each runspace
    # (scriptblock objects cannot cross runspace boundaries in PS 5.1)
    $scriptText = $ScriptBlock.ToString()

    for ($i = 0; $i -lt $InputObject.Count; $i++) {
        $currentItem = $InputObject[$i]
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool
        $null = $ps.AddScript($scriptText).AddArgument($currentItem)
        if ($ArgumentList) {
            foreach ($arg in $ArgumentList) {
                $null = $ps.AddArgument($arg)
            }
        }
        $runspaces += [PSCustomObject]@{
            Index = $i
            PowerShell = $ps
            AsyncResult = $ps.BeginInvoke()
        }
    }

    $results = @(,0 * $InputObject.Count)
    foreach ($r in $runspaces) {
        try {
            $output = $r.PowerShell.EndInvoke($r.AsyncResult)
            if ($r.PowerShell.Streams.Error.Count -gt 0) {
                throw $r.PowerShell.Streams.Error[0].Exception
            }
            $results[$r.Index] = $output
        } finally {
            $r.PowerShell.Dispose()
        }
    }
    $runspacePool.Close()
    $runspacePool.Dispose()
    return $results
}
