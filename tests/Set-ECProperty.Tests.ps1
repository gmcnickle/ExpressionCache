#requires -Modules Pester

Describe 'ExpressionCache :: Set-ECProperty' {

  BeforeAll {
    $here = $PSScriptRoot                                   
    $repoRoot = (Resolve-Path (Join-Path $here '..')).Path  
    $psd1Path = Join-Path $repoRoot 'src/ExpressionCache.psd1'
    $support = Join-Path $here 'support/Common.ps1'         

    if (-not (Test-Path $psd1Path)) { throw "Cannot locate psd1 at: $psd1Path" }
    if (-not (Test-Path $support)) { throw "Cannot locate support at: $support" }

    . $support -ModulePath $psd1Path
    Import-Module $psd1Path -Force

    Ensure-ExpressionCacheInitialized
  }

  BeforeEach { Reset-Providers-ForTests }
  AfterEach  { Reset-Providers-ForTests }

  Context 'Basic add/update behavior' {

    It 'Adds if missing, then updates on second call' {
      $obj = [pscustomobject]@{ Name = 'Jane Developer' }
      $obj.PSObject.Properties['Title'] | Should -BeNullOrEmpty
      $obj | Set-ECProperty -Name 'Title' -Value 'Engineer' | Out-Null
      $obj.Title | Should -Be 'Engineer'
      $obj | Set-ECProperty -Name 'Title' -Value 'Manager' | Out-Null
      $obj.Title | Should -Be 'Manager'
    }

    It 'Does not overwrite when -NoOverwrite is used' {
      $obj = [pscustomobject]@{ Name='Jane Developer'; Title='Engineer' }
      $obj | Set-ECProperty -Name 'Title' -Value 'Manager' -NoOverwrite | Out-Null
      $obj.Title | Should -Be 'Engineer'
    }

    It 'Adds if missing, or updates only when existing value is $null with -OnlyIfNull' {
      $obj = [pscustomobject]@{ Name='Jane Developer'; Title=$null }
      $obj.Title | Should -Be $null
      $obj | Set-ECProperty -Name 'Title' -Value 'Engineer' -OnlyIfNull -DontEnforceType | Out-Null
      $obj.Title | Should -Be 'Engineer'
      $obj | Set-ECProperty -Name 'Title' -Value 'Manager' -OnlyIfNull -DontEnforceType | Out-Null
      $obj.Title | Should -Be 'Engineer'
    }

    It 'Adds when missing even with -OnlyIfNull' {
      $obj = [pscustomobject]@{ Name='Jane' }
      $obj | Set-ECProperty -Name 'Title' -Value 'Engineer' -OnlyIfNull -DontEnforceType | Out-Null
      $obj.Title | Should -Be 'Engineer'
    }

    It 'respects -WhatIf (no changes made)' {
      $o = [pscustomobject]@{ Title='Engineer' }
      $null = $o | Set-ECProperty -Name 'Title' -Value 'Manager' -WhatIf
      $o.Title | Should -Be 'Engineer'
    }
  }

  Context 'Flag precedence' {
    It 'Prefers -NoOverwrite when combined with -OnlyIfNull' {
      $obj = [pscustomobject]@{ Title='Engineer' }
      $obj | Set-ECProperty -Name 'Title' -Value 'Manager' -NoOverwrite -OnlyIfNull | Out-Null
      $obj.Title | Should -Be 'Engineer'
    }
  }

  Context 'Case-insensitivity & property identity' {
    It 'Is case-insensitive on property names' {
      $obj = [pscustomobject]@{ Name='Jane'; Title='Engineer' }
      $obj | Set-ECProperty -Name 'title' -Value 'Manager' | Out-Null
      $obj.Title | Should -Be 'Manager'
    }

    It 'Does not create a duplicate when adding with different case' {
      $obj = [pscustomobject]@{ Title='Engineer' }
      $obj | Set-ECProperty -Name 'title' -Value 'Manager' | Out-Null
      ($obj.PSObject.Properties | Where-Object Name -eq 'Title').Count | Should -Be 1
      $obj.Title | Should -Be 'Manager'
    }
  }

  Context 'Pipeline behavior & pass-through' {
    It 'Returns the same instance (pipeline-friendly pass-through)' {
      $obj = [pscustomobject]@{ Name='Jane' }
      $returned = $obj | Set-ECProperty -Name 'Title' -Value 'Engineer'
      [object]::ReferenceEquals($obj, $returned) | Should -BeTrue
    }

    It 'Works with multiple pipeline inputs and returns each instance' {
      $items = 1..3 | ForEach-Object { [pscustomobject]@{ Id = $_ } } |
               Set-ECProperty -Name 'Tag' -Value 'X'
      $items | Should -HaveCount 3
      foreach ($tag in $items.Tag) { $tag | Should -Be 'X' }
    }
  }

  Context 'Type handling & enforcement' {
    It 'Does not check type when adding a new property' {
      $obj = [pscustomobject]@{ Name='Jane' }
      $obj | Set-ECProperty -Name 'LastSeen' -Value ([datetime]'2025-08-13') | Out-Null
      $obj.LastSeen.GetType().FullName | Should -Be 'System.DateTime'
    }

    It 'Throws on mismatched type when updating without -DontEnforceType' {
      $obj = [pscustomobject]@{ Name='Jane'; Count=[int]7 }
      { $obj | Set-ECProperty -Name 'Count' -Value 'eight' } | Should -Throw
      $obj.Count | Should -Be 7
    }

    It 'Allows compatible updates when -DontEnforceType is specified' {
      $obj = [pscustomobject]@{ Name='Jane'; Count=[int]7 }
      $obj | Set-ECProperty -Name 'Count' -Value '8' -DontEnforceType | Out-Null
      $obj.Count | Should -Be '8'
    }

    It 'Preserves array types on add and update' {
      $obj = [pscustomobject]@{}
      $obj | Set-ECProperty -Name 'Tags' -Value @('a','b') | Out-Null
      $obj.Tags -is [object[]] | Should -BeTrue
      $obj | Set-ECProperty -Name 'Tags' -Value @('c') | Out-Null
      $obj.Tags | Should -Be @('c')
    }
  }

  Context 'Non-writable or computed members' {
    It 'Throws when trying to set a read-only property' {
      $obj = [System.Uri]'https://example.com'
      { $obj | Set-ECProperty -Name 'Host' -Value 'changed.example.com' } | Should -Throw
    }

    It 'Updates a NoteProperty but not a ScriptProperty' {
      $obj = [pscustomobject]@{}
      Add-Member -InputObject $obj -MemberType ScriptProperty -Name 'Title' -Value { 'computed' }
      { $obj | Set-ECProperty -Name 'Title' -Value 'X' } | Should -Throw
    }
  }

  Context 'Errors & diagnostics' {
    It 'Error message includes property name and types on mismatch' {
      $obj = [pscustomobject]@{ Count = 1 }
      $err = { $obj | Set-ECProperty -Name 'Count' -Value 'one' } | Should -Throw -PassThru
      $err.Exception.Message | Should -Match "property 'Count'"
      $err.Exception.Message | Should -Match 'System\.Int32'
      $err.Exception.Message | Should -Match 'System\.String'
    }

    It 'Throws when Object is $null' {
      { Set-ECProperty -Object $null -Name 'X' -Value 1 } | Should -Throw
    }
  }
}
