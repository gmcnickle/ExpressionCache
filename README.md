# ExpressionCache

<p align="center">
  <!-- <a href="https://github.com/gmcnickle/ExpressionCache/actions/workflows/tests.yml">
    <img alt="CI" src="https://github.com/gmcnickle/ExpressionCache/actions/workflows/tests.yml/badge.svg">
  </a> -->
  <a href="LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg">
  </a>
  <a href="https://www.powershellgallery.com/packages/ExpressionCache">
    <img alt="PSGallery Version" src="https://img.shields.io/powershellgallery/v/ExpressionCache">
  </a>
  <a href="https://www.powershellgallery.com/packages/ExpressionCache">
    <img alt="PSGallery Downloads" src="https://img.shields.io/powershellgallery/dt/ExpressionCache">
  </a>
  <!-- Optional: Code coverage (if you add Codecov) -->
  <!-- <a href="https://codecov.io/gh/gmcnickle/ExpressionCache">
    <img alt="Coverage" src="https://codecov.io/gh/gmcnickle/ExpressionCache/branch/main/graph/badge.svg">
  </a> -->
</p>


Lightweight, pluggable caching for PowerShell *expressions* (scriptblocks). You provide a `{ ... }` to run (plus optional args); a storage *provider* handles lookup, freshness, and persistence.

---

## Install (local dev)

```powershell
# From the repo root
Import-Module "$PSScriptRoot/ExpressionCache.psd1" -Force
```

> Requires PowerShell 5.1+ (works great on 7.x). Pester is only needed to run tests.

---

## Quick start

```powershell
Initialize-ExpressionCache -AppName 'MyApp'

# Cache any scriptblock; the key auto-generates from the script + args
$result = Get-ExpressionCache -ScriptBlock { param($x,$y) $x + $y } -Arguments 1,2
$result  # -> 3
```

Prefer parameters over ambient variables inside your scriptblock. If you must capture outer vars, pass a closure: `{ Get-Content $file }.GetNewClosure()`.

---

## Public API

- `Initialize-ExpressionCache -AppName <string> [-Providers <object[]>]`
- `Get-ExpressionCache -ScriptBlock <scriptblock> [-Arguments <object[]>] [-Key <string>] [-StorageType <string>]`
- `Add-ExpressionCacheProvider -Provider <object>`
- `Get-ExpressionCacheProvider [-Name <string>]`
- `Remove-ExpressionCacheProvider -Name <string> [-PassThru]`

### Provider object shape

```powershell
$provider = [pscustomobject]@{
  Name        = 'LocalFileSystemCache'
  Description = 'Stores cached values in the local file system.'
  Version     = '1.0.0'
  Config      = [pscustomobject]@{
    CacheFolder  = "$env:LOCALAPPDATA\ExpressionCache\MyApp"
    MaximumAge   = (Get-Date).AddDays(-7)
    CacheVersion = '1'    # schema/version for on-disk format
    Initialized  = $false
  }
  Initialize    = 'Initialize-LocalFileSystemCache'  # optional
  ReadFromCache = 'Get-FileSystem-CachedValue'       # required
}
Add-ExpressionCacheProvider -Provider $provider
```

> Internally, `Config` is the single source of truth. If a provider supplies `InitializeArgs`, they are merged into `Config` at registration.

### Writing executors

Pass data via `param(...)`/`-Arguments` (safer & more cache-stable):

```powershell
Get-ExpressionCache -ScriptBlock {
  param($userId, $token)
  Invoke-RestMethod "https://api.example.com/users/$userId" -Headers @{ Authorization = "Bearer $token" }
} -Arguments 42, $token
```

If you want to control keying (e.g., ignore a mutable state arg), pass `-Key` explicitly:

```powershell
$key = 'users/42'
Get-ExpressionCache -Key $key -ScriptBlock { param($id,$state) Get-User $id } -Arguments 42, $state
```

---

## File-system provider notes

- Supports `-WhatIf/-Confirm` for state-changing operations (create dir, write file, expire stale cache).
- Cache entries include `{ Version, Query, Data }` where `Version` is `Config.CacheVersion`.
- Expiry is based on `Config.MaximumAge` (timestamp comparison).

---

## Tests

```powershell
# Run all tests (Pester v5+)
pwsh ./tests/run-tests.ps1
```

The suite covers cache misses/hits, expiry, version invalidation, lazy init, error paths, and key stability. Tests use `TestDrive:` to isolate the on-disk cache.

---

## Project layout

```
ExpressionCache.psd1
ExpressionCache.psm1
Providers/
  FileSystem.ps1
Utilities/
  *.ps1
tests/
  ExpressionCache.Tests.ps1
  run-tests.ps1
```

---

## Design highlights

- **Single source of truth:** provider settings live in `Config`.
- **Explicit execution:** call sites pass a **scriptblock**; providers choose how to cache.
- **Safety:** avoids `Invoke-Expression`; favors parameters over ambient variables.
- **Extensible:** add providers (Redis, S3, memory) by implementing `ReadFromCache` (and optional `Initialize`).

---

## License

This project is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

---

## ✒️ Attribution

**Primary Author:** Gary McNickle ([gmcnickle@outlook.com](mailto:gmcnickle@outlook.com))  
**Co-Author & Assistant:** ChatGPT (OpenAI)

This script was collaboratively designed and developed through interactive sessions with ChatGPT, combining human experience and AI-driven support to solve real-world development challenges.

---

## 🌐 Connect

[![GitHub](https://img.shields.io/badge/GitHub-%40gmcnickle-181717?style=flat-square&logo=github)](https://github.com/gmcnickle)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Gary%20McNickle-0A66C2?style=flat-square&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/gmcnickle)
[![ORCID](https://img.shields.io/badge/ORCID-0009--0002--7161--0992-A6CE39?style=flat-square&logo=orcid)](https://orcid.org/0009-0002-7161-0992)
[![RogueCivilian](https://img.shields.io/badge/RogueCivilian-Articles%20%26%20Projects-552B75?style=flat-square)](https://roguecivilian.net)
