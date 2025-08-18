#requires -Modules Pester


# Quick connectivity probe (TCP) – used only to decide whether to skip Redis tests
function Test-RedisAvailable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$HostName,
    [Parameter(Mandatory)]
    [int]$Port,
    [int]$TimeoutMs = 1500
  )
  if ([string]::IsNullOrWhiteSpace($HostName)) { throw "HostName must be a non-empty string." }

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $async = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromMilliseconds($TimeoutMs))) {
      $client.Close(); return $false
    }
    $client.EndConnect($async); return $true
  }
  catch { return $false } finally { $client.Dispose() }
}

function script:Reset-ProviderState {
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(
    [Parameter(Mandatory)]
    [psobject]$Provider
  )

  if (-not $Provider) {
    Write-Verbose "Reset: provider '$name' not registered."
    return
  }

  $name = $Provider.Name
  $target = "Provider '$name'"
  if ($PSCmdlet.ShouldProcess($target, 'Reset (clear cache)')) {
    try {
      # Ensure no prompts in tests; pass Force through to providers that honor it
      Clear-ExpressionCache -ProviderName $name -Force -Confirm:$false -ErrorAction Stop | Out-Null
    }
    catch {
      # If provider lacks a ClearCache hook or clearing fails, log and continue
      Write-Verbose "Reset: failed to clear provider '$name': $($_.Exception.Message)"
    }
  }
}


