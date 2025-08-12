# Providers/RedisCacheProvider.Light.ps1

using namespace System.Net.Sockets
using namespace System.Text

# -- Client constructor -------------------------------------------------------
function New-RedisClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostAddress,
        [Parameter(Mandatory)]
        [int]$Port,
        [int]$Database = 0,
        [string]$Prefix = 'ExpressionCache:v1',
        [string]$Password
    )
    $client = [TcpClient]::new()
    $client.NoDelay = $true
    $client.Connect($HostAddress, $Port)
    $stream = $client.GetStream()

    $ctx = [ordered]@{
        Client  = $client
        Stream  = $stream
        Prefix  = $Prefix
        Db      = $Database
        Host    = $HostAddress
        Port    = $Port
    }

    if ($Password) { 
        Invoke-RedisRaw -Context $ctx -Arguments @('AUTH', $Password) | Out-Null 
    }

    if ($Database -gt 0) { 
        Invoke-RedisRaw -Context $ctx -Arguments @('SELECT', $Database.ToString()) | Out-Null 
    }

    $pong = Invoke-RedisRaw -Context $ctx -Arguments @('PING')

    if ($pong -ne 'PONG') { 
        throw "RedisCache: Redis PING failed: $pong" 
    }

    return [pscustomobject]$ctx
}

# -- Public commands used by provider ----------------------------------------

function Initialize-Redis {
    [CmdletBinding()]
    param(
        [string]$HostAddress = '127.0.0.1',
        [int]$Port = 6379,
        [int]$Database = 2,
        [string]$Prefix = 'ExpressionCache:v1',
        [string]$Password = ""
    )

    $script:RedisClient = New-RedisClient -HostAddress $HostAddress -Port $Port -Database $Database -Password $Password -Prefix $Prefix
}


function Get-Redis-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory=$false)]
        [Alias('ArgumentList')]
        [object[]]$Arguments,

        # Interpret as an expiration moment in time (same as filesystem version)
        [Parameter(Mandatory)]
        [DateTime]$MaximumAge
    )

    if (-not $script:RedisClient) {
        throw "Redis client is not initialized. Call Initialize-Redis first."
    }

    $rkey = Join-RedisKey -Client $script:RedisClient -Key $Key

    # 1) Try Redis
    $value = Invoke-RedisRaw -Context $script:RedisClient -Arguments @('GET', $rkey)

    if ($null -ne $value) {
        return $value
    }

    Write-Verbose "RedisCache: Miss for key '$rkey' → executing ScriptBlock."

    # 2) Cache Miss → compute via ScriptBlock
    $Arguments = if ($Arguments) { 
        $Arguments 
    } 
    else { 
        @() 
    }

    $response = & $ScriptBlock @Arguments

    # 3) Persist to Redis with TTL derived from MaximumAge
    #    MaximumAge is treated as the *latest acceptable timestamp*; TTL = (MaximumAge - now)
    $ttlSeconds = [int][Math]::Ceiling( ($MaximumAge - (Get-Date)).TotalSeconds )

    if ($ttlSeconds -le 0) {
        # Already “expired” by policy; store briefly to avoid thundering herds, or skip TTL if you prefer
        $ttlSeconds = 1
    }

    # Optional: a compact description of the compute step for debugging (mirrors filesystem ‘Query’)
    $desc = ($ScriptBlock.ToString() -split "`r?`n" | ForEach-Object { $_.Trim() }) -join ' '

    # SET value with EX TTL; you could also store $desc in a separate meta key if you want
    # e.g., HSET "$rkey:meta" q $desc ts (Get-Date).ToString('o')
    [void](Invoke-RedisRaw -Context $script:RedisClient -Arguments @('SET', $rkey, $response, 'EX', $ttlSeconds))
    [void](Invoke-RedisRaw -Context $script:RedisClient -Arguments @('HSET', "$rkey:meta", 'q', $desc, 'ts', (Get-Date).ToString('o')))

    Write-Verbose "RedisCache: Stored '$rkey' with TTL ${ttlSeconds}s. Source: $desc"

    return $response
}

function Set-Redis-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$Value,

        [int]$TtlSeconds = 0
    )
    $rkey = (Join-RedisKey -Client $script:RedisClient -Key $Key)

    $arguments = if ($TtlSeconds -gt 0) { 
        @('SET', $rkey, $Value, 'EX', $TtlSeconds.ToString()) 
    } 
    else { 
        @('SET', $rkey, $Value) 
    }

    $resp = Invoke-RedisRaw -Context $script:RedisClient -Arguments $arguments

    if ($resp -ne 'OK') { 
        throw "RedisCache: SET failed: $resp" 
    }
}

