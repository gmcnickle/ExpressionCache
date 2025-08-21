# Providers/RedisCacheProvider.Light.ps1

using namespace System.Net.Sockets
using namespace System.Text

$Global:debugRedis = $true
$Global:RedisDebugLog = "$env:LOCALAPPDATA\redis_debug.log"

function Write-RedisLog {
    param([string]$msg)

    if (-not $Global:debugRedis) {
        return
    }
    
    $timestamp = (Get-Date).ToString("HH:mm:ss.fff")
    Add-Content -Path $Global:RedisDebugLog -Value "$timestamp - $msg"
}


# -- Client constructor -------------------------------------------------------
function New-RedisClient {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        $Provider,

        [Parameter(Mandatory)]
        [string]$HostAddress,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Database = 0,

        [string]$Prefix = 'ExpressionCache:v1',

        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($HostAddress)) {
        throw "HostAddress must be a non-empty string."
    }

    $target = "$($HostAddress):$Port (DB=$Database, Prefix='$Prefix')"
    if (-not $PSCmdlet.ShouldProcess($target, "Open Redis connection")) {
        return $null   # honor -WhatIf / declined -Confirm
    }

    $client = $null
    $stream = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $client.NoDelay = $true
        $client.Connect($HostAddress, $Port)
        $stream = $client.GetStream()

        $ctx = [ordered]@{
            Client = $client
            Stream = $stream
            Prefix = $Prefix
            Db     = $Database
            Host   = $HostAddress
            Port   = $Port
        }

        if ($Password) {
            Invoke-RedisRaw -Context $ctx -Arguments @('AUTH', $Password) -Provider $Provider | Out-Null
        }

        if ($Database -gt 0) {
            Invoke-RedisRaw -Context $ctx -Arguments @('SELECT', $Database.ToString()) -Provider $Provider | Out-Null
        }

        $pong = Invoke-RedisRaw -Context $ctx -Arguments @('PING') -Provider $Provider
        if ($pong -ne 'PONG') {
            throw "Redis PING failed: $pong"
        }

        # success -> return the live context
        return [pscustomobject]$ctx
    }
    catch {
        # ensure cleanup on failure
        try { if ($stream) { $stream.Dispose() } } catch {}
        try { if ($client) { $client.Dispose() } } catch {}
        throw
    }
}

# -- Public commands used by provider ----------------------------------------

function Initialize-Redis-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] 
        [string]$ProviderName,
        [Parameter(Mandatory)]
        [timespan]$DefaultMaxAge,
        [string]$HostAddress = '127.0.0.1',
        [int]$Port = 6379,
        [int]$Database = 2,
        [string]$Prefix = 'ExpressionCache:v1',
        [string]$Password = "",
        [bool]$DeferClientCreation = $true
    )

    $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName
   
    if (-not $provider) { 
        throw "Provider '$ProviderName' not found." 
    }

    if ($provider.State.Initialized) {
        # Write-Warning "RedisCache: Provider already initialized."
        
        return
    }

    $state = [PSCustomObject]@{
        Client   = $null
        SyncRoot = [object]::new()
    }
    $null = $provider | Set-ECProperty -Name 'State' -Value $state -DontEnforceType

    if (-not $DeferClientCreation) {
        $client = New-RedisClient -Provider $provider -HostAddress $HostAddress -Port $Port -Database $Database -Password $Password -Prefix $Prefix
        $provider.State.Client = $client
    }
}

