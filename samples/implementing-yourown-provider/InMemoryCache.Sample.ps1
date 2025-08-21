# InMemoryCache.Sample.ps1
# Requires:
#   - ExpressionCache module available (e.g., installed from PSGallery or in repo)
#   - InMemoryCache.Provider.ps1 in the same folder

Import-Module ExpressionCache -Force
Import-Module (Join-Path $PSScriptRoot "InMemoryCache.Provider.ps1") -Force

function Invoke-Main {
    [CmdletBinding()]
    param(
        [switch]$SoleProvider,
        [TimeSpan]$DefaultTtl   = ([TimeSpan]::FromMinutes(10)),
        [TimeSpan]$CallMaxAge   = ([TimeSpan]::FromMinutes(5)),
        [string]$ProviderName   = "InMemoryCache"
    )

    # Remember existing default provider so we can restore it
    $previousDefault = $env:EXPRCACHE_DEFAULT_PROVIDER

    try {
        # 1) Build provider spec (hashtable) from our helper
        $inMemSpec = [ordered]@{
            InMemoryCache = (New-InMemoryCacheProvider -Name $ProviderName -Prefix 'Sample' -DefaultTtl $DefaultTtl)
        }

        # 2) Initialize ExpressionCache and register our provider
        $providers = Initialize-ExpressionCache -Providers $inMemSpec -AppName "InMemoryCache.Sample" -ReplaceProviders:$SoleProvider

        # 3) Sanity check: ensure our provider is present
        $registered = $providers.Values | Where-Object { $_.Name -eq $ProviderName }
        if (-not $registered) {
            throw "Provider '$ProviderName' was not registered. Initialization failed."
        }

        # 4) Use our provider by default for this script’s lifetime
        $env:EXPRCACHE_DEFAULT_PROVIDER = $ProviderName

        # 5) Demo: compute-once then read-from-cache
        $exec = @{ Count = 0 }
        
        $sb = {
            param($x, $y)
            $exec.Count++
            return $x + $y
        }.GetNewClosure()

        Write-Host "Calling Get-ExpressionCache (expected MISS → compute)..." -ForegroundColor Yellow
        $result1 = Get-ExpressionCache -MaxAge $CallMaxAge -ScriptBlock $sb -Arguments 1, 2
        Write-Host "Result: $result1 ; Exec.Count: $($exec.Count)"

        Write-Host "Calling Get-ExpressionCache again (expected HIT → cached)..." -ForegroundColor Yellow
        $result2 = Get-ExpressionCache -MaxAge $CallMaxAge -ScriptBlock $sb -Arguments 1, 2
        Write-Host "Result: $result2 ; Exec.Count: $($exec.Count)"

        if ($result1 -ne 3 -or $result2 -ne 3) {
            throw "Unexpected result(s) from cache demo. Got [$result1, $result2], expected [3, 3]."
        }
        if ($exec.Count -ne 1) {
            throw "Script block executed $($exec.Count)x; expected 1 (second call should be cached)."
        }

        Write-Host "✅ Cache demo succeeded using provider '$ProviderName'." -ForegroundColor Green

        # Optional: quick TTL proof (set very short MaxAge to force recompute)
        # Write-Host "TTL check (1 second)..." -ForegroundColor Yellow
        # $short = [TimeSpan]::FromSeconds(1)
        # $null = Get-ExpressionCache -MaxAge $short -ScriptBlock $sb -Arguments 1, 2
        # Start-Sleep -Seconds 2
        # $null = Get-ExpressionCache -MaxAge $short -ScriptBlock $sb -Arguments 1, 2
        # if ($exec.Count -lt 2) { throw "Expected recompute after TTL expiry." }
        # Write-Host "TTL expiry verified. Exec.Count: $($exec.Count)"

    }
    finally {
        # 6) Restore previous default provider to avoid session bleed
        if ($null -ne $previousDefault) {
            $env:EXPRCACHE_DEFAULT_PROVIDER = $previousDefault
        } else {
            Remove-Item Env:\EXPRCACHE_DEFAULT_PROVIDER -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Main @PSBoundParameters
