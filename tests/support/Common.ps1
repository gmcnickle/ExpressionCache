param([string]$ModulePath)

# Import module once for the test runspace
if (-not (Get-Module ExpressionCache)) {
    Import-Module $ModulePath -ErrorAction Stop
}

function Ensure-ExpressionCacheInitialized {
    try {
        # Any harmless call that assumes init; adjust if needed
        [void](Get-ExpressionCacheProvider)
    } catch {
        Initialize-ExpressionCache -AppName 'ExpressionCache-Pester' | Out-Null
    }
}

function Reset-Providers-ForTests {
    try {
        $all = Get-ExpressionCacheProvider
        foreach ($p in $all) {
            Remove-ExpressionCacheProvider -Name $p.Name -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        Initialize-ExpressionCache -AppName 'ExpressionCache-Pester' | Out-Null
    }
}
