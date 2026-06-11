# Changelog
All notable changes to **ExpressionCache** will be documented in this file.  
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-06-11
### Added
- Cross-process single-flight coordination for `LocalFileSystemCache`, preventing duplicate computation when multiple processes miss the same key concurrently.
- Distributed per-key locking for Redis cache misses.
- Optional Redis provider settings:
  - `WaitSeconds` controls how long a caller waits for another worker computing the same key.
  - `LockSeconds` controls the distributed lock lifetime for long-running computations.
- Redis concurrency tests covering lock acquisition, token-safe release, and client lease synchronization.

### Changed
- Prepared the public contract for 1.0:
  - Provider hooks are command-name strings with canonical `Initialize`, `GetOrCreate`, `ClearCache`, and `Teardown` properties.
  - `GetOrCreate` commands must declare `Key` and `ScriptBlock`; `ProviderName`, `Arguments`, `Policy`, and `CacheVersion` are standard optional inputs.
  - `With-ProviderLock` was renamed to `Invoke-ProviderLockedOperation`.
  - `ProviderName` is the canonical parameter name, with `Name` retained as an alias.
  - Missing provider lookups now use the PowerShell error stream and support common `-ErrorAction` behavior.
  - Module exports are explicitly listed in the manifest.
  - The automatic cache-key algorithm is treated as stable throughout the 1.x release line.
- Redis access using a shared provider client is synchronized for connection safety.
- Provider state reads and writes now participate consistently in provider locking.
- Local filesystem cache replacement is atomic during concurrent writes.
- The default Redis namespace changes from `v0` to `v1` when the module version advances to 1.0.

### Fixed
- Concurrent cache misses across runspaces or processes could execute the same expression more than once.
- Redis distributed locks now use the intended namespaced cache key instead of an empty key.
- Provider lock operations no longer shadow a caller's `$ScriptBlock` variable.
- Automatic cache keys now use OS-independent argument serialization.
- Internal provider lookup now works consistently under Windows PowerShell 5.1.
- Local filesystem cache writes could briefly remove the destination before replacing it.

## [0.3.1] - 2026-04-16
### Fixed
- Thread safety: `$script:__ParamCache` changed from plain hashtable to `ConcurrentDictionary` to prevent corruption under concurrent access.
- Thread safety: `Get-ProviderLock` rewritten with `Monitor`-based double-checked locking to fix TOCTOU race on lock initialization.
- Thread safety: wrapped unprotected reads of `$script:RegisteredStorageProviders` and `$script:Config` in `With-ReadLock`.

### Changed
- Removed duplicate `Build-CallableSplat.ps1` and `Build-SplatFromConfig.ps1` (identical copies of `New-CallableSplat.ps1` and `New-SplatFromConfig.ps1`).

### Added
- Smoke test for InMemoryCache sample (`InMemoryCache.Sample.Tests.ps1`).

## [0.3.0] - 2026-04-15
### Breaking Changes
- Redis provider: config key renamed from `Host` to `HostAddress` to match the `New-RedisClient` parameter name.
- Redis provider: default password changed from `'ChangeThisPassword!'` to `''` (empty). Set `$env:EXPRCACHE_REDIS_PASSWORD` or pass `Password` explicitly in config.

### Added
- **Thread safety**: `ReaderWriterLockSlim` for provider state, per-key `SemaphoreSlim` gates for single-flight cache operations.
- **PowerShell 5.1 compatibility**: replaced all `[type]::new()` calls with `New-Object`; added `Invoke-ParallelRunspace` helper for PS 5.1 concurrent tests.
- **Test coverage**: added test suites for `Get-ExpressionCacheProvider`, `Remove-ExpressionCacheProvider`, `Set-ProviderConfig`, `Set-ProviderStateValues`, `With-ProviderLock`, `ProviderStateAndConfig`, and `ConfigMerge` (7 new test files, 87 total tests).
- **Redis test infrastructure**: auto-detection of Redis via Docker or local `redis-cli`, isolated test prefix per run, skip logic for environments without Redis.
- Configurable `JsonDepth` with truncation warnings for deep object graphs.

### Fixed
- `Test-ExpressionCacheProviderSpec`: relaxed missing-command check from throw to warning, fixing cross-scope compatibility for custom providers defined outside the module.
- `Merge-ObjectDeep`: fixed `-or` to `-and` for map type check; array-wrapped `.Keys` to prevent enumeration bugs.
- `Get-FromLocalFileSystem`: added `-ErrorAction Stop` to `Get-Item` so TOCTOU race is caught by the existing `try/catch` (PS 5.1 non-terminating error fix).
- InMemoryCache sample: fixed module scope isolation — dot-source provider, use `global:` function prefix so ExpressionCache can invoke custom provider functions.
- Redis provider: removed duplicate `Get-RedisClient` function that shadowed the client initializer (caused by `Ensure-RedisClient` rename collision).
- Redis provider: fixed `Use-RedisClient` leaking the client object into the pipeline.
- Redis provider: suppressed unwanted output from lazy client initialization.
- `Initialize-ExpressionCache`: fixed output leaking to pipeline.
- Naming inconsistencies across module (standardized to PowerShell approved verbs where possible).
- Temp file cleanup in `LocalFileSystem` provider.
- Thread safety: `$script:__ParamCache` changed from plain hashtable to `ConcurrentDictionary` to prevent corruption under concurrent access.
- Thread safety: `Get-ProviderLock` rewritten with `Monitor`-based double-checked locking to fix TOCTOU race on lock initialization.
- Thread safety: wrapped unprotected reads of `$script:RegisteredStorageProviders` and `$script:Config` in `With-ReadLock`.

### Changed
- Redis provider documentation rewritten to accurately reflect capabilities (native RESP protocol, thread-safe init, sliding TTL, SCAN-based clearing, envelope serialization with gzip).

## [0.2.0] - 2025-08-21
### Breaking Changes
- Changed provider descriptors from `PSCustomObject` to **ordered hashtables**.  
  Providers must now return a hashtable spec.

### Added
- New sample: `InMemoryCache.Sample.ps1` showing custom provider registration and cache usage.
- Support for `EXPRCACHE_DEFAULT_PROVIDER` environment override.
- Defered client initialization during Redis provider init

### Fixed
- Cache policy: bug where a 1-day default TTL resolved to 1 second.  
  Clarified precedence (`MaxAge > ExpireAtUtc > SlidingAge`), safer null handling, enforced 1-second minimum.
- Redis provider: added test-safe prefix overrides and reset hooks; improved parity with LocalFileSystem provider.
- Module polish: corrected exported functions, improved error messages, and more reliable test isolation.

## [0.1.2] - 2025-08-10
### Fixed
- Manifest and packaging issues for initial publish.

## [0.1.1] - 2025-08-08
### Added
- Initial publish to PowerShell Gallery.
