#requires -Modules Pester

Describe 'Get-ExpressionCacheProvider' {

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

    It 'returns a specific provider by name' {
        InModuleScope ExpressionCache {
            $spec = @{
                Name        = 'GetByName'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{}
            }

            Add-ExpressionCacheProvider -Provider $spec | Out-Null
            $result = Get-ExpressionCacheProvider -ProviderName 'GetByName'

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be 'GetByName'
        }
    }

    It 'returns all providers when no name is given' {
        InModuleScope ExpressionCache {
            foreach ($n in @('ListA', 'ListB')) {
                Add-ExpressionCacheProvider -Provider @{
                    Name        = $n
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                } | Out-Null
            }

            $all = Get-ExpressionCacheProvider
            $all.Count | Should -BeGreaterOrEqual 2
        }
    }

    It 'returns $null with -NoFallback when provider does not exist' {
        $result = Get-ExpressionCacheProvider -ProviderName 'NeverRegistered' -NoFallback
        $result | Should -BeNullOrEmpty
    }

    It 'falls back to all providers when name not found and -NoFallback is not set' {
        InModuleScope ExpressionCache {
            Add-ExpressionCacheProvider -Provider @{
                Name        = 'FallbackTest'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{}
            } | Out-Null

            # Ask for a non-existent name without -NoFallback
            $result = Get-ExpressionCacheProvider -ProviderName 'DoesNotExist'
            # Should get the full provider collection as fallback
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
