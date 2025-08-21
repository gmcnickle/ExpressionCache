# Changelog
All notable changes to **ExpressionCache** will be documented in this file.  
This project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2025-08-21
### Breaking
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
