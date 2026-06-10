#requires -Modules Pester

Describe 'Redis concurrency controls' {

    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $psd1Path = Join-Path $repoRoot 'src/ExpressionCache.psd1'
        Import-Module $psd1Path -Force
    }

    BeforeEach {
        InModuleScope ExpressionCache {
            Initialize-ExpressionCache -AppName 'RedisConcurrencyTests' | Out-Null
        }
    }

    It 'rechecks the cache after acquiring the distributed key lock' {
        InModuleScope ExpressionCache {
            $script:getCalls = 0
            $script:executions = 0
            $cachedPayload = Write-CacheValue -Value 42

            Mock Use-RedisClient {
                param($ProviderName, $Body)
                & $Body ([pscustomobject]@{ Prefix = 'test'; Stream = $null })
            }
            Mock Invoke-RedisRaw {
                param($Context, $Arguments, $Provider)
                $command = [string]($Arguments[0])
                switch ($command) {
                    'GET' {
                        $script:getCalls++
                        if ($script:getCalls -eq 1) { return $null }
                        return $cachedPayload
                    }
                    'SET' { return 'OK' }
                    'EVAL' { return 1 }
                }
            }

            $policy = Resolve-CachePolicy -MaxAge (New-TimeSpan -Minutes 5)
            $result = Get-Redis-CachedValue -ProviderName 'Redis' -Key 'same-key' -Policy $policy -WaitSeconds 1 -ScriptBlock {
                $script:executions++
                99
            }

            $result | Should -Be 42
            $script:executions | Should -Be 0
            Assert-MockCalled Invoke-RedisRaw -Times 1 -ParameterFilter { $Arguments[0] -eq 'EVAL' }
        }
    }

    It 'stores a miss and releases only its own lock token' {
        InModuleScope ExpressionCache {
            $script:executions = 0
            $script:commands = New-Object 'System.Collections.Generic.List[object]'

            Mock Use-RedisClient {
                param($ProviderName, $Body)
                & $Body ([pscustomobject]@{ Prefix = 'test'; Stream = $null })
            }
            Mock Invoke-RedisRaw {
                param($Context, $Arguments, $Provider)
                $script:commands.Add(@($Arguments)) | Out-Null
                if ($Arguments[0] -eq 'GET') { return $null }
                if ($Arguments[0] -eq 'SET' -and $Arguments -contains 'NX') { return 'OK' }
                if ($Arguments[0] -eq 'EVAL') { return 1 }
                return 'OK'
            }

            $policy = Resolve-CachePolicy -MaxAge (New-TimeSpan -Minutes 5)
            $result = Get-Redis-CachedValue -ProviderName 'Redis' -Key 'miss' -Policy $policy -WaitSeconds 1 -ScriptBlock {
                $script:executions++
                17
            }

            $result | Should -Be 17
            $script:executions | Should -Be 1

            $lockCommand = $script:commands | Where-Object { $_[0] -eq 'SET' -and $_ -contains 'NX' } | Select-Object -First 1
            $unlockCommand = $script:commands | Where-Object { $_[0] -eq 'EVAL' } | Select-Object -First 1
            $lockCommand | Should -Not -BeNullOrEmpty
            $unlockCommand | Should -Not -BeNullOrEmpty
            $unlockCommand[-1] | Should -Be $lockCommand[2]
        }
    }

    It 'holds the provider lock for the full client lease' {
        InModuleScope ExpressionCache {
            $provider = Get-ExpressionCacheProvider -ProviderName 'Redis'
            Set-ProviderStateValues -Provider $provider -Patch @{
                Client = [pscustomobject]@{ Prefix = 'test'; Stream = $null }
                Initialized = $true
            }

            $lockWasHeld = Use-RedisClient -ProviderName 'Redis' -Body {
                param($client)
                $provider.__Lock.IsWriteLockHeld
            }

            $lockWasHeld | Should -BeTrue
        }
    }
}