Describe 'ExpressionCache :: Providers' {

  BeforeAll {
    $cwd = (Get-Location).Path

    $psd1Path = Join-Path $cwd 'src/ExpressionCache.psd1'
    if (-not (Test-Path $psd1Path)) { throw "Cannot locate $psd1Path" }
    Import-Module $psd1Path -Force

    $SupportPath = Join-Path $cwd 'tests/support/common.ps1'
    if (-not (Test-Path $SupportPath)) { throw "Cannot locate $SupportPath" }
    . $SupportPath -ModulePath $psd1Path

    # Build test-specific provider configs (prefix etc.) here in RUN phase:
    $testPrefix = 'test:' + [guid]::NewGuid().ToString('N') + ':'

    $providerConfigs = @(
      @{ Key = 'LocalFileSystemCache'; Config = @{ Prefix = $testPrefix } }
    )

    $enableRedis =
    $IsLinux -and
    $env:EXPRCACHE_SKIP_REDIS -ne '1' -and
    -not [string]::IsNullOrWhiteSpace($env:EXPRCACHE_REDIS_PASSWORD)

    if ($enableRedis) {
      $providerConfigs += @{ Key = 'Redis'; Config = @{ Database = 15; Prefix = $testPrefix } }
    }

    $providers = Initialize-ExpressionCache -AppName 'TestApp' -Providers $providerConfigs

    $script:Cases = @()

    $fs = $providers | Where-Object Name -eq 'LocalFileSystemCache'
    if ($fs) {
      $script:Cases += @{ Provider = $fs; ProviderName = $fs.Name; SkipReason = $null }
    }

    if ($enableRedis) {
      $rd = $providers | Where-Object Name -eq 'Redis'
      if ($rd) {
        $script:Cases += @{ Provider = $rd; ProviderName = $rd.Name; SkipReason = $null }
      }
    }
    else {
      $script:Cases += @{ Provider = $null; ProviderName = 'Redis'; SkipReason = 'Redis disabled on this environment.' }
    }
  }

  # BeforeEach { Reset-Providers-ForTests }
  # AfterEach { Reset-Providers-ForTests }

  BeforeDiscovery {
    $testPrefix = 'test:' + [guid]::NewGuid().ToString('N') + ':'

    # Always include LocalFileSystemCache
    $providerConfigs = @(
      @{ Key = 'LocalFileSystemCache'; Config = @{ Prefix = $testPrefix } }
    )

    # Decide if Redis is eligible on this environment
    $enableRedis =
    $IsLinux -and
    $env:EXPRCACHE_SKIP_REDIS -ne '1' -and
    -not [string]::IsNullOrWhiteSpace($env:EXPRCACHE_REDIS_PASSWORD)

    if ($enableRedis) {
      $providerConfigs += @{ Key = 'Redis'; Config = @{ Database = 15; Prefix = $testPrefix } }
    }

    # Initialize providers that are actually enabled
    $providers = Initialize-ExpressionCache -AppName 'TestApp' -Providers $providerConfigs

    # Build test cases: real LocalFS + real Redis (if enabled) + a "skipped" Redis case when not enabled
    $script:Cases = @()

    # Local FS (always present)
    $fs = $providers | Where-Object Name -eq 'LocalFileSystemCache'
    if ($fs) {
      $script:Cases += @{
        Provider     = $fs
        ProviderName = $fs.Name
        SkipReason   = $null
      }
    }

    # Redis
    if ($enableRedis) {
      $rd = $providers | Where-Object Name -eq 'Redis'
      if ($rd) {
        $script:Cases += @{
          Provider     = $rd
          ProviderName = $rd.Name
          SkipReason   = $null
        }
      }
    }
    else {
      # Include a skipped Redis case so each It{} stays uniform across providers
      $script:Cases += @{
        Provider     = $null
        ProviderName = 'Redis'
        SkipReason   = 'Redis tests disabled on this environment (non-Linux or missing credentials).'
      }
    }
  }

  Context 'Core caching semantics' {

    It 'computes on a miss and writes to cache' -TestCases $script:Cases {
      param($Provider, $ProviderName, $SkipReason)
      if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason; return }

      Reset-ProviderState $provider

      $exec = @{ Value = 0 }
      $sb = { param($x, $y) $exec.Value++; $x + $y }.GetNewClosure()

      $result = Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb -Arguments 1, 2
      $result | Should -Be 3
      $exec.Value | Should -Be 1

      Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb -Arguments 1, 2 | Should -Be 3
      $exec.Value | Should -Be 1
    }

    It 'returns from cache on a hit (does not re-execute)' -TestCases $script:Cases {
      param($Provider, $ProviderName, $SkipReason)
      if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason; return }

      Reset-ProviderState $provider

      $exec = @{ Value = 0 }
      $sb = { param($x, $y) $exec.Value++; $x + $y }.GetNewClosure()
      $maxAge = (New-TimeSpan -Seconds 10)

      Get-ExpressionCache -ProviderName $ProviderName -MaxAge $maxAge -ScriptBlock $sb -Arguments 1, 2 | Should -Be 3
      $exec.Value | Should -Be 1

      Get-ExpressionCache -ProviderName $ProviderName -MaxAge $maxAge -ScriptBlock $sb -Arguments 1, 2 | Should -Be 3
      $exec.Value | Should -Be 1
    }

    It 'does not cache $null results' -TestCases $script:Cases {
      param($Provider, $ProviderName, $SkipReason)
      if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason; return }

      Reset-ProviderState $provider

      $exec = @{ Value = 0 }
      $sb = { $exec.Value++; return $null }.GetNewClosure()

      $r1 = Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb
      $r1 | Should -Be $null
      $exec.Value | Should -Be 1

      $r2 = Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb
      $r2 | Should -Be $null
      $exec.Value | Should -Be 2
    }

    It 'auto-generates a stable key and includes argument differences' -TestCases $script:Cases {
      param($SkipReason)
      if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason; return }

      $sb = { param($x, $y) $x + $y }
      $k12 = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 1, 2
      $k21 = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 2, 1
      $k12b = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 1, 2

      $k12  | Should -Not -BeNullOrEmpty
      $k12  | Should -Not -Be $k21
      $k12  | Should -Be $k12b
    }
  }

  Context 'Expiration & invalidation' {

    It 'expires stale entries based on MaximumAge/TTL' -TestCases $script:Cases {
      param($Provider, $ProviderName, $SkipReason)
      if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason; return }

      Reset-ProviderState $provider

      $exec = @{ Value = 0 }
      $sb = { param($x, $y) $exec.Value++; $x + $y }.GetNewClosure()

      if ($provider.Name -eq 'LocalFileSystemCache') {
        # Force the file to look old by touching LastWriteTime
        $provider.Config.DefaultMaxAge = (New-TimeSpan -Days 1)
        $key = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 1, 2

        Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb -Arguments 1, 2 | Out-Null
        $exec.Value | Should -Be 1

        $prov = Get-ExpressionCacheProvider -ProviderName 'LocalFileSystemCache'
        $path = Join-Path $prov.Config.CacheFolder "$key.txt"
        (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-8)

        Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb -Arguments 1, 2 | Should -Be 3
        $exec.Value | Should -Be 2
      }
      else {
        # Redis: use absolute expiry to force recompute
        $expireAt = (Get-Date).AddSeconds(1)
        Get-ExpressionCache -ProviderName $ProviderName -ExpireAtUtc $expireAt -ScriptBlock $sb -Arguments 1, 2 | Out-Null
        $exec.Value | Should -Be 1

        Start-Sleep -Seconds 2
        Get-ExpressionCache -ProviderName $ProviderName -ExpireAtUtc $expireAt -ScriptBlock $sb -Arguments 1, 2 | Should -Be 3
        $exec.Value | Should -Be 2
      }
    }

    # FS-specific cache version invalidation
    It 'invalidates cache when CacheVersion changes (FS only)' -TestCases $script:Cases {
      param($Provider, $ProviderName, $SkipReason)
      if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason; return }
      if ($ProviderName -ne 'LocalFileSystemCache') { Set-ItResult -Skipped -Because 'Not applicable to this provider'; return }

      Reset-ProviderState $Provider

      $exec = @{ Value = 0 }
      $sb = { param($x, $y) $exec.Value++; $x + $y }.GetNewClosure()

      # Warm cache
      Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb -Arguments 1, 2 | Should -Be 3
      $exec.Value | Should -Be 1

      # Compute next version while preserving type
      $oldVersion = (Get-ExpressionCacheProvider -ProviderName $ProviderName).Config.CacheVersion
      $nextVersion = if ($oldVersion -is [int]) { $oldVersion + 1 } else { "$oldVersion:next" }

      # Mutate live provider inside module scope
      InModuleScope ExpressionCache -Parameters @{ Name = $ProviderName; Next = $nextVersion } {
        $scopedProvider = Get-ExpressionCacheProvider -ProviderName $Name
        $scopedProvider.Config | Set-ECProperty -Name 'CacheVersion' -Value $Next
        (Get-ExpressionCacheProvider -ProviderName $Name).Config.CacheVersion | Should -Be $Next
      }

      try {
        # Should miss and recompute
        Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb -Arguments 1, 2 | Should -Be 3
        $exec.Value | Should -Be 2
      }
      finally {
        InModuleScope ExpressionCache -Parameters @{ Name = $ProviderName; Old = $oldVersion } {
          $scopedProvider = Get-ExpressionCacheProvider -ProviderName $Name
          $scopedProvider.Config | Set-ECProperty -Name 'CacheVersion' -Value $Old
        }
      }
    }
   
  }

  Context 'Clear-ExpressionCache' {
    It 'calls provider ClearCache with -Force' {
      Mock -ModuleName ExpressionCache Invoke-ExpressionCacheProviderHook { } -Verifiable
      Clear-ExpressionCache -ProviderName 'Fake' -Force -Confirm:$false
      Assert-MockCalled -ModuleName ExpressionCache Invoke-ExpressionCacheProviderHook -Times 1 -ParameterFilter {
        $ProviderName -eq 'Fake' -and $Hook -eq 'ClearCache' -and $Arguments.Force
      }
    }

    It 'honors -WhatIf (no hook call)' {
      Mock -ModuleName ExpressionCache Invoke-ExpressionCacheProviderHook { } -Verifiable
      Clear-ExpressionCache -ProviderName 'Fake' -Force -WhatIf
      Assert-MockCalled -ModuleName ExpressionCache Invoke-ExpressionCacheProviderHook -Times 0
    }
  }

  Context 'Initialization & provider integrity' {

    It 'lazily initializes (first write sets up backing store)' -TestCases $script:Cases {
      param($Provider, $ProviderName, $SkipReason)
      if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason; return }

      Reset-ProviderState $provider

      $exec = @{ Value = 0 }
      $sb = { param($x, $y) $exec.Value++; $x + $y }.GetNewClosure()

      if ($provider.Name -eq 'LocalFileSystemCache') {
        $folder = $provider.Config.CacheFolder
        Test-Path $folder | Should -BeFalse
        Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb -Arguments 1, 2 | Should -Be 3
        Test-Path $folder | Should -BeTrue
        $provider.State.Initialized | Should -BeTrue
      }
      else {
        { Get-ExpressionCache -ProviderName $ProviderName -ScriptBlock $sb -Arguments 1, 2 } | Should -Not -Throw
      }
    }

    It 'throws a clear error for an unknown StorageType' {
      { Get-ExpressionCache -ScriptBlock { 1 } -ProviderName 'Nope' } |
      Should -Throw '*Provider*not registered*'
    }

    It 'throws a clear error when provider function is missing (standalone)' {
      $name = 'Broken-' + [guid]::NewGuid().ToString('N')

      { Add-ExpressionCacheProvider -Provider @{
          Name        = $name
          GetOrCreate = 'Totally-Not-Here'   # doesn't exist
          Config      = [pscustomobject]@{}
        }
      } | Should -Throw "*command 'Totally-Not-Here'*not found*"

      { Get-ExpressionCache -ProviderName $name -ScriptBlock { 1 } } | Should -Throw '*Provider*not registered*'
    }
  }
}
