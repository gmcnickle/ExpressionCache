#requires -Modules Pester

Describe 'Config merge and splat internals' {

    BeforeAll {
        $here = $PSScriptRoot
        $repoRoot = (Resolve-Path (Join-Path $here '..')).Path
        $psd1Path = Join-Path $repoRoot 'src/ExpressionCache.psd1'
        $support  = Join-Path $here 'support/Common.ps1'

        . $support -ModulePath $psd1Path
        Import-Module $psd1Path -Force

        Ensure-ExpressionCacheInitialized
    }

    Context 'Merge-ObjectDeep' {

        It 'override scalar replaces base scalar' {
            InModuleScope ExpressionCache {
                $result = Merge-ObjectDeep -Base @{ Port = 6379 } -Override @{ Port = 6380 }
                $result.Port | Should -Be 6380
            }
        }

        It 'preserves base keys not present in override' {
            InModuleScope ExpressionCache {
                $result = Merge-ObjectDeep -Base @{ A = 1; B = 2 } -Override @{ B = 99 }
                $result.A | Should -Be 1
                $result.B | Should -Be 99
            }
        }

        It 'adds new keys from override' {
            InModuleScope ExpressionCache {
                $result = Merge-ObjectDeep -Base @{ A = 1 } -Override @{ B = 2 }
                $result.A | Should -Be 1
                $result.B | Should -Be 2
            }
        }

        It 'recursively merges nested hashtables' {
            InModuleScope ExpressionCache {
                $base = @{
                    Config = @{ Port = 6379; Host = 'localhost' }
                    Name   = 'Original'
                }
                $override = @{
                    Config = @{ Port = 6380 }
                }
                $result = Merge-ObjectDeep -Base $base -Override $override
                $result.Config.Port | Should -Be 6380
                $result.Config.Host | Should -Be 'localhost'
                $result.Name | Should -Be 'Original'
            }
        }

        It 'empty hashtable override preserves all base keys' {
            InModuleScope ExpressionCache {
                $result = Merge-ObjectDeep -Base @{ A = 1; B = 2 } -Override @{}
                $result.A | Should -Be 1
                $result.B | Should -Be 2
            }
        }

        It 'override array replaces base array' {
            InModuleScope ExpressionCache {
                $result = Merge-ObjectDeep -Base @(1, 2) -Override @(3, 4, 5)
                $result | Should -Be @(3, 4, 5)
            }
        }

        It 'handles PSCustomObject base with hashtable override' {
            InModuleScope ExpressionCache {
                $base = [pscustomobject]@{ A = 1; B = 2 }
                $override = @{ B = 99; C = 3 }
                $result = Merge-ObjectDeep -Base $base -Override $override
                $result | Should -BeOfType [pscustomobject]
                $result.A | Should -Be 1
                $result.B | Should -Be 99
                $result.C | Should -Be 3
            }
        }

        It 'handles hashtable base with PSCustomObject override' {
            InModuleScope ExpressionCache {
                $base = @{ A = 1; B = 2 }
                $override = [pscustomobject]@{ B = 99 }
                $result = Merge-ObjectDeep -Base $base -Override $override
                $result | Should -BeOfType [hashtable]
                $result.A | Should -Be 1
                $result.B | Should -Be 99
            }
        }

        It 'override scalar replaces base nested hashtable' {
            InModuleScope ExpressionCache {
                $base = @{ X = @{ Nested = 1 } }
                $override = @{ X = 'flat' }
                $result = Merge-ObjectDeep -Base $base -Override $override
                $result.X | Should -Be 'flat'
            }
        }
    }

    Context 'Merge-ExpressionCacheConfig' {

        It 'overrides existing keys in the base config' {
            InModuleScope ExpressionCache {
                $base = [pscustomobject]@{ Database = 2; Port = 6379 }
                $overrides = @{ Database = 15 }
                $result = Merge-ExpressionCacheConfig -Base $base -Overrides $overrides
                $result.Database | Should -Be 15
                $result.Port | Should -Be 6379
            }
        }

        It 'adds new keys not present in the base' {
            InModuleScope ExpressionCache {
                $base = [pscustomobject]@{ Port = 6379 }
                $overrides = @{ CustomSetting = 'hello' }
                $result = Merge-ExpressionCacheConfig -Base $base -Overrides $overrides
                $result.Port | Should -Be 6379
                $result.CustomSetting | Should -Be 'hello'
            }
        }

        It 'empty overrides leaves base unchanged' {
            InModuleScope ExpressionCache {
                $base = [pscustomobject]@{ A = 1; B = 2 }
                $result = Merge-ExpressionCacheConfig -Base $base -Overrides @{}
                $result.A | Should -Be 1
                $result.B | Should -Be 2
            }
        }

        It 'mutates the base object in place and returns it' {
            InModuleScope ExpressionCache {
                $base = [pscustomobject]@{ X = 'old' }
                $result = Merge-ExpressionCacheConfig -Base $base -Overrides @{ X = 'new' }
                $result | Should -Be $base
                $base.X | Should -Be 'new'
            }
        }
    }

    Context 'Merge-ExpressionCacheProviders' {

        It 'merges user overrides into default provider configs' {
            InModuleScope ExpressionCache {
                $defaults = [ordered]@{
                    Redis = @{
                        Name        = 'Redis'
                        GetOrCreate = 'Get-Redis-CachedValue'
                        Initialize  = 'Initialize-Redis-Cache'
                        ClearCache  = 'Clear-Redis-Cache'
                        Config      = @{ Database = 2; Port = 6379; HostAddress = '127.0.0.1' }
                    }
                }
                $overrides = [ordered]@{
                    Redis = @{
                        Name        = 'Redis'
                        GetOrCreate = 'Get-Redis-CachedValue'
                        Initialize  = 'Initialize-Redis-Cache'
                        ClearCache  = 'Clear-Redis-Cache'
                        Config      = @{ Database = 15 }
                    }
                }
                $result = Merge-ExpressionCacheProviders -Defaults $defaults -Overrides $overrides
                $result.Redis.Config.Database    | Should -Be 15
                $result.Redis.Config.Port        | Should -Be 6379
                $result.Redis.Config.HostAddress | Should -Be '127.0.0.1'
            }
        }

        It 'adds a new provider not in defaults' {
            InModuleScope ExpressionCache {
                $defaults = [ordered]@{
                    LocalFileSystemCache = @{
                        Name        = 'LocalFileSystemCache'
                        GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                        Initialize  = 'Initialize-LocalFileSystem-Cache'
                        ClearCache  = 'Clear-LocalFileSystem-Cache'
                        Config      = @{ CacheFolder = 'C:\temp' }
                    }
                }
                $newProvider = [ordered]@{
                    Custom = @{
                        Name        = 'Custom'
                        GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                        Config      = @{ Foo = 'bar' }
                    }
                }
                $result = Merge-ExpressionCacheProviders -Defaults $defaults -Overrides $newProvider
                $result.Keys | Should -Contain 'LocalFileSystemCache'
                $result.Keys | Should -Contain 'Custom'
                $result.Custom.Config.Foo | Should -Be 'bar'
            }
        }

        It '-Replace discards defaults entirely' {
            InModuleScope ExpressionCache {
                $defaults = [ordered]@{
                    LocalFileSystemCache = @{
                        Name        = 'LocalFileSystemCache'
                        GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                        Initialize  = 'Initialize-LocalFileSystem-Cache'
                        ClearCache  = 'Clear-LocalFileSystem-Cache'
                        Config      = @{ CacheFolder = 'C:\temp' }
                    }
                }
                $replacement = [ordered]@{
                    OnlyThis = @{
                        Name        = 'OnlyThis'
                        GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                        Config      = @{ X = 1 }
                    }
                }
                $result = Merge-ExpressionCacheProviders -Defaults $defaults -Overrides $replacement -Replace
                $result.Keys | Should -Not -Contain 'LocalFileSystemCache'
                $result.Keys | Should -Contain 'OnlyThis'
            }
        }

        It 'preserves unmodified defaults when only some providers are overridden' {
            InModuleScope ExpressionCache {
                $defaults = [ordered]@{
                    LFS = @{
                        Name        = 'LFS'
                        GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                        Initialize  = 'Initialize-LocalFileSystem-Cache'
                        ClearCache  = 'Clear-LocalFileSystem-Cache'
                        Config      = @{ CacheFolder = 'C:\original' }
                    }
                    Redis = @{
                        Name        = 'Redis'
                        GetOrCreate = 'Get-Redis-CachedValue'
                        Initialize  = 'Initialize-Redis-Cache'
                        ClearCache  = 'Clear-Redis-Cache'
                        Config      = @{ Database = 2 }
                    }
                }
                $overrides = [ordered]@{
                    Redis = @{
                        Name        = 'Redis'
                        GetOrCreate = 'Get-Redis-CachedValue'
                        Initialize  = 'Initialize-Redis-Cache'
                        ClearCache  = 'Clear-Redis-Cache'
                        Config      = @{ Database = 15 }
                    }
                }
                $result = Merge-ExpressionCacheProviders -Defaults $defaults -Overrides $overrides
                $result.LFS.Config.CacheFolder | Should -Be 'C:\original'
                $result.Redis.Config.Database  | Should -Be 15
            }
        }
    }

    Context 'New-SplatFromConfig' {

        It 'includes only parameters accepted by the target command' {
            InModuleScope ExpressionCache {
                $config = @{
                    ProviderName = 'Redis'
                    HostAddress  = '10.0.0.1'
                    Port         = 6380
                    NotAParam    = 'should-be-excluded'
                }
                $splat = New-SplatFromConfig -CommandName 'New-RedisClient' -Config $config
                $splat.Keys | Should -Contain 'HostAddress'
                $splat.Keys | Should -Contain 'Port'
                $splat.Keys | Should -Not -Contain 'NotAParam'
                $splat.Keys | Should -Not -Contain 'ProviderName'
            }
        }

        It 'excludes common parameters like Verbose and ErrorAction' {
            InModuleScope ExpressionCache {
                $config = @{
                    HostAddress = '127.0.0.1'
                    Verbose     = $true
                    ErrorAction = 'Stop'
                }
                $splat = New-SplatFromConfig -CommandName 'New-RedisClient' -Config $config
                $splat.Keys | Should -Contain 'HostAddress'
                $splat.Keys | Should -Not -Contain 'Verbose'
                $splat.Keys | Should -Not -Contain 'ErrorAction'
            }
        }
    }

    Context 'New-CallableSplat' {

        It 'merges Config and Arguments, preferring Config by default' {
            InModuleScope ExpressionCache {
                function script:Test-SplatTarget { [CmdletBinding()] param([string]$Name, [int]$Port, [string]$Host2, [switch]$Force) }
                $null = $script:__ParamCache.TryRemove('Test-SplatTarget', [ref]$null)
                $splat = New-CallableSplat -CommandName 'Test-SplatTarget' `
                    -Config @{ Name = 'from-config'; Port = 1234 } `
                    -Arguments @{ Name = 'from-args'; Host2 = 'extra' }
                $splat.Name  | Should -Be 'from-config'
                $splat.Port  | Should -Be 1234
                $splat.Host2 | Should -Be 'extra'
            }
        }

        It '-PreferArgs makes Arguments override Config' {
            InModuleScope ExpressionCache {
                function script:Test-SplatTarget { [CmdletBinding()] param([string]$Name, [int]$Port, [string]$Host2, [switch]$Force) }
                $null = $script:__ParamCache.TryRemove('Test-SplatTarget', [ref]$null)
                $splat = New-CallableSplat -CommandName 'Test-SplatTarget' `
                    -Config @{ Name = 'from-config'; Port = 1234 } `
                    -Arguments @{ Name = 'from-args' } `
                    -PreferArgs
                $splat.Name | Should -Be 'from-args'
                $splat.Port | Should -Be 1234
            }
        }

        It 'excludes null and empty string values by default' {
            InModuleScope ExpressionCache {
                function script:Test-SplatTarget { [CmdletBinding()] param([string]$Name, [int]$Port, [string]$Host2, [switch]$Force) }
                $null = $script:__ParamCache.TryRemove('Test-SplatTarget', [ref]$null)
                $splat = New-CallableSplat -CommandName 'Test-SplatTarget' `
                    -Config @{ Name = $null; Port = 8080; Host2 = '' }
                $splat.Keys | Should -Not -Contain 'Name'
                $splat.Keys | Should -Not -Contain 'Host2'
                $splat.Port | Should -Be 8080
            }
        }

        It '-IncludeNulls passes null values through' {
            InModuleScope ExpressionCache {
                function script:Test-SplatTarget { [CmdletBinding()] param([string]$Name, [int]$Port, [string]$Host2, [switch]$Force) }
                $null = $script:__ParamCache.TryRemove('Test-SplatTarget', [ref]$null)
                $splat = New-CallableSplat -CommandName 'Test-SplatTarget' `
                    -Config @{ Name = $null; Port = 8080 } `
                    -IncludeNulls
                $splat.Keys | Should -Contain 'Name'
                $splat.Name | Should -Be $null
                $splat.Port | Should -Be 8080
            }
        }

        It 'includes switch parameters only when truthy' {
            InModuleScope ExpressionCache {
                function script:Test-SplatTarget { [CmdletBinding()] param([string]$Name, [int]$Port, [string]$Host2, [switch]$Force) }
                $null = $script:__ParamCache.TryRemove('Test-SplatTarget', [ref]$null)
                $splatOn = New-CallableSplat -CommandName 'Test-SplatTarget' `
                    -Config @{ Force = $true; Name = 'x' }
                $splatOn.Keys | Should -Contain 'Force'
                $splatOn.Force | Should -Be $true

                $splatOff = New-CallableSplat -CommandName 'Test-SplatTarget' `
                    -Config @{ Force = $false; Name = 'x' }
                $splatOff.Keys | Should -Not -Contain 'Force'
            }
        }

        It 'ignores parameters not accepted by the target command' {
            InModuleScope ExpressionCache {
                function script:Test-SplatTarget { [CmdletBinding()] param([string]$Name, [int]$Port, [string]$Host2, [switch]$Force) }
                $null = $script:__ParamCache.TryRemove('Test-SplatTarget', [ref]$null)
                $splat = New-CallableSplat -CommandName 'Test-SplatTarget' `
                    -Config @{ Name = 'ok'; Bogus = 'nope' }
                $splat.Keys | Should -Contain 'Name'
                $splat.Keys | Should -Not -Contain 'Bogus'
            }
        }
    }

    Context 'Initialize-ExpressionCache config merge (end-to-end)' {

        AfterEach {
            # Restore clean state
            try { Initialize-ExpressionCache -AppName 'ExpressionCache-Pester' | Out-Null } catch {}
        }

        It 'user config overrides merge with defaults for Redis' {
            Initialize-ExpressionCache -AppName 'MergeTest' -Providers ([ordered]@{
                Redis = @{ Name = 'Redis'; Config = @{ Database = 15; Prefix = 'test:custom:' } }
            }) | Out-Null

            $p = Get-ExpressionCacheProvider -ProviderName 'Redis'
            $p.Config.Database    | Should -Be 15
            $p.Config.Prefix      | Should -Be 'test:custom:'
            $p.Config.HostAddress | Should -Be '127.0.0.1'
            $p.Config.Port        | Should -Be 6379
        }

        It 'user config overrides merge with defaults for LocalFileSystemCache' {
            $customFolder = Join-Path ([System.IO.Path]::GetTempPath()) 'MergeTestCache'
            Initialize-ExpressionCache -AppName 'MergeTest' -Providers ([ordered]@{
                LocalFileSystemCache = @{
                    Name   = 'LocalFileSystemCache'
                    Config = @{ CacheFolder = $customFolder; JsonDepth = 20 }
                }
            }) | Out-Null

            $p = Get-ExpressionCacheProvider -ProviderName 'LocalFileSystemCache'
            $p.Config.CacheFolder | Should -Be $customFolder
            $p.Config.JsonDepth   | Should -Be 20
            $p.Config.CacheVersion | Should -Be 1
        }

        It '-ReplaceProviders discards all defaults' {
            Initialize-ExpressionCache -AppName 'ReplaceTest' -ReplaceProviders -Providers ([ordered]@{
                OnlyMe = @{
                    Name        = 'OnlyMe'
                    GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                    Config      = @{ CacheFolder = ([System.IO.Path]::GetTempPath()) }
                }
            }) | Out-Null

            $all = Get-ExpressionCacheProvider
            $all.Keys | Should -Contain 'OnlyMe'
            $all.Keys | Should -Not -Contain 'LocalFileSystemCache'
            $all.Keys | Should -Not -Contain 'Redis'
        }

        It 'no user providers uses all defaults' {
            Initialize-ExpressionCache -AppName 'DefaultsOnly' | Out-Null
            $all = Get-ExpressionCacheProvider
            $all.Keys | Should -Contain 'LocalFileSystemCache'
            $all.Keys | Should -Contain 'Redis'
        }

        It 'default Prefix includes AppName' {
            Initialize-ExpressionCache -AppName 'PrefixCheck' | Out-Null
            $p = Get-ExpressionCacheProvider -ProviderName 'Redis'
            $p.Config.Prefix | Should -Match 'PrefixCheck'
        }
    }
}