function Resolve-RedisClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProviderName
    )

    $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName

    if (-not $provider) { 
        throw "Provider '$ProviderName' not found." 
    }

    $state  = $provider.State
    $client = $state.Client
    $config = $provider.Config

    # Optional: global/env override to disable redis (useful in CI)
    if ($env:EC_DISABLE_REDIS) { 
        return $null, $provider 
    }

    if ($client) { 
        return $client, $provider 
    }

    $defer  = ($config -and $config.ContainsKey('DeferClientCreation') -and [bool]$config['DeferClientCreation'])
    $strict = ($config -and $config.ContainsKey('Strict')              -and [bool]$config['Strict'])

    if (-not $defer) {
        throw "No Redis client initialized for provider '$ProviderName'."
    }

    # Provider-scoped sync object to avoid double-create
    if (-not $state.Sync) { 
        $state | Set-ECProperty -Name 'Sync' -Value (New-Object object) -DontEnforceType 
    }

    lock ($state.Sync) {
        if ($state.Client) { 
            return $state.Client, $provider 
        } # someone else won the race

        if (-not $state.ClientCreationAttempted) {
            $state | Set-ECProperty -Name 'ClientCreationAttempted' -Value $true -DontEnforceType

            try {
                $newClient = New-RedisClient `
                    -Host     $config['Host'] `
                    -Port     $config['Port'] `
                    -Database $config['Database'] `
                    -Prefix   $config['Prefix'] `
                    -Password $config['Password']

                $state | Set-ECProperty -Name 'Client'      -Value $newClient -DontEnforceType
                $state | Set-ECProperty -Name 'Initialized' -Value $true      -DontEnforceType
                $state | Set-ECProperty -Name 'LastError'   -Value $null      -DontEnforceType
            }
            catch {
                $state | Set-ECProperty -Name 'LastError'   -Value $_         -DontEnforceType
                $state | Set-ECProperty -Name 'Initialized' -Value $false     -DontEnforceType

                if ($strict) { 
                    throw 
                }
            }
        }

        return $state.Client, $provider
    }
}

function Get-Redis-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$Arguments,
        [Parameter(Mandatory)][CachePolicy]$Policy
    )

    try {
        Write-RedisLog "=== [ENTRY] Get-Redis-CachedValue ==="
        $client, $provider = Resolve-RedisClient -ProviderName $ProviderName
        $rkey = Join-RedisKey -Client $client -Key $Key

        $raw = Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('GET', $rkey))
        # write-host "Redis GET $rkey"
        if ($null -ne $raw) {
            if ($Policy.Sliding) {
                Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('EXPIRE', $rkey, [string]$Policy.TtlSeconds)) | Out-Null
                Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('EXPIRE', "$rkey:meta", [string]$Policy.TtlSeconds)) | Out-Null
            }
            Write-RedisLog "[CACHE HIT] Key: $rkey"
            return (Read-CacheValue $raw)
        }

        Write-RedisLog "[CACHE MISS] Key: $rkey — computing value"
        if ($null -eq $Arguments) { $Arguments = @() }
        $result = & $ScriptBlock @Arguments
        if ($null -eq $result) { return $null }

        $payload = Write-CacheValue -Value $result

        Invoke-RedisRaw -Provider $provider -Context $client `
            -Arguments ([object[]]@('SET', $rkey, $payload, 'EX', [string]$Policy.TtlSeconds)) | Out-Null

        $desc = ($ScriptBlock.ToString() -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' '
        Invoke-RedisRaw -Provider $provider -Context $client `
            -Arguments ([object[]]@('HSET', "$rkey:meta", 'q', $desc, 'ts', (Get-Date).ToString('o'))) | Out-Null
        Invoke-RedisRaw -Provider $provider -Context $client `
            -Arguments ([object[]]@('EXPIRE', "$rkey:meta", [string]$Policy.TtlSeconds)) | Out-Null

        Write-RedisLog "[CACHE STORE] Key: $rkey"
        return $result
    }
    finally {
        Write-RedisLog "=== [EXIT] Get-Redis-CachedValue ==="
    }
}

function Clear-Redis-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProviderName,
        [switch]$Force
    )

    try {
        Write-RedisLog "=== [ENTRY] Clear-Redis-Cache ==="
        $client, $provider = Resolve-RedisClient -ProviderName $ProviderName
        $pattern = "$($client.Prefix)*"

        $cursor = '0'
        $iterationLimit = 100
        $iteration = 0

        do {
            $resp = Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('SCAN', $cursor, 'MATCH', $pattern, 'COUNT', '1000'))

            if ($resp[0] -is [array]) {
                $nextCursor = [string]$resp[0][0]
            }
            else {
                $nextCursor = [string]$resp[0]
            }

            $keys = $resp[1]

            if ($keys -isnot [array]) { $keys = @($keys) }
            if ($keys.Count -eq 1 -and $keys[0] -is [array]) { $keys = $keys[0] }

            $keys = $keys | Where-Object { $_ -ne '0' }
            Write-RedisLog "[SCAN] Cursor=$cursor -> $nextCursor, KeysReturned=$($keys.Count)"

            if ($keys.Count -gt 0) {
                $chunk = $keys -join ', '
                Write-RedisLog "[UNLINK] Keys: $chunk"
                $cmd = @('UNLINK') + $keys
                Invoke-RedisRaw -Provider $provider -Context $client -Arguments $cmd | Out-Null
            }

            if ($cursor -eq $nextCursor) {
                Write-RedisLog "[WARN] Redis SCAN returned same cursor ($cursor), breaking."
                break
            }

            $cursor = $nextCursor
            $iteration++
        } while ($cursor -ne '0' -and $iteration -lt $iterationLimit)

        if ($iteration -ge $iterationLimit) {
            Write-RedisLog "[ERROR] SCAN exceeded iteration limit ($iterationLimit)."
        }
    }
    finally {
        Write-RedisLog "=== [EXIT] Clear-Redis-Cache ==="
    }
}



