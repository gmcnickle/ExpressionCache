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
    $cacheDir  = Split-Path -Path $cacheFile -Parent

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
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$CacheFolder,

        [Parameter(Mandatory)]
        [DateTime]$MaximumAge,

        [Parameter(Mandatory)]
        [string]$CacheVersion
    )

    $cacheFile = [IO.Path]::Combine($CacheFolder, "$Key.txt")

    if (-not (Test-Path -LiteralPath $cacheFile)) { 
        return $null 
    }

    $lastModified = (Get-Item -LiteralPath $cacheFile).LastWriteTime  # keep full precision
    
    if ($lastModified -lt $MaximumAge -and (Test-Path $cacheFile)) {

        if ($PSCmdlet.ShouldProcess($cacheFile, "Remove expired cache")) {
            Remove-Item -LiteralPath $cacheFile -Force
        }

        Write-Verbose "ExpressionCache: $($cacheFile) deleted."
        return $null
    }

    try {
        $cacheContent = Get-Content -Raw -LiteralPath $cacheFile | ConvertFrom-Json

        if ($cacheContent.Version -ne $CacheVersion) {
            Write-Verbose "LocalFileSystemCache: Cache version mismatch: expected $CacheVersion, got $($cacheContent.Version)"

            return $null
        }

        return $cacheContent.Data
    }
    catch {
        Write-Warning "LocalFileSystemCache: Failed to read or parse cache file: $cacheFile"

        return $null
    }
}

function Get-LocalFileSystem-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory=$false)]
        [Alias('ArgumentList')]
        [object[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$CacheFolder,

        [Parameter(Mandatory)]
        [DateTime]$MaximumAge,

        [Parameter(Mandatory)][string]
        $CacheVersion
    )

    $response = Get-FromLocalFileSystem -Key $Key -CacheFolder $CacheFolder -MaximumAge $MaximumAge -CacheVersion $CacheVersion

    if ($null -eq $response) {
        # Cache Miss → compute via ScriptBlock
        $Arguments = if ($Arguments) { $Arguments } else { @() }
        $response = & $ScriptBlock @Arguments

        # Persist
        # normalize the ScriptBlock for debugging
        $desc = ($ScriptBlock.ToString() -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' '
        Update-LocalFileSystem-Cache -Key $Key -Data $response -Query $desc -CacheFolder $CacheFolder -CacheVersion $CacheVersion
    } 
    else {
        Write-Verbose "LocalFileSystemCache: Retrieved from cache: $Key"
    }

    return $response
}

function Initialize-LocalFileSystemCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CacheFolder,
        
        [Parameter(Mandatory)]
        [string]$CacheVersion
    )

    if (-not (Test-Path -LiteralPath $CacheFolder)) {
        New-Item -ItemType Directory -Path $CacheFolder -Force | Out-Null
    }
}
