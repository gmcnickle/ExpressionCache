#requires -Modules Pester

Describe 'Set-ProviderStateValues' {

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

    Context 'Atomic mode (default)' {

        It 'writes multiple keys under a single lock' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'AtomicState'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'AtomicState'

                Set-ProviderStateValues -Provider $p -Patch @{ alpha = 'a'; beta = 'b' }

                (Get-ProviderStateValue -Provider $p -Key 'alpha') | Should -Be 'a'
                (Get-ProviderStateValue -Provider $p -Key 'beta')  | Should -Be 'b'
            }
        }

        It 'bumps StateRevision metadata' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'RevBump'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'RevBump'

                Set-ProviderStateValues -Provider $p -Patch @{ x = 1 }
                $rev1 = Get-ProviderStateValue -Provider $p -Key 'StateRevision'

                Set-ProviderStateValues -Provider $p -Patch @{ y = 2 }
                $rev2 = Get-ProviderStateValue -Provider $p -Key 'StateRevision'

                $rev2 | Should -BeGreaterThan $rev1
            }
        }
    }

    Context 'NonAtomic mode' {

        It 'writes keys without holding the provider lock' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'NonAtomicState'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'NonAtomicState'

                Set-ProviderStateValues -Provider $p -Patch @{ one = 1; two = 2 } -NonAtomic

                (Get-ProviderStateValue -Provider $p -Key 'one') | Should -Be 1
                (Get-ProviderStateValue -Provider $p -Key 'two') | Should -Be 2
            }
        }

        It 'bumps StateRevision in NonAtomic mode too' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'NonAtomicRev'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'NonAtomicRev'

                Set-ProviderStateValues -Provider $p -Patch @{ a = 1 } -NonAtomic
                $rev = Get-ProviderStateValue -Provider $p -Key 'StateRevision'
                $rev | Should -BeGreaterOrEqual 1
            }
        }
    }
}
