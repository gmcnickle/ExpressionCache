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

    Test-Directory $CacheFolder
}

function Clear-LocalFileSystem-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProviderName,
        [switch]$Force
    )

    $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName
    $folder = $provider.Config.CacheFolder

    if (-not $folder) { 
        return 
    }

    # Block same-process readers/writers while clearing
    With-ProviderLock $provider {
        if (Test-Path -LiteralPath $folder) {
            Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
        }
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
        [string]$CacheVersion,

        [int]$JsonDepth = 10
    )

    if ($null -eq $Data -or (($Data -is [System.Collections.ICollection]) -and $Data.Count -eq 0)) { 
        return 
    }

    $cacheFile = [IO.Path]::Combine($CacheFolder, "$Key.txt")

    if ($PSCmdlet.ShouldProcess($cacheFile, 'Write cache entry')) {
        $payload = [pscustomobject]@{
            Version = $CacheVersion
            Query   = $Query
            Data    = $Data
        }

        Write-JsonFileAtomically -Path $cacheFile -Object $payload -JsonDepth $JsonDepth
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
        [string]$CacheVersion,

        [Parameter(Mandatory)]
        [CachePolicy]$Policy
    )

    $cacheFile = [IO.Path]::Combine($CacheFolder, "$Key.txt")

    if (-not (Test-Path -LiteralPath $cacheFile)) { 
        return $null 
    }

    # Avoid TOCTOU by handling races in try/catch
    try {
        $item = Get-Item -LiteralPath $cacheFile -Force -ErrorAction Stop
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

            return $null
        }

        $cacheContent = Read-JsonFileWithRetries -Path $cacheFile

        if ($cacheContent.Version -ne $CacheVersion) {
            Write-Verbose "LocalFileSystemCache: version mismatch: expected $CacheVersion, got $($cacheContent.Version)"

            return $null
        }

        if ($Policy.Sliding) {
            try { 
                [IO.File]::SetLastWriteTimeUtc($cacheFile, (Get-Date).ToUniversalTime()) 
            }
            catch { 

            }
        }

        return $cacheContent.Data
    }
    catch {
        Write-Warning "LocalFileSystemCache: failed to read/parse cache file: $cacheFile ($($_.Exception.Message))"
        return $null
    }
}

function Get-LocalFileSystem-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$ProviderName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [object[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$CacheFolder,

        [Parameter(Mandatory)]
        [CachePolicy]$Policy,

        [Parameter(Mandatory)]
        [string]$CacheVersion,

        [int]$WaitSeconds = 10,

        [int]$JsonDepth = 10
    )

    $response = Get-FromLocalFileSystem -Key $Key -CacheFolder $CacheFolder -CacheVersion $CacheVersion -Policy $Policy
    if ($null -ne $response) { 
        Write-Verbose "LocalFileSystemCache: Retrieved from cache: $Key"; return $response 
    }

    # Single-flight gate for this key (avoid duplicate compute+writes)
    $gateKey = "lfs::$CacheFolder::$Key"
    $gate = Get-KeyGate -Key $gateKey
    $ts = [TimeSpan]::FromSeconds([Math]::Max(1, $WaitSeconds))

    if (-not $gate.Wait($ts)) { 
        throw "Timeout acquiring cache gate for '$Key' after $WaitSeconds s." 
    }

    try {
        # Re-check after acquiring the gate (another thread may have populated it)
        $response = Get-FromLocalFileSystem -Key $Key -CacheFolder $CacheFolder -CacheVersion $CacheVersion -Policy $Policy
        if ($null -ne $response) { 
            return $response 
        }

        # MISS → compute
        if ($null -eq $Arguments) { $Arguments = @() }
        $response = & $ScriptBlock @Arguments

        if ($null -eq $response) {
            Write-Verbose "LocalFileSystemCache: Computed null; skipping write for: $Key"

            return $null
        }

        $desc = ($ScriptBlock.ToString() -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' '
        Update-LocalFileSystem-Cache -Key $Key -Data $response -Query $desc -CacheFolder $CacheFolder -CacheVersion $CacheVersion -JsonDepth $JsonDepth

        return $response
    }
    finally {
        $gate.Release() | Out-Null
    }
}

function Test-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    [void][IO.Directory]::CreateDirectory($Path)
}

# Write JSON atomically: temp -> (replace|move)
function Write-JsonFileAtomically {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $Object,

        [int]$JsonDepth = 10
    )

    $dir = Split-Path -Parent $Path
    Test-Directory $dir

    $json = $Object | ConvertTo-Json -Depth $JsonDepth
    if ($json -match '"System\.[^"]+"') {
        Write-Warning "ExpressionCache: ConvertTo-Json may have truncated objects at depth $JsonDepth. Consider increasing JsonDepth in provider config."
    }
    $tmp = Join-Path $dir (".tmp_{0}_{1}.json" -f $PID, [Guid]::NewGuid().ToString('N'))

    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))

    # Atomic overwrite (or create) with retry for cross-process contention
    $maxRetries = 3
    for ($attempt = 0; $attempt -le $maxRetries; $attempt++) {
        try {
            # .NET Framework (PS 5.1) File.Move lacks overwrite param; delete first
            if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
            [IO.File]::Move($tmp, $Path)
            return
        }
        catch [System.IO.IOException], [System.UnauthorizedAccessException] {
            if ($attempt -eq $maxRetries) {
                # Clean up orphaned temp file before re-throwing
                if ([IO.File]::Exists($tmp)) {
                    try { [IO.File]::Delete($tmp) } catch { }
                }
                throw
            }
            [System.Threading.Thread]::Sleep(25 * ($attempt + 1))
        }
    }
}

function Read-JsonFileWithRetries {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$Retries = 3,

        [int]$DelayMs = 25
    )
    for ($i = 0; $i -le $Retries; $i++) {
        try {
            $raw = [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false)))
            return $raw | ConvertFrom-Json
        } 
        catch [System.IO.FileNotFoundException] {
            if ($i -eq $Retries) { 
                throw 
            }
            Start-Sleep -Milliseconds $DelayMs

        } 
        catch [System.IO.IOException] {
            if ($i -eq $Retries) { 
                throw 
            }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}
