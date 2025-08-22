#requires -Modules Pester

Describe 'ExpressionCache :: Providers' {

  function script:Reset-ProviderState {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
      [Parameter(Mandatory)]
      [psobject]$Provider
    )

    if (-not $Provider) {
      Write-Verbose "Reset: provider '$($Provider.name)' not registered."
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
  
  function script:Get-TestPrefix {
    $result = @{}

    InModuleScope ExpressionCache -Parameters @{Data = $result } {
      if ($null -eq $script:get_expression_cache_tests_prefix) {
        $script:get_expression_cache_tests_prefix = 'test:' + [guid]::NewGuid().ToString('N') + ':'
      }

      $Data["prefix"] = $script:get_expression_cache_tests_prefix
    }

    return $result["prefix"]
  }

  function script:Get-RedisEnabled {
    # Enable only if: Linux runner AND not explicitly skipped AND password provided
    if (-not $IsLinux) { return $false }
    if ($env:EXPRCACHE_SKIP_REDIS -eq '1') { return $false }
    if ([string]::IsNullOrWhiteSpace($env:EXPRCACHE_REDIS_PASSWORD)) { return $false }
    return $true
  }

function script:Get-ProviderConfigs {
  param([switch]$Discovery)

  $testPrefix   = Get-TestPrefix
  $redisEnabled = Get-RedisEnabled

  # --- Build provider map (only add Redis if gate passes) ---
  $providerList = @(
    @{ Name = 'LocalFileSystemCache'; Config = @{ Prefix = $testPrefix } }
  )
  if ($redisEnabled) {
    $providerList += @{ Name = 'Redis'; Config = @{ Database = 15; Prefix = $testPrefix } }
  }

  $providerMap = [ordered]@{}
  foreach ($p in $providerList) { $providerMap[$p.Name] = $p }

  # --- Initialize (unless discovery) ---
  $providers = if ($Discovery) { $null } else {
    Initialize-ExpressionCache -AppName 'TestApp' -Providers $providerMap
  }

  # Helper to build a single Redis test case with correct skip reason
  function New-RedisTestCase {
    param(
      [hashtable]$Providers,
      [bool]$RedisEnabled,
      [switch]$DiscoveryMode
    )
    $rd = $null
    if ($Providers -and $Providers.Contains('Redis')) { $rd = $Providers['Redis'] }

    $skip =
      if (-not $RedisEnabled) {
        'Redis tests disabled on this environment (non-Linux, SKIP_REDIS=1, or missing credentials).'
      }
      elseif (-not $rd -and -not $DiscoveryMode) {
        # Only complain about "not registered" when we actually initialized providers
        'Redis provider not registered for this run.'
      }
      else { $null }

    if ($DiscoveryMode) {
      return @{ ProviderName = 'Redis'; SkipReason = $skip }
    } else {
      return @{ Provider = $rd; ProviderName = 'Redis'; SkipReason = $skip }
    }
  }

  $testCases = @()

  if ($Discovery) {
    # Local FS is always discoverable
    $testCases += @{ ProviderName = 'LocalFileSystemCache'; SkipReason = $null }

    # Exactly one Redis case (skip reason covers disabled)
    $testCases += New-RedisTestCase -Providers $null -RedisEnabled:$redisEnabled -DiscoveryMode
  }
  else {
    # Local FS (only add if actually registered)
    if ($providers -and $providers.Contains('LocalFileSystemCache')) {
      $fs = $providers['LocalFileSystemCache']
      $testCases += @{ Provider = $fs; ProviderName = $fs.Name; SkipReason = $null }
    }

    # Exactly one Redis case; will be skipped if disabled or not registered
    $testCases += New-RedisTestCase -Providers $providers -RedisEnabled:$redisEnabled
  }

  return $testCases
}



  function script:Add-Common {
    $here = $PSScriptRoot                                   
    $repoRoot = (Resolve-Path (Join-Path $here '..')).Path  
    $psd1Path = Join-Path $repoRoot 'src/ExpressionCache.psd1'
    $support = Join-Path $here 'support/Common.ps1'         

    if (-not (Test-Path $psd1Path)) { throw "Cannot locate psd1 at: $psd1Path" }
    if (-not (Test-Path $support)) { throw "Cannot locate support at: $support" }

    . $support -ModulePath $psd1Path
    Import-Module $psd1Path -Force

    if (-not (Get-Command Initialize-ExpressionCache -ErrorAction SilentlyContinue)) {
      throw "Initialize-ExpressionCache not exported. Check PSD1: RootModule/FunctionsToExport."
    }
  }

  BeforeAll {
    Add-Common

    $script:Cases = Get-ProviderConfigs
  }

  BeforeDiscovery {
    Add-Common

    $script:Cases = Get-ProviderConfigs
  }

  Context 'Core caching semantics' {

    It '(<ProviderName>) computes on a miss and writes to cache' -TestCases $script:Cases {
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

    It '(<ProviderName>) returns from cache on a hit (does not re-execute)' -TestCases $script:Cases {
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

    It '(<ProviderName>) does not cache $null results' -TestCases $script:Cases {
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

    It '(<ProviderName>) auto-generates a stable key and includes argument differences' -TestCases $script:Cases {
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

    It '(<ProviderName>) expires stale entries based on MaximumAge/TTL' -TestCases $script:Cases {
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
    It '(<ProviderName>) invalidates cache when CacheVersion changes (FS only)' -TestCases $script:Cases {
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

    It '(<ProviderName>) lazily initializes (first write sets up backing store)' -TestCases $script:Cases {
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
      $name = 'Nope'
      { Get-ExpressionCache -ProviderName $name -ScriptBlock { 1 } } | Should -Throw '*Provider*not registered*'
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

    # TODO: Decide how to expose Merge-ExpressionCacheConfig...
    # It 'overlays only specified keys, preserves others' {
    #   $base = [pscustomobject]@{ Prefix = 'default:'; CacheVersion = 1 }
    #   $ovr = @{ Prefix = 'custom:' }
    #   Merge-ExpressionCacheConfig -Base $base -Overrides $ovr | Out-Null
    #   $base.Prefix       | Should -Be 'custom:'
    #   $base.CacheVersion | Should -Be 1
    # }

    # TODO: Decide how to expose Get-DefaultProviders...
    # It 'does not mutate defaults inside Initialize-ExpressionCache' {
    #   $defaults = Get-DefaultProviders
    #   $orig = $defaults.LocalFileSystemCache.Config.Prefix

    #   Initialize-ExpressionCache -AppName X -Providers @(
    #     @{ Name = 'LocalFileSystemCache'; Config = @{ Prefix = 't:' } }
    #   ) | Out-Null

    #   (Get-DefaultProviders).LocalFileSystemCache.Config.Prefix | Should -Be $orig
    # }

  }
}
