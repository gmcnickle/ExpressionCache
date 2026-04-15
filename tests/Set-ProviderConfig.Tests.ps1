#requires -Modules Pester

Describe 'Set-ProviderConfig' {

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

    It 'replaces provider config atomically' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'CfgTest'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{ Foo = 'original' }
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'CfgTest'

            Set-ProviderConfig -Provider $p -NewConfig @{ Foo = 'updated'; Bar = 42 }

            $p.Config.Foo | Should -Be 'updated'
            $p.Config.Bar | Should -Be 42
        }
    }

    It 'increments ConfigRevision on each update' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'RevTest'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{ X = 1 }
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'RevTest'

            Set-ProviderConfig -Provider $p -NewConfig @{ X = 2 }
            $rev1 = $p.ConfigRevision

            Set-ProviderConfig -Provider $p -NewConfig @{ X = 3 }
            $rev2 = $p.ConfigRevision

            $rev2 | Should -BeGreaterThan $rev1
        }
    }

    It 'sets ConfigLastChangedUtc timestamp' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'TsTest'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{ Y = 0 }
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'TsTest'

            $before = [DateTime]::UtcNow
            Set-ProviderConfig -Provider $p -NewConfig @{ Y = 1 }

            $p.ConfigLastChangedUtc | Should -BeOfType [DateTime]
            $p.ConfigLastChangedUtc | Should -BeGreaterOrEqual $before
        }
    }

    It 'first update starts ConfigRevision at 1' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'FirstRevTest'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{ Z = 0 }
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'FirstRevTest'

            Set-ProviderConfig -Provider $p -NewConfig @{ Z = 1 }
            $p.ConfigRevision | Should -Be 1
        }
    }
}
