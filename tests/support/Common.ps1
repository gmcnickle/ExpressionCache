param([string]$ModulePath)

# Import module once for the test runspace
if (-not (Get-Module ExpressionCache)) {
    Import-Module $ModulePath -ErrorAction Stop
}

function script:Ensure-ExpressionCacheInitialized {
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

function script:Reset-Providers-ForTests {
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

function script:Invoke-ParallelRunspace {
    <#
    .SYNOPSIS
        Runs a scriptblock in parallel using runspace pools (PS 5.1+).
    .PARAMETER InputObject
        The collection to process in parallel.
    .PARAMETER ScriptBlock
        The scriptblock to invoke. Receives the current item as param($i).
    .PARAMETER ThrottleLimit
        Maximum number of concurrent runspaces.
    .PARAMETER ArgumentList
        Additional arguments to pass to the scriptblock.
    .PARAMETER Variables
        Hashtable of variable names/values to inject into each runspace.
    .OUTPUTS
        Array of results, in input order (scalars unwrapped from PSDataCollection).
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

    try {
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

        $results = New-Object object[] $InputObject.Count
        foreach ($r in $runspaces) {
            $output = $r.PowerShell.EndInvoke($r.AsyncResult)
            if ($r.PowerShell.Streams.Error.Count -gt 0) {
                throw $r.PowerShell.Streams.Error[0].Exception
            }
            # Unwrap PSDataCollection to scalar value (matches ForEach-Object -Parallel behavior)
            if ($output.Count -eq 1) {
                $results[$r.Index] = $output[0]
            } elseif ($output.Count -gt 1) {
                $results[$r.Index] = @($output)
            }
        }
        return ,$results
    } finally {
        foreach ($r in $runspaces) {
            try { $r.PowerShell.Dispose() } catch {}
        }
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
}
