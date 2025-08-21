    <#
.SYNOPSIS
Validates a single ExpressionCache provider spec and normalizes it to a hashtable.

.DESCRIPTION
Enforces the strict provider descriptor contract used by Initialize-ExpressionCache:
- Spec must include Name (string), GetOrCreate (string or scriptblock), and Config (hashtable/IDictionary).
- Optional Initialize and Clear must be a function name (string) or a scriptblock if present.
- Function-name strings are validated with Get-Command -Name <string>.
- Returns a normalized **hashtable** (not PSCustomObject).

.PARAMETER Spec
Provider descriptor to validate. Accepts hashtable, ordered hashtable, or PSCustomObject.

.OUTPUTS
[hashtable]
A normalized provider spec (Name, GetOrCreate, [Initialize], [ClearCache], Config as hashtable).

.EXAMPLE
$spec = @{
  Name        = 'InMemoryCache'
  GetOrCreate = 'Get-InMemory-CachedValue'
  Initialize  = 'Initialize-InMemoryCache'
  ClearCache  = 'Clear-InMemory-Cache'
  Config      = @{ DefaultMaxAge = (New-TimeSpan -Minutes 10) }
}
$valid = Test-ExpressionCacheProviderSpec -Spec $spec
#>
function Test-ExpressionCacheProviderSpec {
    param([Parameter(Mandatory)][object]$Spec)

    function ConvertTo-Hashtable {
        param([Parameter(Mandatory)][object]$InputObject)

        # Handle accidental arrays (caused by stray outputs upstream)
        if ($InputObject -is [array]) {
            # Pick the single spec-like object if present
            $candidates = $InputObject | Where-Object {
                $_ -is [System.Collections.IDictionary] -or $_ -is [pscustomobject]
            }
            if ($candidates.Count -eq 1) {
                $InputObject = $candidates[0]
            } else {
                $types = ($InputObject | ForEach-Object { $_.GetType().FullName }) -join ', '
                throw "ExpressionCache: Provider spec must be a hashtable/IDictionary or PSCustomObject. Got array: $types"
            }
        }

        if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject }
        if ($InputObject -is [pscustomobject]) {
            $ht = @{}
            foreach ($p in $InputObject.PSObject.Properties) { $ht[$p.Name] = $p.Value }
            return $ht
        }
        throw "ExpressionCache: Provider spec must be a hashtable/IDictionary or PSCustomObject. Got: $($InputObject.GetType().FullName)"
    }

    function Ensure-Functor {
        param(
            [Parameter(Mandatory)][object]$Value,
            [Parameter(Mandatory)][string]$PropName,
            [Parameter(Mandatory)][string]$ProviderName
        )
        if ($Value -is [scriptblock]) { return }  # silent success

        if ($Value -is [string]) {
            if ([string]::IsNullOrWhiteSpace($Value)) {
                throw "ExpressionCache: Provider '$ProviderName': '$PropName' cannot be empty."
            }
            # Verify function exists; discard output to stay silent
            $null = Get-Command -Name $Value -ErrorAction SilentlyContinue
            if (-not $?) {
                throw "ExpressionCache: Provider '$ProviderName': command '$Value' (from '$PropName') not found."
            }
            return  # silent success
        }

        throw "ExpressionCache: Provider '$ProviderName': '$PropName' must be a function name (string) or a scriptblock. Got: $($Value.GetType().FullName)"
    }

    # Normalize to plain hashtable (and strip accidental array wrappers)
    $specHt = ConvertTo-Hashtable $Spec

    foreach ($req in 'Name','GetOrCreate','Config') {
        if (-not ($specHt.Keys -contains $req) -or -not $specHt[$req]) {
            throw "ExpressionCache: Provider spec missing required property '$req'."
        }
    }

    if ($specHt['Name'] -isnot [string] -or [string]::IsNullOrWhiteSpace($specHt['Name'])) {
        throw "ExpressionCache: Provider 'Name' must be a non-empty string."
    }
    $name = [string]$specHt['Name']

    # Validate functors (silent on success)
    Ensure-Functor -Value $specHt['GetOrCreate'] -PropName 'GetOrCreate' -ProviderName $name
    foreach ($opt in 'Initialize','Clear') {
        if ($specHt.Keys -contains $opt -and $null -ne $specHt[$opt]) {
            Ensure-Functor -Value $specHt[$opt] -PropName $opt -ProviderName $name
        }
    }

    # Config -> hashtable (and handle PSCO)
    $cfg = $specHt['Config']
    if ($cfg -isnot [System.Collections.IDictionary] -and $cfg -isnot [pscustomobject]) {
        throw "ExpressionCache: Provider '$name': Config must be a hashtable or PSCustomObject."
    }
    $specHt['Config'] = ConvertTo-Hashtable $cfg

    return $specHt   # only output; no stray $true’s
}
