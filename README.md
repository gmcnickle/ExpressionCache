# ExpressionCache

<p align="center">
  <img src="https://raw.githubusercontent.com/gmcnickle/ExpressionCache/main/assets/ExpressionCache-Typographic-logo-white.svg" alt="ExpressionCache Logo" width="400"/>
</p>


<p align="center">
  <a href="LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-yellow.svg">
  </a>
  <a href="https://www.powershellgallery.com/packages/ExpressionCache">
    <img alt="PSGallery Version" src="https://img.shields.io/powershellgallery/v/ExpressionCache">
  </a>
  <a href="https://www.powershellgallery.com/packages/ExpressionCache">
    <img alt="PSGallery Downloads" src="https://img.shields.io/powershellgallery/dt/ExpressionCache">
  </a>
</p>
<p align="center">
  <!-- PowerShell 7 badge -->
  <a href="https://github.com/gmcnickle/ExpressionCache/actions/workflows/pester-pwsh.yml">
    <img alt="PowerShell 7 Tests"
        src="https://github.com/gmcnickle/ExpressionCache/actions/workflows/pester-pwsh.yml/badge.svg?branch=main">
  </a>
  <!-- Windows PowerShell 5.1 badge -->
  <a href="https://github.com/gmcnickle/ExpressionCache/actions/workflows/pester-ps51.yml">
    <img alt="PowerShell 5.1 Tests"
        src="https://github.com/gmcnickle/ExpressionCache/actions/workflows/pester-ps51.yml/badge.svg?branch=main">
  </a>
  <a href="https://github.com/gmcnickle/ExpressionCache/actions/workflows/pester-linux.yml">
    <img alt="Linux Tests (PowerShell 7)"
        src="https://github.com/gmcnickle/ExpressionCache/actions/workflows/pester-linux.yml/badge.svg?branch=main">
  </a>  
</p>

Lightweight, pluggable caching for PowerShell *expressions* (scriptblocks).  
Designed for **ease of use** — you can cache the results of *any* expression that outputs data, with minimal configuration. Drop in a `{ ... }`, run once, and let a provider handle freshness, persistence, and lookup automatically.

> ⚡ ExpressionCache is in preview. I’d love early developer feedback — try it out and open issues or discussions!

## Table of Contents