# -- Helpers -----------------------------------------------------------------
function Join-RedisKey {
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [object]$Client
    )

    if (-not $client -or [string]::IsNullOrWhiteSpace($client.Prefix)) {
        return $Key
    }

    return "$($client.Prefix):$Key"
}


function Invoke-RedisRaw {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory)] $Context,
        [Parameter(Mandatory)] [object[]]$Arguments,
        [Parameter(Mandatory)] $Provider
    )

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        throw "Invoke-RedisRaw: -Arguments empty."
    }

    $cmdString = ($Arguments | ForEach-Object { "'$_'" }) -join ' '
    Write-RedisLog "→ Redis CMD: $cmdString"

    $stream = $Context.Stream
    if ($stream.ReadTimeout -eq 0) { $stream.ReadTimeout = 10000 }
    if ($stream.WriteTimeout -eq 0) { $stream.WriteTimeout = 10000 }

    $lockObj = $Provider.State.SyncRoot
    [System.Threading.Monitor]::Enter($lockObj)
    try {
        $ascii = [Text.Encoding]::ASCII
        $utf8 = [Text.Encoding]::UTF8
        $crlf = $ascii.GetBytes("`r`n")

        $arrHdr = $ascii.GetBytes("*$($Arguments.Count)")
        $stream.Write($arrHdr, 0, $arrHdr.Length); $stream.Write($crlf, 0, 2)

        foreach ($it in [object[]]$Arguments) {
            $s = [string]$it
            $b = $utf8.GetBytes($s)
            $len = $ascii.GetBytes("`$$($b.Length)")
            $stream.Write($len, 0, $len.Length); $stream.Write($crlf, 0, 2)
            $stream.Write($b, 0, $b.Length); $stream.Write($crlf, 0, 2)
        }
        $stream.Flush()

        $response = Read-RedisRESP -Stream $stream
        Write-RedisLog "← Redis RESP: $($response | Out-String)"
        return $response
    }
    finally {
        [System.Threading.Monitor]::Exit($lockObj)
    }
}

function Read-Full {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory)]
        [byte[]]$Buffer,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Count
    )

    if ($null -eq $Stream) { throw "Stream cannot be null." }
    if (-not $Stream.CanRead) { throw "Stream is not readable." }
    if ($Buffer.Length -lt $Count) {
        throw "Buffer is smaller than Count (buffer=$($Buffer.Length), count=$Count)."
    }

    # Prefer .NET's ReadExactly if available (PowerShell 7+ on .NET 6+)
    $readExactly = [System.IO.Stream].GetMethod('ReadExactly', [Type[]]@([byte[]], [int], [int]))
    if ($readExactly) {
        try {
            $Stream.ReadExactly($Buffer, 0, $Count)
            return $Count
        }
        catch [System.IO.EndOfStreamException] {
            throw "Unexpected EOF while reading $Count bytes (received fewer)."
        }
    }

    # Fallback loop
    $offset = 0
    while ($offset -lt $Count) {
        $n = $Stream.Read($Buffer, $offset, $Count - $offset)
        if ($n -le 0) {
            throw "Unexpected EOF while reading $Count bytes (got $offset)."
        }
        $offset += $n
    }
    return $Count
}


function Read-RedisLine {
    param([System.IO.Stream]$Stream)

    $bytes = New-Object System.Collections.Generic.List[byte]
    while ($true) {
        $b = $Stream.ReadByte()
        if ($b -eq -1) { throw "Unexpected EOF while reading line." }
        if ($b -eq 13) {
            # CR
            $lf = $Stream.ReadByte()
            if ($lf -ne 10) { throw "Protocol error: expected LF after CR." }
            break
        }
        $bytes.Add([byte]$b)
    }
    return [Text.Encoding]::UTF8.GetString($bytes.ToArray())
}

