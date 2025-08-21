function Clear-LocalFileSystem-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProviderName,
        [switch]$Force
    )

    $prov = Get-ExpressionCacheProvider -ProviderName $ProviderName
    $folder = $prov.Config.CacheFolder

    if ($folder -and (Test-Path -LiteralPath $folder)) {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
  
}

function Update-LocalFileSystem-Cache {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter(Mandatory)]
        [string]$CacheFolder,

        [Parameter(Mandatory)]
        [string]$CacheVersion
    )

    if ($null -eq $Data -or (($Data -is [System.Collections.ICollection]) -and $Data.Count -eq 0)) { 
        return 
    }

    $cacheFile = [IO.Path]::Combine($CacheFolder, "$Key.txt")
    $cacheDir = Split-Path -Path $cacheFile -Parent

    # Ensure directory exists (gated by ShouldProcess)
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        if ($PSCmdlet.ShouldProcess($cacheDir, 'Create cache directory')) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }
    }

    if ($PSCmdlet.ShouldProcess($cacheFile, 'Write cache entry')) {
        $cacheResult = [pscustomobject]@{
            Version = $CacheVersion
            Query   = $Query
            Data    = $Data
        }
        $cacheResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheFile -Force
    }
}

function Get-FromLocalFileSystem {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$CacheFolder,
        [Parameter(Mandatory)][string]$CacheVersion,
        [Parameter(Mandatory)][CachePolicy]$Policy
    )

    $cacheFile = [IO.Path]::Combine($CacheFolder, "$Key.txt")
    if (-not (Test-Path -LiteralPath $cacheFile)) { return $null }

    $item = Get-Item -LiteralPath $cacheFile -Force
    $lastWriteUtc = $item.LastWriteTimeUtc
    $nowUtc = (Get-Date).ToUniversalTime()

    $isFresh = switch ($Policy.Mode) {
        'Absolute' { $nowUtc -le $Policy.ExpireAtUtc }
        'Sliding' { ($nowUtc - $lastWriteUtc) -le [TimeSpan]::FromSeconds($Policy.TtlSeconds) }
        default { ($nowUtc - $lastWriteUtc) -le [TimeSpan]::FromSeconds($Policy.TtlSeconds) }
    }

    if (-not $isFresh) {
        if ($PSCmdlet.ShouldProcess($cacheFile, "Remove expired cache")) {
            Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
        }
        Write-Verbose "ExpressionCache: $cacheFile deleted (expired)."
        return $null
    }

    try {
        $cacheContent = Get-Content -Raw -LiteralPath $cacheFile | ConvertFrom-Json
        if ($cacheContent.Version -ne $CacheVersion) {
            Write-Verbose "LocalFileSystemCache: version mismatch: expected $CacheVersion, got $($cacheContent.Version)"
            return $null
        }

        # Sliding: refresh 'last write' timestamp on hit
        if ($Policy.Sliding) {
            [IO.File]::SetLastWriteTimeUtc($cacheFile, (Get-Date).ToUniversalTime())
        }

        return $cacheContent.Data
    }
    catch {
        Write-Warning "LocalFileSystemCache: failed to read/parse cache file: $cacheFile"
        return $null
    }
}

function Get-LocalFileSystem-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,

        [Alias('ArgumentList')]
        [object[]]$Arguments,

        [Parameter(Mandatory)][string]$CacheFolder,
        [Parameter(Mandatory)][CachePolicy]$Policy,   # <- replaces MaximumAge

        [Parameter(Mandatory)][string]$CacheVersion
    )

    # READ (Policy handles MaxAge/Absolute/Sliding in Get-FromLocalFileSystem)
    $response = Get-FromLocalFileSystem -Key $Key -CacheFolder $CacheFolder -CacheVersion $CacheVersion -Policy $Policy

    if ($null -ne $response) {
        Write-Verbose "LocalFileSystemCache: Retrieved from cache: $Key"
        return $response
    }

    # MISS → compute
    $Arguments = if ($Arguments) { $Arguments } else { @() }
    $response = & $ScriptBlock @Arguments

    if ($null -eq $response) {
        Write-Verbose "LocalFileSystemCache: Computed null; skipping write for: $Key"
        return $null
    }

    # Persist new value (policy is enforced on future reads by Get-FromLocalFileSystem)
    $desc = ($ScriptBlock.ToString() -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' '
    Update-LocalFileSystem-Cache -Key $Key -Data $response -Query $desc -CacheFolder $CacheFolder -CacheVersion $CacheVersion

    return $response
}


function Initialize-LocalFileSystem-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CacheFolder,

        [Parameter(Mandatory)] 
        [string]$ProviderName,
        
        [Parameter(Mandatory)]
        [string]$CacheVersion,

        [Parameter(Mandatory)]
        [timespan]$DefaultMaxAge
    )

    if (-not (Test-Path -LiteralPath $CacheFolder)) {
        New-Item -ItemType Directory -Path $CacheFolder -Force | Out-Null
    }

    $null = Get-ExpressionCacheProvider -ProviderName $ProviderName
}
