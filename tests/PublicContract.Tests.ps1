#requires -Modules Pester

Describe 'ExpressionCache public contract' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $modulePath = Join-Path $repoRoot 'src/ExpressionCache.psd1'
        Import-Module $modulePath -Force
    }

    It 'exports only the supported public functions' {
        $expected = @(
            'Add-ExpressionCacheProvider'
            'Clear-ExpressionCache'
            'Get-ExpressionCache'
            'Get-ExpressionCacheProvider'
            'Get-ProviderConfig'
            'Get-ProviderStateValue'
            'Initialize-ExpressionCache'
            'Invoke-ProviderLockedOperation'
            'New-ExpressionCacheKey'
            'Remove-ExpressionCacheProvider'
            'Set-ProviderConfig'
            'Set-ProviderStateValue'
            'Set-ProviderStateValues'
        )

        $actual = Get-Command -Module ExpressionCache -CommandType Function |
            Select-Object -ExpandProperty Name |
            Sort-Object

        $actual | Should -Be ($expected | Sort-Object)
    }

    It 'does not expose the removed NoFallback parameter' {
        (Get-Command Get-ExpressionCacheProvider).Parameters.Keys |
            Should -Not -Contain 'NoFallback'
    }

    It 'uses ProviderName as the canonical parameter with a Name alias' {
        foreach ($commandName in 'Get-ExpressionCache', 'Get-ExpressionCacheProvider', 'Clear-ExpressionCache', 'Remove-ExpressionCacheProvider') {
            $parameter = (Get-Command $commandName).Parameters['ProviderName']
            $parameter | Should -Not -BeNullOrEmpty
            $parameter.Aliases | Should -Contain 'Name'
        }
    }

    It 'documents Providers as a dictionary parameter' {
        (Get-Command Initialize-ExpressionCache).Parameters['Providers'].ParameterType |
            Should -Be ([System.Collections.IDictionary])
    }

    It 'keeps the automatic key algorithm stable for the 1.x contract' {
        $scriptBlock = [scriptblock]::Create('param($x, $y) $x + $y')

        New-ExpressionCacheKey -ScriptBlock $scriptBlock -Arguments 1, 2 |
            Should -Be '39d101a3c98cb9d67e67872421570bf3a879c487ef9798c7a6282d7c8bc362d1'
    }
}

Describe 'Provider descriptor contract' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $modulePath = Join-Path $repoRoot 'src/ExpressionCache.psd1'
        Import-Module $modulePath -Force
    }

    It 'rejects scriptblock hooks' {
        InModuleScope ExpressionCache {
            {
                Test-ExpressionCacheProviderSpec -Spec @{
                    Name        = 'ScriptHook'
                    GetOrCreate = { param($Key, $ScriptBlock) }
                    Config      = @{}
                }
            } | Should -Throw '*command-name string*'
        }
    }

    It 'requires GetOrCreate commands to accept Key and ScriptBlock' {
        InModuleScope ExpressionCache {
            function Get-IncompleteProviderValue {
                param([string]$Key)
            }

            {
                Test-ExpressionCacheProviderSpec -Spec @{
                    Name        = 'Incomplete'
                    GetOrCreate = 'Get-IncompleteProviderValue'
                    Config      = @{}
                }
            } | Should -Throw "*must declare a 'ScriptBlock' parameter*"
        }
    }

    It 'accepts the canonical lifecycle hook names' {
        InModuleScope ExpressionCache {
            function Get-ContractValue {
                param([string]$Key, [scriptblock]$ScriptBlock)
            }
            function Initialize-ContractProvider {}
            function Clear-ContractProvider {}
            function Close-ContractProvider {}

            $result = Test-ExpressionCacheProviderSpec -Spec @{
                Name        = 'Contract'
                GetOrCreate = 'Get-ContractValue'
                Initialize  = 'Initialize-ContractProvider'
                ClearCache  = 'Clear-ContractProvider'
                Teardown    = 'Close-ContractProvider'
                Config      = @{}
            }

            $result.ClearCache | Should -Be 'Clear-ContractProvider'
            $result.Teardown | Should -Be 'Close-ContractProvider'
        }
    }
}