function Read-RedisRESP {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)

    $type = $Stream.ReadByte()
    if ($type -lt 0) {
        Write-RedisLog "ERROR: Disconnected (no type byte)."
        throw "Disconnected from Redis (no type byte)."
    }

    switch ([char]$type) {
        '+' {
            $val = Read-RedisLine -Stream $Stream
            Write-RedisLog "Simple string: +$val"
            return $val
        }
        '-' {
            $err = Read-RedisLine -Stream $Stream
            Write-RedisLog "Error: -$err"
            throw "Redis error: $err"
        }
        ':' {
            $val = [int64](Read-RedisLine -Stream $Stream)
            Write-RedisLog "Integer: :$val"
            return $val
        }
        '$' {
            # Bulk string
            $lenStr = Read-RedisLine -Stream $Stream
            $len = [int]$lenStr
            if ($len -lt 0) {
                Write-RedisLog "Bulk string: \$-1 (null)"
                return $null
            }

            $buf = New-Object byte[] $len
            $null = Read-Full -Stream $Stream -Buffer $buf -Count $len  # discard count, we don't need it here

            # consume trailing CRLF
            $cr = $Stream.ReadByte(); 
            $lf = $Stream.ReadByte()

            if ($cr -ne 13 -or $lf -ne 10) { 
                throw "Protocol error: expected CRLF after bulk payload." 
            }

            $val = [Text.Encoding]::UTF8.GetString($buf)
            Write-RedisLog "Bulk string: \$$len => '$val'"
            return $val
        }
        '*' {
            $cnt = [int](Read-RedisLine -Stream $Stream)
            if ($cnt -lt 0) {
                Write-RedisLog "Array: *-1 (null)"
                return $null
            }
            if ($cnt -eq 0) {
                Write-RedisLog "Array: *0 (empty)"
                return @()
            }

            Write-RedisLog "Array: *$cnt (start)"
            $arr = @()
            for ($i = 0; $i -lt $cnt; $i++) {
                $item = Read-RedisRESP -Stream $Stream
                Write-RedisLog "  [$i] Type: $($item.GetType().Name) - Value: $item"
                $arr += , $item
            }
            Write-RedisLog "Array: *$cnt (end)"
            return $arr
        }
        default {
            Write-RedisLog "Unknown RESP type byte: $type ('$([char]$type)')"
            throw "Unknown RESP type byte: $type ('$([char]$type)')"
        }
    }
}


function Write-CacheValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Value,
        [int]$JsonDepth = 100,
        [int]$CliXmlDepth = 5,
        [int]$CompressOverBytes = 4096
    )

    if ($null -eq $Value) {
        throw "Write-CacheValue called with `$null. Caller should skip caching nulls."
    }

    $typeName = $Value.GetType().AssemblyQualifiedName

    $fmt = 'json'
    try {
        $data = ConvertTo-Json -InputObject $Value -Compress -Depth $JsonDepth
    }
    catch {
        $fmt = 'clixml'
        $data = [System.Management.Automation.PSSerializer]::Serialize($Value, $CliXmlDepth)
    }

    $enc = 'utf8'
    if ([Text.Encoding]::UTF8.GetByteCount($data) -ge $CompressOverBytes) {
        $ms = New-Object System.IO.MemoryStream
        $gzip = New-Object System.IO.Compression.GZipStream($ms, [IO.Compression.CompressionLevel]::SmallestSize)
        $bytes = [Text.Encoding]::UTF8.GetBytes($data)
        $gzip.Write($bytes, 0, $bytes.Length); $gzip.Dispose()
        $data = [Convert]::ToBase64String($ms.ToArray()); $enc = 'gzip+base64'
        $ms.Dispose()
    }

    $envelope = [ordered]@{ v = 1; fmt = $fmt; enc = $enc; type = $typeName; data = $data }
    ConvertTo-Json $envelope -Compress -Depth 10
}

function Read-CacheValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Payload)

    $env = $null
    try { $env = $Payload | ConvertFrom-Json -ErrorAction Stop } catch { }
    if ($null -eq $env -or $null -eq $env.v -or $null -eq $env.fmt) { return $Payload }

    $data = $env.data
    if ($env.enc -eq 'gzip+base64') {
        $bytes = [Convert]::FromBase64String($data)
        $msIn = [System.IO.MemoryStream]::new($bytes, $false)
        $gzip = [System.IO.Compression.GZipStream]::new($msIn, [IO.Compression.CompressionMode]::Decompress)
        $msOut = [System.IO.MemoryStream]::new()
        $buf = New-Object byte[] 8192; while (($n = $gzip.Read($buf, 0, $buf.Length)) -gt 0) { $msOut.Write($buf, 0, $n) }
        $gzip.Dispose(); $msIn.Dispose()
        $data = [Text.Encoding]::UTF8.GetString($msOut.ToArray()); $msOut.Dispose()
    }

    switch ($env.fmt) {
        'json' { $data | ConvertFrom-Json }
        'clixml' { [System.Management.Automation.PSSerializer]::Deserialize($data) }
        default { $data }
    }
}
