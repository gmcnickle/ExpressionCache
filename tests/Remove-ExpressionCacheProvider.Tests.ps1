#requires -Modules Pester

Describe 'Remove-ExpressionCacheProvider' {

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

    Context 'Basic removal' {

        It 'removes a registered provider by name' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'Removable'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null

                $before = Get-ExpressionCacheProvider -ProviderName 'Removable'
                $before | Should -Not -BeNullOrEmpty

                Remove-ExpressionCacheProvider -ProviderName 'Removable' -Confirm:$false

                $after = Get-ExpressionCacheProvider -ProviderName 'Removable' -NoFallback
                $after | Should -BeNullOrEmpty
            }
        }

        It 'is case-insensitive on provider name' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'CaseTest'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                Remove-ExpressionCacheProvider -ProviderName 'CASETEST' -Confirm:$false

                $result = Get-ExpressionCacheProvider -ProviderName 'CaseTest' -NoFallback
                $result | Should -BeNullOrEmpty
            }
        }

        It 'does not throw when provider does not exist' {
            # Non-existent provider emits a warning but should not throw
            { Remove-ExpressionCacheProvider -ProviderName 'DoesNotExist' -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context '-WhatIf and -PassThru' {

        It 'does not remove when -WhatIf is used' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'WhatIfTest'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                Remove-ExpressionCacheProvider -ProviderName 'WhatIfTest' -WhatIf

                $result = Get-ExpressionCacheProvider -ProviderName 'WhatIfTest'
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It 'returns the removed spec when -PassThru is used' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'PassThruTest'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{ A = 1 }
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null

                $removed = Remove-ExpressionCacheProvider -ProviderName 'PassThruTest' -PassThru -Confirm:$false
                $removed | Should -Not -BeNullOrEmpty
                $removed.Name | Should -Be 'PassThruTest'
            }
        }

        It 'returns nothing without -PassThru' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'SilentTest'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null

                $result = Remove-ExpressionCacheProvider -ProviderName 'SilentTest' -Confirm:$false
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Pipeline input' {

        It 'accepts provider names from the pipeline' {
            InModuleScope ExpressionCache {
                foreach ($n in @('PipeA', 'PipeB')) {
                    Add-ExpressionCacheProvider -Provider @{
                        Name        = $n
                        GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                        Config      = [pscustomobject]@{}
                    } | Out-Null
                }

                'PipeA', 'PipeB' | Remove-ExpressionCacheProvider -Confirm:$false

                (Get-ExpressionCacheProvider -ProviderName 'PipeA' -NoFallback) | Should -BeNullOrEmpty
                (Get-ExpressionCacheProvider -ProviderName 'PipeB' -NoFallback) | Should -BeNullOrEmpty
            }
        }
    }
}
