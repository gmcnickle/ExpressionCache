#requires -Modules Pester

Import-Module "$PSScriptRoot/../ExpressionCache.psd1" -Force

Describe 'ExpressionCache :: LocalFileSystemCache' {

  BeforeAll {
    Initialize-ExpressionCache -AppName 'TestApp'

    # Point the provider at an isolated temp folder (Pester's TestDrive:)
    $provider = Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
    $provider.Config.CacheFolder  = Join-Path $TestDrive 'cache'
    $provider.Config.MaximumAge   = (Get-Date).AddDays(-7)
    $provider.Config.CacheVersion = '1'
  }

  BeforeEach {
    # Clean cache folder between tests
    $prov = Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
    if (Test-Path $prov.Config.CacheFolder) {
      Remove-Item -LiteralPath $prov.Config.CacheFolder -Recurse -Force
    }
    $prov.Config.Initialized = $false
  }

  It 'computes on a miss and writes a cache file' {
    $execCount = @{ Value = 0 }
    $sb = { param($x,$y) $execCount.Value++; $x + $y }.GetNewClosure()

    $result = Get-ExpressionCache -ScriptBlock $sb -Arguments 1,2
    $result | Should -Be 3
    $execCount.Value | Should -Be 1

    $key  = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 1,2
    $prov = Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
    $path = Join-Path $prov.Config.CacheFolder "$key.txt"
    Test-Path $path | Should -BeTrue

    # file contents
    $json = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $json.Version  | Should -Be $prov.Config.CacheVersion
    $json.Data     | Should -Not -BeNullOrEmpty
    $json.Query    | Should -BeOfType ([string])
  }

  It 'returns from cache on a hit (does not re-execute)' {
    $execCount = @{ Value = 0 }
    $sb = { param($x,$y) $execCount.Value++; $x + $y }.GetNewClosure()

    # first call populates cache
    Get-ExpressionCache -ScriptBlock $sb -Arguments 1,2 | Out-Null
    $execCount.Value | Should -Be 1

    # second call should not execute again
    Get-ExpressionCache -ScriptBlock $sb -Arguments 1,2 | Should -Be 3
    $execCount.Value | Should -Be 1
  }

  It 'expires a stale cache file based on MaximumAge' {
    $execCount = @{ Value = 0 }
    $sb = { param($x,$y) $execCount.Value++; $x + $y }.GetNewClosure()

    # write cache
    $key  = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 1,2
    Get-ExpressionCache -ScriptBlock $sb -Arguments 1,2 | Out-Null
    $execCount.Value | Should -Be 1

    # age the file beyond MaximumAge
    $prov = Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
    $path = Join-Path $prov.Config.CacheFolder "$key.txt"
    (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-8)

    # next call should recompute
    Get-ExpressionCache -ScriptBlock $sb -Arguments 1,2 | Should -Be 3
    $execCount.Value | Should -Be 2
  }

  It 'invalidates cache when CacheVersion changes' {
    $execCount = @{ Value = 0 }
    $sb = { param($x,$y) $execCount.Value++; $x + $y }.GetNewClosure()

    Get-ExpressionCache -ScriptBlock $sb -Arguments 1,2 | Out-Null
    $execCount.Value | Should -Be 1

    # bump version
    $prov = Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
    $prov.Config.CacheVersion = '2'

    Get-ExpressionCache -ScriptBlock $sb -Arguments 1,2 | Should -Be 3
    $execCount.Value | Should -Be 2
  }

  It 'auto-generates a stable key and includes argument differences' {
    $sb = { param($x,$y) $x + $y }

    $k12 = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 1,2
    $k21 = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 2,1
    $k12dup = New-ExpressionCacheKey -ScriptBlock $sb -Arguments 1,2

    $k12 | Should -Not -BeNullOrEmpty
    $k12 | Should -Not -Be $k21  # argument order matters
    $k12 | Should -Be $k12dup    # deterministic
  }

  It 'lazily initializes the provider (creates folder and marks Initialized)' {
    $execCount = @{ Value = 0 }
    $sb = { param($x,$y) $execCount.Value++; $x + $y }.GetNewClosure()

    $prov = Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
    $prov.Config.Initialized = $false
    $folder = $prov.Config.CacheFolder
    Test-Path $folder | Should -BeFalse

    Get-ExpressionCache -ScriptBlock $sb -Arguments 1,2 | Should -Be 3

    Test-Path $folder | Should -BeTrue
    $prov.Config.Initialized | Should -BeTrue
  }

  It 'throws a clear error for an unknown StorageType' {
    { Get-ExpressionCache -ScriptBlock { 1 } -StorageType 'Nope' } |
      Should -Throw '*Storage type*not registered*'
  }

  It 'throws a clear error when provider function is missing' {
    # temporarily set bad function name
    $prov = Get-ExpressionCacheProvider -Name 'LocalFileSystemCache'
    $old  = $prov.ReadFromCache
    $prov.ReadFromCache = 'Totally-Not-Here'

    try {
      { Get-ExpressionCache -ScriptBlock { 1 } } |
        Should -Throw '*Provider function*not found*'
    } finally {
      $prov.ReadFromCache = $old
    }
  }
}
