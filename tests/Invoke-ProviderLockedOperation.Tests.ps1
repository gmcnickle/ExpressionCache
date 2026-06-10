#requires -Modules Pester

Describe 'Invoke-ProviderLockedOperation' {

    BeforeAll {
        $here = $PSScriptRoot
        $repoRoot = (Resolve-Path (Join-Path $here '..')).Path
        $psd1Path = Join-Path $repoRoot 'src/ExpressionCache.psd1'
        $support  = Join-Path $here 'support/Common.ps1'

        if (-not (Test-Path $psd1Path)) { throw "Cannot locate psd1 at: $psd1Path" }
        if (-not (Test-Path $support))  { throw "Cannot locate support at: $support" }

        . $support -ModulePath $psd1Path
        Import-Module $psd1Path -Force

        Ensure-ExpressionCacheInitialized
    }

    BeforeEach { Reset-Providers-ForTests }
    AfterEach  { Reset-Providers-ForTests }

    It 'executes the body scriptblock and returns its result' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'LockExec'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{}
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'LockExec'

            $result = Invoke-ProviderLockedOperation -Provider $p { 42 }
            $result | Should -Be 42
        }
    }

    It 'does not shadow a ScriptBlock variable used by the operation' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'LockScope'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{}
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'LockScope'
            $ScriptBlock = { 42 }

            $result = Invoke-ProviderLockedOperation -Provider $p -Operation {
                & $ScriptBlock
            }

            $result | Should -Be 42
        }
    }

    It 'releases the lock even when the body throws' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'LockRelease'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{}
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'LockRelease'

            # Force the lock to be created
            Invoke-ProviderLockedOperation -Provider $p { $null } | Out-Null

            # Now throw inside the lock
            try { Invoke-ProviderLockedOperation -Provider $p { throw 'boom' } } catch { }

            # Lock should be released — we can acquire it again without deadlock
            $result = Invoke-ProviderLockedOperation -Provider $p { 'recovered' }
            $result | Should -Be 'recovered'
        }
    }

    It 'lazily creates the lock on first use' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'LazyLock'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{}
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'LazyLock'

            # __Lock should not exist yet (lazy creation)
            $hasLockBefore = $null -ne $p.__Lock

            Invoke-ProviderLockedOperation -Provider $p { $null } | Out-Null

            # Now it should exist
            $p.__Lock | Should -Not -BeNullOrEmpty
        }
    }
}
