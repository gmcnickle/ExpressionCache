# Pester v5+
# Tests the real behavior of Add-ExpressionCacheProvider (no README assumptions).
# Relies on the module's internal helpers: Test-ExpressionCacheProviderSpec,
# Merge-ExpressionCacheConfig, Build-SplatFromConfig, Assert-MandatoryParamsPresent.

#requires -Modules Pester


Describe 'Add-ExpressionCacheProvider' {

    BeforeAll {
        $here = $PSScriptRoot                                   
        $repoRoot = (Resolve-Path (Join-Path $here '..')).Path  
        $psd1Path = Join-Path $repoRoot 'src/ExpressionCache.psd1'
        $support = Join-Path $here 'support/common.ps1'         

        if (-not (Test-Path $psd1Path)) { throw "Cannot locate psd1 at: $psd1Path" }
        if (-not (Test-Path $support)) { throw "Cannot locate support at: $support" }

        . $support -ModulePath $psd1Path
        Import-Module $psd1Path -Force

        Ensure-ExpressionCacheInitialized
    }


    BeforeEach { 
        Reset-Providers-ForTests 
        $script:EC_InitCalls = 0
        $script:EC_LastInitArgs = $null
    }
    AfterEach { Reset-Providers-ForTests }

    It 'normalizes the spec via Test-ExpressionCacheProviderSpec and registers it' {
        # Use Key to ensure normalization happens (Key→Name).
        $spec = @{
            Name        = 'LocalFileSystemCache'
            GetOrCreate = 'Get-LocalFileSystem-CachedValue'
            Config      = [pscustomobject]@{ Prefix = 'X' }
        }

        $ret = Add-ExpressionCacheProvider -Provider $spec

        # Returns the normalized spec and registers it
        $ret | Should -Not -BeNullOrEmpty
        $ret.Name | Should -Be 'LocalFileSystemCache'

        $all = Get-ExpressionCacheProvider
        $all.Name | Should -Contain 'LocalFileSystemCache'
    }

    It 'performs a one-time merge of InitializeArgs into Config (overrides win) and removes InitializeArgs' {
        $spec = @{
            Name           = 'Redis'
            GetOrCreate    = 'Get-Redis-CachedValue'
            Config         = [pscustomobject]@{
                Prefix   = 'ExpressionCache:v1:App'
                Host     = 'will-be-overwritten'
                Database = 0
            }
            InitializeArgs = @{
                Host     = '127.0.0.1'
                Port     = 6379
                Password = 'pw'
            }
        }

        $ret = Add-ExpressionCacheProvider -Provider $spec

        # InitializeArgs removed from returned spec
        ($ret.PSObject.Properties.Name -contains 'InitializeArgs') | Should -BeFalse

        # Config contains merged + overridden values
        $ret.Config.Host     | Should -Be '127.0.0.1'
        $ret.Config.Port     | Should -Be 6379
        $ret.Config.Password | Should -Be 'pw'
        $ret.Config.Prefix   | Should -Be 'ExpressionCache:v1:App'
        $ret.Config.Database | Should -Be 0
    }

    It 'rejects duplicate provider names (case-insensitive), even under -WhatIf' {
        $p1 = @{
            Name        = 'DupName'
            GetOrCreate = 'Get-LocalFileSystem-CachedValue'
            Config      = [pscustomobject]@{}
        }
        $p2 = @{
            Name        = 'DUPNAME'
            GetOrCreate = 'Get-LocalFileSystem-CachedValue'
            Config      = [pscustomobject]@{}
        }

        Add-ExpressionCacheProvider -Provider $p1 | Out-Null
        $result = { Add-ExpressionCacheProvider -Provider $p2 -WhatIf } | Should -Throw -PassThru
        $result.Exception.Message | Should -Match "A provider named '$($p2.Name)' is already registered."
    }

    It 'does not register or initialize when -WhatIf is used, but still returns the normalized spec' {
        InModuleScope ExpressionCache {
            # fresh fakes for THIS block
            Set-Variable -Name EC_InitCalls -Scope Script -Value 0

            function Initialize-EC-Fake {
                param([string]$HostAddr, [int]$Port)
                $script:EC_InitCalls++
            }

            function Get-OrCreate-EC-Fake {
                param([string]$Key, [scriptblock]$ScriptBlock, [object[]]$Arguments, [psobject]$Config)
                & $ScriptBlock @Arguments
            }

            $spec = @{
                Name        = 'NoOp'
                Initialize  = 'Initialize-EC-Fake'
                GetOrCreate = 'Get-OrCreate-EC-Fake'
                Config      = [pscustomobject]@{ Host = 'localhost'; Port = 6379 }
            }

            $ret = Add-ExpressionCacheProvider -Provider $spec -WhatIf

            $ret.Name | Should -Be 'NoOp'
            $script:EC_InitCalls | Should -Be 0
            $script:RegisteredStorageProviders.Count | Should -Be 0
        }
    }


    It 'eagerly initializes when Initialize is provided, using Build-SplatFromConfig + mandatory enforcement' {

        InModuleScope ExpressionCache {
            Set-Variable -Name EC_InitCalls -Scope Script -Value 0

            function Initialize-EC-Fake {
                param([string]$HostAddr, [int]$Port)
                $script:EC_InitCalls++
            }

            $spec = @{
                Name        = 'InitTest'
                Initialize  = 'Initialize-EC-Fake'
                GetOrCreate = 'Get-LocalFileSystem-CachedValue'
                Config      = [pscustomobject]@{
                    HostAddr      = '10.0.0.5'
                    Port          = 6380
                    OptionalThing = 'foo'
                    Initialized   = $false
                }
            }

            Add-ExpressionCacheProvider -Provider $spec

            # Initialize called exactly once with params from Config
            $script:EC_InitCalls | Should -Be 1
            $spec.Config.Initialized | Should -Be $true
            $spec.Config.HostAddr | Should -Be '10.0.0.5'
            $spec.Config.Port | Should -Be 6380
            $spec.Config.OptionalThing | Should -Be 'foo'
        }
    }

    It 'throws if Initialize requires a param that is not present in Config' {
        function Initialize-EC-RequiresToken {
            param([Parameter(Mandatory)] [string]$Token)
        }

        $spec = @{
            Name        = 'BadInit'
            Initialize  = 'Initialize-EC-RequiresToken'
            GetOrCreate = 'Get-LocalFileSystem-CachedValue'
            Config      = [pscustomobject]@{
                # Note: no 'Token' here, should fail Assert-MandatoryParamsPresent
            }
        }

        { Add-ExpressionCacheProvider -Provider $spec } | Should -Throw
    }

    It 'returns the registered spec object (PSCustomObject) with expected members' {
        $spec = @{
            Name        = 'ReturnShape'
            GetOrCreate = 'Get-LocalFileSystem-CachedValue'
            Config      = [pscustomobject]@{ A = 1 }
        }

        $ret = Add-ExpressionCacheProvider -Provider $spec

        $ret | Should -BeOfType 'System.Management.Automation.PSCustomObject'
        $ret.PSObject.Properties.Name | Should -Contain 'Name'
        $ret.PSObject.Properties.Name | Should -Contain 'Config'
        $ret.PSObject.Properties.Name | Should -Contain 'GetOrCreate'
        ($ret.PSObject.Properties.Name -contains 'InitializeArgs') | Should -BeFalse
    }
}
