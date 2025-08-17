class CachePolicy {
    [string]   $Mode         # 'MaxAge' | 'Absolute' | 'Sliding'
    [int]      $TtlSeconds
    [datetime] $ExpireAtUtc  # UTC
    [bool]     $Sliding
}


<#
.SYNOPSIS
Resolves an effective cache policy from caller options or provider defaults.

.DESCRIPTION
Resolve-CachePolicy determines the cache expiration policy to use, applying a clear precedence and
sane minimums. It returns a [CachePolicy] object with:
- Mode        : 'MaxAge' | 'Absolute' | 'Sliding'
- TtlSeconds  : integer TTL (minimum 1 second)
- ExpireAtUtc : absolute expiration in UTC
- Sliding     : $true only for sliding policies

Precedence (first present wins):
  1) -MaxAge        → TTL-based (“stale if older than…”)
  2) -ExpireAtUtc   → absolute expiry at a specific UTC moment
  3) -SlidingAge    → sliding TTL (renews on access; providers may refresh ExpireAtUtc)
If none of the above are provided:
  4) -DefaultPolicy (used as-is)
  5) -DefaultMaxAge (converted to MaxAge)
  6) Fallback = 5 minutes (MaxAge)

Null semantics (when a parameter is *present* but $null):
- -MaxAge $null      → treat as TTL = 1 second (minimal nonzero)
- -ExpireAtUtc $null → expire ~now + 1 second
- -SlidingAge $null  → TTL = 1 second, Sliding = $true

Safety:
- TTLs ≤ 0 are coerced to 1 second.
- ExpireAtUtc is normalized to UTC; past times become TTL = 1 second.

.PARAMETER MaxAge
Optional TimeSpan for TTL-style freshness. If present, overrides all other options.
When $null, a minimal TTL of 1 second is used.

.PARAMETER ExpireAtUtc
Optional DateTime (interpreted/converted to UTC) for absolute expiration. If present, used unless
-MaxAge is also present. If passed as $null, expires ~now + 1 second.

.PARAMETER SlidingAge
Optional TimeSpan for sliding expiration (renews on access). If present, used unless -MaxAge or
-ExpireAtUtc is present. When $null, TTL = 1 second, Sliding = $true.

.PARAMETER DefaultPolicy
Optional precomputed [CachePolicy] to use when caller did not specify MaxAge/ExpireAtUtc/SlidingAge.

.PARAMETER DefaultMaxAge
Optional TimeSpan used as a fallback TTL when no caller choice and no DefaultPolicy are supplied.

.OUTPUTS
CachePolicy

.EXAMPLE
# Caller chooses MaxAge (10 minutes). Overrides everything else.
Resolve-CachePolicy -MaxAge (New-TimeSpan -Minutes 10)

.EXAMPLE
# Absolute expiration at midnight UTC tonight.
$midnight = [DateTime]::UtcNow.Date.AddDays(1)
Resolve-CachePolicy -ExpireAtUtc $midnight

.EXAMPLE
# Sliding expiration (2 minutes). Providers should refresh on access.
Resolve-CachePolicy -SlidingAge (New-TimeSpan -Minutes 2)

.EXAMPLE
# Nothing specified by caller → use provider's default policy as-is.
$default = [CachePolicy]@{ Mode='MaxAge'; TtlSeconds=300; ExpireAtUtc=[DateTime]::UtcNow.AddMinutes(5); Sliding=$false }
Resolve-CachePolicy -DefaultPolicy $default

.EXAMPLE
# No caller choice, no DefaultPolicy → use DefaultMaxAge (1 hour).
Resolve-CachePolicy -DefaultMaxAge (New-TimeSpan -Hours 1)

.EXAMPLE
# Edge case: present but null → minimal nonzero TTL (1 second).
Resolve-CachePolicy -MaxAge $null

.NOTES
- Providers can use TtlSeconds directly (e.g., as Redis TTL) and may treat Sliding=$true to refresh
  expiry on access. ExpireAtUtc is computed for convenience; providers may prefer TtlSeconds.
- All DateTimes are normalized to UTC.
#>
function Resolve-CachePolicy {
    [CmdletBinding()]
    [OutputType([CachePolicy])]
    param(
        # Caller-specified (optional). Keep them nullable so callers can omit them without prompts.
        [Nullable[TimeSpan]] $MaxAge,
        [Nullable[datetime]] $ExpireAtUtc,
        [Nullable[TimeSpan]] $SlidingAge,

        # Provider defaults (optional)
        [CachePolicy]        $DefaultPolicy,
        [Nullable[TimeSpan]] $DefaultMaxAge
    )

    $nowUtc = (Get-Date).ToUniversalTime()

    # 1) Precedence: MaxAge > ExpireAtUtc > SlidingAge
    if ($PSBoundParameters.ContainsKey('MaxAge')) {
        $ttl = 1
        if ($null -ne $MaxAge) {
            $ttl = [int][Math]::Ceiling([double]$MaxAge.Value.TotalSeconds)
            if ($ttl -le 0) { $ttl = 1 }
        }
        return [CachePolicy]@{
            Mode        = 'MaxAge'
            TtlSeconds  = $ttl
            ExpireAtUtc = $nowUtc.AddSeconds($ttl)
            Sliding     = $false
        }
    }

    if ($PSBoundParameters.ContainsKey('ExpireAtUtc')) {
        $abs = if ($null -ne $ExpireAtUtc) { $ExpireAtUtc.Value.ToUniversalTime() } else { $nowUtc.AddSeconds(1) }
        $ttl = [int][Math]::Ceiling(([double]($abs - $nowUtc).TotalSeconds))
        if ($ttl -le 0) { $ttl = 1 }
        return [CachePolicy]@{
            Mode        = 'Absolute'
            TtlSeconds  = $ttl
            ExpireAtUtc = $abs
            Sliding     = $false
        }
    }

    if ($PSBoundParameters.ContainsKey('SlidingAge')) {
        $ttl = 1
        if ($null -ne $SlidingAge) {
            $ttl = [int][Math]::Ceiling([double]$SlidingAge.Value.TotalSeconds)
            if ($ttl -le 0) { $ttl = 1 }
        }
        return [CachePolicy]@{
            Mode        = 'Sliding'
            TtlSeconds  = $ttl
            ExpireAtUtc = $nowUtc.AddSeconds($ttl)
            Sliding     = $true
        }
    }

    # 2) No caller choice → provider defaults
    if ($null -ne $DefaultPolicy) { return $DefaultPolicy }

    if ($PSBoundParameters.ContainsKey('DefaultMaxAge') -and $null -ne $DefaultMaxAge) {
        $ttl = [int][Math]::Ceiling([double]$DefaultMaxAge.Value.TotalSeconds)
        if ($ttl -le 0) { $ttl = 1 }
        return [CachePolicy]@{
            Mode        = 'MaxAge'
            TtlSeconds  = $ttl
            ExpireAtUtc = $nowUtc.AddSeconds($ttl)
            Sliding     = $false
        }
    }

    # 3) Library-wide fallback (5 minutes)
    $fallback = [TimeSpan]::FromMinutes(5)
    $ttl2 = [int][Math]::Ceiling([double]$fallback.TotalSeconds)
    [CachePolicy]@{
        Mode        = 'MaxAge'
        TtlSeconds  = $ttl2
        ExpireAtUtc = $nowUtc.AddSeconds($ttl2)
        Sliding     = $false
    }
}
