#requires -Modules Pester

Describe 'Provider State and Config helpers' {

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

    Context 'Get-ProviderConfig' {

        It 'returns a snapshot (copy) of the config by default' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'CfgSnap'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{ Key = 'original' }
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'CfgSnap'

                $snap = Get-ProviderConfig -Provider $p
                $snap.Key | Should -Be 'original'

                # Mutating the snapshot should NOT affect the provider config
                $snap.Key = 'mutated'
                $p.Config.Key | Should -Be 'original'
            }
        }

        It 'returns the raw reference when -Raw is used' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'CfgRaw'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{ Key = 'original' }
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'CfgRaw'

                $raw = Get-ProviderConfig -Provider $p -Raw
                $raw.Key | Should -Be 'original'
            }
        }
    }

    Context 'Get-ProviderStateValue' {

        It 'returns the stored value for a key' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'StateGet'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'StateGet'

                Set-ProviderStateValue -Provider $p -Key 'hello' -Value 'world'
                $v = Get-ProviderStateValue -Provider $p -Key 'hello'
                $v | Should -Be 'world'
            }
        }

        It 'returns $null for a missing key (default)' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'StateMiss'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'StateMiss'

                # Ensure state is initialized
                Set-ProviderStateValue -Provider $p -Key 'setup' -Value 1

                $v = Get-ProviderStateValue -Provider $p -Key 'nonexistent'
                $v | Should -BeNullOrEmpty
            }
        }

        It 'returns the -Default value for a missing key' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'StateDef'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'StateDef'

                # Ensure state is initialized
                Set-ProviderStateValue -Provider $p -Key 'setup' -Value 1

                $v = Get-ProviderStateValue -Provider $p -Key 'missing' -Default 'fallback'
                $v | Should -Be 'fallback'
            }
        }
    }

    Context 'Set-ProviderStateValue' {

        It 'creates new state keys' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'StateSet'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'StateSet'

                Set-ProviderStateValue -Provider $p -Key 'count' -Value 5
                (Get-ProviderStateValue -Provider $p -Key 'count') | Should -Be 5
            }
        }

        It 'overwrites existing state keys' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'StateOverwrite'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'StateOverwrite'

                Set-ProviderStateValue -Provider $p -Key 'val' -Value 'first'
                Set-ProviderStateValue -Provider $p -Key 'val' -Value 'second'

                (Get-ProviderStateValue -Provider $p -Key 'val') | Should -Be 'second'
            }
        }

        It 'lazily creates the State dictionary if missing' {
            InModuleScope ExpressionCache {
                $spec = @{
                    Name        = 'LazyState'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = [pscustomobject]@{}
                }

                Add-ExpressionCacheProvider -Provider $spec | Out-Null
                $p = Get-ExpressionCacheProvider -ProviderName 'LazyState'

                # State may not exist yet
                Set-ProviderStateValue -Provider $p -Key 'auto' -Value 'created'
                $p.State | Should -Not -BeNullOrEmpty
                (Get-ProviderStateValue -Provider $p -Key 'auto') | Should -Be 'created'
            }
        }
    }
}