- [Install](#install)
- [Quick start](#quick-start)
- [Examples](#-examples)
- [Public API](#public-api)
- [Providers](#providers)
  - [Provider Object Shape and Initialization](#provider-object-shape-and-initialization)
  - [Provider Function Contracts](#provider-function-contracts)
  - [Writing Executors](#writing-executors)
- [Tests](#-tests)
- [Project layout](#project-layout)
- [Design highlights](#-design-highlights)
- [Extensibility](#extensibility)
- [Licensing](#licensing)
- [Credits](#credits)
- [Community & Show and Tell](#community--show-and-tell)

## Install

From the [PowerShell Gallery](https://www.powershellgallery.com/packages/ExpressionCache):

```powershell
Install-Module ExpressionCache -Scope CurrentUser
```

For local development:

```powershell
# From repo root
Import-Module "$PSScriptRoot/src/ExpressionCache.psd1" -Force
```

> Requires PowerShell 5.1+ (works great on 7.x).

## Quick start

```powershell
Initialize-ExpressionCache -AppName 'MyApp'

# Cache any scriptblock; the key auto-generates from the script + args.  Uses the built-in default local file system cache.
$result = Get-ExpressionCache -ScriptBlock { param($x,$y) $x + $y } -Arguments 1,2
# -> 3
```

Prefer `param(...)` over ambient variables inside scriptblocks.  
If you must capture outer vars, use a closure: `{ Get-Content $file }.GetNewClosure()`.

## 💡 Examples

### 1. Simple — Recursive directory search

```powershell
Initialize-ExpressionCache -AppName 'DemoApp'

$results = Get-ExpressionCache -ScriptBlock {
    param($path, $pattern)
    Get-ChildItem -Path $path -Recurse -Filter $pattern -ErrorAction SilentlyContinue
} -Arguments "C:\Projects", "*.ps1"

$results | Select-Object FullName
```

👉 Run it once, results are cached. Next call is near-instant, even if the directory tree is huge.

### 2. Developer workflow — `git pull`

```powershell
$gitOutput = Get-ExpressionCache -ScriptBlock {
    git -C "C:\Projects\ExpressionCache" pull
}

$gitOutput
```

### 3. Developer workflow — GitHub API (all PRs assigned to me)

```powershell
$token = "<your-personal-access-token>"
$me = "gmcnickle"

$prs = Get-ExpressionCache -ScriptBlock {
    param($user, $token)
    Invoke-RestMethod "https://api.github.com/search/issues?q=assignee:$user+is:pr+is:open" `
        -Headers @{ Authorization = "Bearer $token"; "User-Agent" = "ExpressionCacheDemo" }
} -Arguments $me, $token

$prs.items | Select-Object number, title, state
```

### 4. Explicit keying — Stable results, mutable args

```powershell
$key = "user-profile-42"
$userProfile = Get-ExpressionCache -Key $key -ScriptBlock {
    param($userId, $timestamp)  # timestamp doesn’t affect cache key
    Invoke-RestMethod "https://api.example.com/users/$userId"
} -Arguments 42, (Get-Date)

$userProfile
```


## Public API

**Core**
- `Initialize-ExpressionCache -AppName <string> [-Providers <object[]>] [-ReplaceProviders]`
- `Get-ExpressionCache -ScriptBlock <scriptblock> [-Arguments <object[]>] [-Key <string>] [-ProviderName <string>] [-MaxAge <timespan>]`
- `Clear-ExpressionCache [-ProviderName <string>] [-Force]`
- `New-ExpressionCacheKey -ScriptBlock <scriptblock> [-Arguments <object[]>]`

**Provider Management**
- `Add-ExpressionCacheProvider -Provider <hashtable>`
- `Get-ExpressionCacheProvider [-ProviderName <string>]`
- `Remove-ExpressionCacheProvider -ProviderName <string> [-PassThru]`

**Provider Authoring**
- `Get-ProviderConfig -Provider <object> [-Raw]`
- `Set-ProviderConfig -Provider <object> -NewConfig <hashtable>`
- `Get-ProviderStateValue -Provider <object> [-Key <string>] [-Default <object>]`
- `Set-ProviderStateValue -Provider <object> -Key <string> -Value <object>`
- `Set-ProviderStateValues -Provider <object> -Patch <hashtable> [-NonAtomic]`
- `With-ProviderLock -Provider <object> -Body <scriptblock>`

## Providers

### Provider Object Shape and Initialization

A provider in **ExpressionCache** is represented as a hashtable (or PSCustomObject) with the following shape:

```powershell
@{
    Name   = '<unique-provider-name>'  # Identifier used within ExpressionCache
    Type   = '<ProviderType>'          # Maps to your provider implementation
    Config = @{
        <key> = <value>                # Provider-specific configuration values
    }
}
```

- **Name**: Friendly identifier, unique within your cache session.
- **Type**: The provider type (usually matches the suffix of your Initialize function, e.g. `LocalFileSystemCache`, `RedisCache`).
- **Config**: Hashtable of configuration options. These are expanded as parameters to the provider's `Initialize-*` function.

When you call `Initialize-ExpressionCache`, the framework automatically calls the provider's initialize function, spreading the values in `Config` into its parameter list.

For example:

```powershell
function Initialize-LocalFileSystemCache {
    [CmdletBinding()]
    param(
        [string]$CacheFolder,
        [datetime]$MaximumAge,
        [string]$CacheVersion
    )
    # initialization logic
}
```

A provider object for this might look like:

```powershell
@{
    Name   = 'local'
    Type   = 'LocalFileSystemCache'
    Config = @{
        CacheFolder = 'C:\Temp\cache'
        MaximumAge  = (Get-Date).AddDays(-7)
        CacheVersion = 'v1'
    }
}
```

When `Initialize-ExpressionCache` is called, ExpressionCache will invoke:

```powershell
Initialize-LocalFileSystemCache -CacheFolder 'C:\Temp\cache' -MaximumAge <datetime> -CacheVersion 'v1'
```

#### Example: Redis Provider

The included Redis provider is a fully functional, dependency-free implementation built on raw TCP sockets and the RESP protocol. It serves as both a **working provider** for single-instance Redis and a **reference implementation** for building complex providers.

What it includes:
- Native RESP protocol client (no external modules required)
- Lazy, thread-safe client initialization with single-flight gating
- TTL-based expiration with sliding expiry support
- Per-key metadata tracking (query description + timestamp)
- Envelope-based serialization (JSON with CliXml fallback, gzip for large payloads)
- `SCAN`-based cache clearing (production-safe, no `KEYS *`)
- Optional `AUTH` and `SELECT` for password-protected and multi-database setups
- Debug logging via `$env:EXPRCACHE_DEBUG_REDIS`

What it intentionally omits (and where a production-grade provider might extend):
- Connection pooling or automatic reconnect
- Command pipelining/batching
- Cluster, Sentinel, or replica support

```powershell
function Initialize-RedisCache {
    param(
        [string]$HostAddress,
        [int]$Port,
        [string]$Password
    )
    # initialization logic
}
```

Provider config overrides (merged with defaults):

```powershell
@{
    Name   = 'Redis'
    Config = @{
        HostAddress = '127.0.0.1'
        Port        = 6379
        Database    = 2
        Password    = ''   # set $env:EXPRCACHE_REDIS_PASSWORD or pass explicitly
    }
}
```

> The Redis provider is designed as a reference implementation that demonstrates the full provider contract. It is suitable for development and single-instance Redis deployments. For high-availability or clustered Redis, consider building a provider on top of a dedicated Redis client library.

#### Notes for Provider Authors

- **Validation**: Add `ValidateNotNullOrEmpty` or similar attributes to your parameters to ensure Config values are valid.
- **Defaults**: Parameters can have defaults (e.g., `[int]$Port = 6379`).
- **Extensibility**: Additional fields in `Config` will be ignored unless matched by a parameter.
- **Versioning**: When updating a provider, keep parameter names stable to avoid breaking Config contracts.



### Provider Function Contracts

Providers expose three functions. ExpressionCache wires these up from your provider object and passes `Config` entries as **named parameters**.

#### 1) `Initialize-<ProviderType>`

**Purpose:** Build provider-specific state (clients, prefixes, folders), validate config, and mark the provider ready.

**Call pattern:** ExpressionCache calls this once per provider when `Initialize-ExpressionCache` runs.  
**Parameter binding:** Values from `Provider.Config` are passed as named parameters.

**Example — LocalFileSystem**

```powershell
function Initialize-LocalFileSystemCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]  $CacheFolder,
        [Parameter(Mandatory)][datetime]$MaximumAge,
        [Parameter(Mandatory)][string]  $CacheVersion,
        [string]$Prefix = ''
    )

    if (-not (Test-Path $CacheFolder)) {
        New-Item -ItemType Directory -Path $CacheFolder | Out-Null
    }

    $script:LocalFS_State = @{
        CacheFolder  = $CacheFolder
        MaximumAge   = $MaximumAge
        CacheVersion = $CacheVersion
        Prefix       = $Prefix
        Initialized  = $true
    }
}
```

#### 2) `GetOrCreate`

**Purpose:** Return a cached value for `Key` if fresh; otherwise compute via `ScriptBlock` + `Arguments`, persist, and return.

**Required params:** `Key`, `ScriptBlock`, `Arguments` (optional), plus config values.  
**Return:** The computed or cached value.

**Example — LocalFileSystem**

```powershell
function Get-LocalFileSystem-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]      $Key,
        [Parameter(Mandatory)][string]      $ProviderName,
        [Parameter(Mandatory)][scriptblock] $ScriptBlock,
        [Alias('ArgumentList')][object[]]   $Arguments,

        [Parameter(Mandatory)][string]      $CacheFolder,
        [Parameter(Mandatory)][CachePolicy] $Policy,
        [Parameter(Mandatory)][string]      $CacheVersion
    )

    $response = Get-FromLocalFileSystem -Key $Key -CacheFolder $CacheFolder -CacheVersion $CacheVersion -Policy $Policy

    if ($null -eq $response) {
        $Arguments = if ($Arguments) { $Arguments } else { @() }
        $response  = & $ScriptBlock @Arguments
        Set-ToLocalFileSystem -Key $Key -Value $response -CacheFolder $CacheFolder -CacheVersion $CacheVersion
    }

    return $response
}
```

**Requirements**
- Do not cache exceptions.  
- Enforce TTL/version rules.  
- Use deterministic keys.  
- Choose robust serialization (CLIXML, JSON, etc.).

#### 3) `Clear-<ProviderType>-Cache`

**Purpose:** Remove cached entries (by key or all). Used by `Clear-ExpressionCache`.

**Example — LocalFileSystem**

```powershell
function Clear-LocalFileSystem-Cache {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ProviderName,
        [string]$Key,
        [switch]$Force
    )

    if ($PSCmdlet.ShouldProcess("LocalFileSystemCache:$ProviderName","Clear cache")) {
        if ($Key) {
            Remove-LocalFS-Entry -Key $Key -Force:$Force
        } else {
            Remove-LocalFS-All -Force:$Force
        }
    }
}
```

#### Best Practices

- **Parameter names = Config keys.** Keep them stable across versions.  
- **Thread safety.** Ensure provider state is safe across multiple calls.  
- **Idempotence.** Multiple init calls should not corrupt state.  
- **Key versioning.** Use `CacheVersion` or key segments to avoid mixing formats.  

#### Minimal provider object tying it together

```powershell
$provider = [ordered]@{
  Name        = 'LocalFileSystemCache'
  Description = 'Stores cached values in the local file system.'
  Version     = '1.0.0'
  Config      = [ordered]@{
    CacheFolder  = "$env:LOCALAPPDATA\ExpressionCache\MyApp"
    MaximumAge   = (Get-Date).AddDays(-7)
    CacheVersion = '1'
    Prefix       = 'expr:'
  }
  Initialize  = 'Initialize-LocalFileSystemCache'
  GetOrCreate = 'Get-LocalFileSystem-CachedValue'
  ClearCache  = 'Clear-LocalFileSystem-Cache'
}
Add-ExpressionCacheProvider -Provider $provider
```

Providers included today:
- **LocalFileSystemCache** – simple file-based persistence.
- **RedisCache** – dependency-free Redis provider with native RESP protocol support, suitable for single-instance deployments and as a reference for building custom remote providers.

### Writing Executors

**What’s an executor?**  
In ExpressionCache, an *executor* is the `ScriptBlock` you pass to `Get-ExpressionCache` (or a provider’s `Get-OrCreate-*` function). It is the unit of work that computes a value on a cache miss. The executor should be a **pure, parameterized function** of its inputs.

#### Why parameterize your executor?
- **Cache stability** — the cache key derives from the executor + arguments.
- **Isolation** — avoids closure/scope bugs from `$script:` or `$global:`.
- **Testability** — parameterized executors are easier to reason about.

#### Recommended executor
```powershell
$executor = {
    param([string]$RepoPath,[int]$Limit=100)
    Get-ChildItem -LiteralPath $RepoPath -Recurse -File |
      Select-Object -First $Limit |
      ForEach-Object { $_.FullName }
}

Get-ExpressionCache -Key 'repo:files:v1' -ScriptBlock $executor -Arguments @('C:\src\myrepo',200)
```

#### Anti-patterns (avoid)
```powershell
# ❌ Capturing outer vars
$repoPath='C:\src\myrepo'
$executor={ Get-ChildItem -LiteralPath $repoPath -Recurse -File }

# ❌ Using global/script scope
$script:RepoPath='C:\src\myrepo'
$executor={ Get-ChildItem -LiteralPath $script:RepoPath -Recurse -File }
```

#### Practical tips
- Pass time, randomness, or env state as parameters.  
- Return simple, serializable objects.  
- Throw on real failures.  
- Version your keys.  


Pass values via parameters for better cache stability:

```powershell
Get-ExpressionCache -ScriptBlock {
  param($userId, $token)
  Invoke-RestMethod "https://api.example.com/users/$userId" -Headers @{ Authorization = "Bearer $token" }
} -Arguments 42, $token
```

Explicit key control:

```powershell
$key = 'users/42'
Get-ExpressionCache -Key $key -ScriptBlock { param($id,$state) Get-User $id } -Arguments 42, $state
```


## 🧪 Tests

```powershell
# Run all tests (Pester v5+)
pwsh ./tests/run-tests.ps1
```

Tests run on **PowerShell 5.1** and **7.x** via GitHub Actions (Windows + Linux).

The suite covers:
- cache hits/misses
- expiry and version invalidation
- error paths and key stability
- thread safety and concurrent access (PS 7+)
- provider lifecycle (add, remove, config, state)
- locking semantics and lock release on error
- provider state management (atomic and non-atomic)

## Project layout

```
src/
  ExpressionCache.psd1
  ExpressionCache.psm1
  Public/
    *.ps1               # Exported functions
  Providers/
    LocalFileSystem.ps1
    RedisCache.ps1
  Utilities/
    *.ps1
tests/
  Add-ExpressionCacheProvider.Tests.ps1
  Get-ExpressionCache.Tests.ps1
  Get-ExpressionCacheProvider.Tests.ps1
  ProviderStateAndConfig.Tests.ps1
  Remove-ExpressionCacheProvider.Tests.ps1
  Set-ProviderConfig.Tests.ps1
  Set-ProviderStateValues.Tests.ps1
  With-ProviderLock.Tests.ps1
  support/
    Common.ps1
  run-tests.ps1
```

## ✨ Design highlights

- **Ease of use:** cache results from any expression with minimal config.  
- **Single source of truth:** provider settings live in `Config`.  
- **Explicit execution:** call sites pass a scriptblock; providers choose how to cache.  
- **Thread-safe:** ReaderWriterLockSlim for provider state, per-key SemaphoreSlim gates for single-flight cache operations.  
- **Safety:** avoids `Invoke-Expression`; favors parameters over ambient variables.  
- **Extensible:** add providers (Redis, S3, memory, …) by implementing `GetOrCreate`.

## Extensibility

ExpressionCache is designed to be **provider-agnostic**. You can add new providers for any storage backend with minimal effort.

1. Create a provider object with:
   - `Name`, `Description`, `Version`
   - `Config` (settings like paths, TTL, version tags)
   - `GetOrCreate` (required)
   - `Initialize` (optional)
   - `ClearCache` (optional but recommended)

2. Implement the provider functions (see [Provider Function Contracts](#provider-function-contracts)):
   - `Initialize-<ProviderType>` — setup and validate config
   - `GetOrCreate` — return or compute/persist values
   - `Clear-<ProviderType>-Cache` — clear entries safely

3. Register:
```powershell
Add-ExpressionCacheProvider -Provider $myProvider
```

4. Use:
```powershell
Get-ExpressionCache -ProviderName $myProvider.Name -ScriptBlock { ... }
```

Providers included:
- **LocalFileSystemCache** – file-based, zero dependencies
- **RedisCache** – native RESP protocol, zero dependencies, reference implementation for remote/shared caching

Potential extensions:
- In-memory cache (see `samples/implementing-yourown-provider/`)
- Cloud-backed (S3, Azure Blob)
- Database-backed (SQL, SQLite)

## Community & Show and Tell

We’d love to see how you’re using ExpressionCache in your own projects!  
Visit our [GitHub Discussions](https://github.com/gmcnickle/ExpressionCache/discussions) and share:

- Interesting caching scenarios you’ve solved  
- Creative providers (custom backends)  
- Integration into developer workflows (CI/CD, data collection, API batching, etc.)  

Your use case might inspire the next feature or best practice.

## Contributing

Contributions are welcome! Whether it’s a bug fix, a new provider, or an idea for improvement:

1. Fork the repo and create your branch from main.

2. Add tests for new features or fixes (we use Pester v5+).

3. Run the test suite locally with ./tests/run-tests.ps1.

4. Submit a pull request with a clear description of the changes.

Please follow the existing coding style and structure (functions in src/, tests in tests/).
For larger features, consider opening a Discussion first to align on direction.

## Licensing

- **Code**: All source code files (e.g., .ps1, .py) in this repository are licensed under the [MIT License](LICENSE.md). If you use these scripts, a shout-out to [Gary McNickle](https://github.com/gmcnickle) and this repository is appreciated but not required.
- **Non-Code Content**: All documentation, images, and written content (e.g., .md, .jpg, .txt) are licensed under the [Creative Commons Attribution 4.0 International Public License](LICENSE-CC-BY.md). Please attribute as: "© Gary McNickle 2025, licensed under CC BY 4.0 International" with a link to [https://creativecommons.org/licenses/by/4.0/](https://creativecommons.org/licenses/by/4.0/).
- **Other Files**: Any files not explicitly categorized (e.g., .json, .yml) are licensed under CC BY 4.0 unless otherwise noted.
- **Contributions**: By contributing to this repository, you agree to license your code under the MIT License and non-code contributions under CC BY 4.0.

## Credits

**Primary Author:** Gary McNickle ([gmcnickle@outlook.com](mailto:gmcnickle@outlook.com))  
**Co-Author & Assistant:** ChatGPT (OpenAI)  

This script was collaboratively designed and developed through interactive sessions with ChatGPT, combining human experience and AI-driven support to solve real-world development challenges.


<p align="center">
  <a href="https://github.com/gmcnickle">
    <img alt="GitHub" src="https://img.shields.io/badge/GitHub-%40gmcnickle-181717?style=flat-square&logo=github">
  </a>
  <a href="https://www.linkedin.com/in/gmcnickle">
    <img alt="LinkedIn" src="https://img.shields.io/badge/LinkedIn-Gary%20McNickle-0A66C2?style=flat-square&logo=linkedin&logoColor=white">
  </a>
  <a href="https://orcid.org/0009-0002-7161-0992">
    <img alt="ORCID" src="https://img.shields.io/badge/ORCID-0009--0002--7161--0992-A6CE39?style=flat-square&logo=orcid">
  </a>
  <a href="https://roguecivilian.org">
    <img alt="RogueCivilian" src="https://img.shields.io/badge/RogueCivilian-Articles%20%26%20Projects-552B75?style=flat-square">
  </a>
</p>