function Test-Redis-CacheExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $rkey = (Join-RedisKey -Client $script:RedisClient -Key $Key)

    $n = Invoke-RedisRaw -Context $script:RedisClient -Arguments @('EXISTS', $rkey)

    return ([int]$n -gt 0)
}

function Remove-Redis-CachedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $rkey = (Join-RedisKey -Client $script:RedisClient -Key $Key)

    [void](Invoke-RedisRaw -Context $script:RedisClient -Arguments @('DEL', $rkey))
}

function Clear-Redis-Cache {
    $pattern = if ([string]::IsNullOrWhiteSpace($script:RedisClient.Prefix)) { 
        '*' 
    } 
    else { 
        "$($script:RedisClient.Prefix):*" 
    }

    $cursor = '0'
    do {
        $reply = Invoke-RedisRaw -Context $script:RedisClient -Arguments @('SCAN', $cursor, 'MATCH', $pattern, 'COUNT', '1000')
        # reply is an array: [cursor, [keys...]]
        $cursor = $reply[0]
        $keys   = $reply[1]

        if ($keys -and $keys.Count -gt 0) {
            foreach ($batch in ($keys | ForEach-Object -Begin {$tmp=@()} -Process {
                $tmp += $_; if ($tmp.Count -ge 1000) { ,$tmp; $tmp=@() }
            } -End { if ($tmp.Count) { ,$tmp } })) {
                [void](Invoke-RedisRaw -Context $script:RedisClient -Arguments (@('DEL') + $batch))
            }
        }
    } 
    while ($cursor -ne '0')
}

# -- Helpers -----------------------------------------------------------------
function Join-RedisKey {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($script:RedisClient)) { 
        return $Key 
    }

    return "$($script:RedisClient.Prefix):$Key"
}

function Invoke-RedisRaw {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Context,

        [Parameter(Mandatory)]
        [object[]]$Arguments
    )

    $stream = $Context.Stream

    # Write RESP array
    $ascii = [Encoding]::ASCII
    $utf8  = [Encoding]::UTF8
    $crlf  = $ascii.GetBytes("`r`n")

    $arrHdr = $ascii.GetBytes("*$($Arguments.Count)")
    $stream.Write($arrHdr,0,$arrHdr.Length); $stream.Write($crlf,0,2)

    foreach ($it in $Arguments) {
        $s = [string]$it
        $b = $utf8.GetBytes($s)
        $len = $ascii.GetBytes("`$$($b.Length)")
        $stream.Write($len,0,$len.Length); $stream.Write($crlf,0,2)
        $stream.Write($b,0,$b.Length); $stream.Write($crlf,0,2)
    }
    $stream.Flush()

    # Read RESP reply
    return Read-RedisRESP -Stream $stream
}

function Read-RedisRESP {
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream
    )

    $type = $Stream.ReadByte()

    if ($type -lt 0) { 
        throw "RedisCache: Disconnected from Redis." 
    }

    switch ([char]$type) {
        '+' { return Read-RedisLine -Stream $Stream }                                   # simple string
        '-' { $e = Read-RedisLine -Stream $Stream; throw "RedisCache: Redis error: $e"} # error
        ':' { return [int64](Read-RedisLine -Stream $Stream) }                          # integer
        '$' {
                $len = [int](Read-RedisLine -Stream $Stream)
                if ($len -lt 0) { 
                    return $null 
                }

                $buf = New-Object byte[] $len

                [void]$Stream.Read($buf,0,$len)
                [void]$Stream.ReadByte(); [void]$Stream.ReadByte()                      # CRLF

                return [Text.Encoding]::UTF8.GetString($buf)
        }
        '*' {
            $cnt = [int](Read-RedisLine -Stream $Stream)

            if ($cnt -lt 0) { 
                return $null 
            }

            $arr = New-Object object[] $cnt

            for ($i=0; $i -lt $cnt; $i++) { 
                $arr[$i] = Read-RedisRESP -Stream $Stream 
            }

            return $arr
        }

        default { throw "RedisCache: Unknown RESP type byte: $type" }
    }
}

function Read-RedisLine {
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream
    )

    $ms = [System.IO.MemoryStream]::new()

    while ($true) {
        $b = $Stream.ReadByte()

        if ($b -lt 0) { 
            break 
        }

        if ($b -eq 13) { 
            if ($Stream.ReadByte() -eq 10) { 
                break 
            } 
            else { 
                continue 
            } 
        }

        $ms.WriteByte([byte]$b)
    }

    return [Text.Encoding]::UTF8.GetString($ms.ToArray())
}
