# Providers/RedisCacheProvider.Light.ps1

using namespace System.Net.Sockets
using namespace System.Text

# -- Client constructor -------------------------------------------------------
function New-RedisClient {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        $Provider,

        [Parameter(Mandatory)]
        [string]$HostAddress,

        [Parameter(Mandatory)]
        [ValidateRange(1,65535)]
        [int]$Port,

        [ValidateRange(0,[int]::MaxValue)]
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
        [string]$HostAddress = '127.0.0.1',
        [int]$Port = 6379,
        [int]$Database = 2,
        [string]$Prefix = 'ExpressionCache:v1',
        [string]$Password = ""
    )

    $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName
   
    if (-not $provider) { 
        throw "Provider '$ProviderName' not found." 
    }

    if ($provider.State.Initialized) {
        # Write-Warning "RedisCache: Provider already initialized."
        
        return
    }

    $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName
    $state = $provider.State
    if (-not $state) {
        $state = [PSCustomObject]@{
            Client      = $null
            Initialized = $true
            SyncRoot    = [object]::new()
        }
    } 
    $null = $provider | Set-ECProperty -Name 'State' -Value $state -DontEnforceType

    $client = New-RedisClient -Provider $provider -HostAddress $HostAddress -Port $Port -Database $Database -Password $Password -Prefix $Prefix
    $provider.State.Client = $client
}

function Resolve-RedisClient {
    param(
        [Parameter(Mandatory)]
        [string]$ProviderName
    )

    $provider = Get-ExpressionCacheProvider -ProviderName $ProviderName
    if (-not $provider) { throw "Provider '$ProviderName' not found." }

    $client = $provider.State.Client

    if (-not $client) {
        throw "No client found for '$ProviderName'."
    }

    return $client, $provider
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

    $client, $provider = Resolve-RedisClient -ProviderName $ProviderName
    $rkey = Join-RedisKey -Client $client -Key $Key

    # READ
    $raw = Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('GET', $rkey))
    if ($null -ne $raw) {
        # Sliding: refresh TTLs on hit
        if ($Policy.Sliding) {
            [void](Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('EXPIRE', $rkey, [string]$Policy.TtlSeconds)))
            [void](Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('EXPIRE', "${rkey}:meta", [string]$Policy.TtlSeconds)))
        }
        return (Read-CacheValue $raw)
    }

    # MISS → compute
    if ($null -eq $Arguments) { $Arguments = @() }
    $result = & $ScriptBlock @Arguments
    if ($null -eq $result) { return $null }

    $payload = Write-CacheValue -Value $result

    # Write value with TTL
    [void](Invoke-RedisRaw -Provider $provider -Context $client `
            -Arguments ([object[]]@('SET', $rkey, $payload, 'EX', [string]$Policy.TtlSeconds)))

    # optional metadata (query + timestamp)
    $desc = ($ScriptBlock.ToString() -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' '
    [void](Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('HSET', "${rkey}:meta", 'q', $desc, 'ts', (Get-Date).ToString('o'))))
    [void](Invoke-RedisRaw -Provider $provider -Context $client -Arguments ([object[]]@('EXPIRE', "${rkey}:meta", [string]$Policy.TtlSeconds)))

    return $result
}



function Clear-Redis-Cache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProviderName,
        [switch]$Force
    )

    $client, $provider = Resolve-RedisClient -ProviderName $ProviderName
    $pattern = "$($client.Prefix)*"   # must match Join-RedisKey behavior

    $cursor = '0'
    do {
        $resp = Invoke-RedisRaw -Provider $provider -Context $client `
            -Arguments ([object[]]@('SCAN', $cursor, 'MATCH', $pattern, 'COUNT', '1000'))
        $cursor = [string]$resp[0]
        $keys = @($resp[1])

        if ($keys.Count -gt 0) {
            $batchSize = 1000
            for ($i = 0; $i -lt $keys.Count; $i += $batchSize) {
                $end = [Math]::Min($i + $batchSize - 1, $keys.Count - 1)
                $chunk = $keys[$i..$end]
                $cmd = @('UNLINK') + $chunk
                [void](Invoke-RedisRaw -Provider $provider -Context $client -Arguments $cmd)
            }
        }
    } while ($cursor -ne '0')
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

    $stream = $Context.Stream
    if ($stream.ReadTimeout -eq 0) {
        $stream.ReadTimeout = 10000 
    }

    if ($stream.WriteTimeout -eq 0) {
        $stream.WriteTimeout = 10000 
    }

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

        return Read-RedisRESP -Stream $stream
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
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)

    # Optional: avoid hangs forever
    if ($Stream.ReadTimeout -eq 0) { $Stream.ReadTimeout = 10000 }  # 10s

    $ms = New-Object System.IO.MemoryStream
    while ($true) {
        $b = $Stream.ReadByte()
        if ($b -lt 0) { throw "Disconnected while reading line." }
        if ($b -eq 13) {
            # CR
            $lf = $Stream.ReadByte()
            if ($lf -ne 10) { throw "Protocol error: expected LF after CR, got $lf." }
            break
        }
        $ms.WriteByte([byte]$b)
    }
    return [Text.Encoding]::UTF8.GetString($ms.ToArray())
}

function Read-RedisRESP {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)

    $type = $Stream.ReadByte()
    if ($type -lt 0) { throw "Disconnected from Redis." }

    switch ([char]$type) {
        '+' { return Read-RedisLine -Stream $Stream }                        # Simple String
        '-' { $e = Read-RedisLine -Stream $Stream; throw "Redis error: $e" } # Error
        ':' { return [int64](Read-RedisLine -Stream $Stream) }               # Integer

        '$' {
            # Bulk String
            $len = [int](Read-RedisLine -Stream $Stream)
            if ($len -lt 0) { return $null }                                 # Null bulk

            $buf = New-Object byte[] $len
            Read-Full -Stream $Stream -Buffer $buf -Count $len

            # Require CRLF after bulk payload
            $cr = $Stream.ReadByte(); $lf = $Stream.ReadByte()
            if ($cr -ne 13 -or $lf -ne 10) {
                throw "Protocol error: expected CRLF after bulk payload."
            }
            return [Text.Encoding]::UTF8.GetString($buf)
        }

        '*' {
            # Array
            $cnt = [int](Read-RedisLine -Stream $Stream)
            if ($cnt -lt 0) { return $null }                                  # Null array

            $arr = New-Object object[] $cnt
            for ($i = 0; $i -lt $cnt; $i++) {
                $arr[$i] = Read-RedisRESP -Stream $Stream
            }
            return $arr
        }

        default { throw "Unknown RESP type byte: $type" }
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
