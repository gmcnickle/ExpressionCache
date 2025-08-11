function Get-ExpressionCacheHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Text','String')]
        [AllowNull()]
        [string]$InputString
    )

    begin {
        # Create once per pipeline
        $hasher   = [System.Security.Cryptography.HashAlgorithm]::Create('SHA256')
        $encoding = [System.Text.Encoding]::UTF8
        if (-not $hasher) { 
            throw "Unable to create SHA256 hasher." 
        }
    }

    process {
        # Coerce $null to empty string so the pipeline keeps flowing
        $bytes     = $encoding.GetBytes([string]$InputString)
        $hashBytes = $hasher.ComputeHash($bytes)

        # hex without hyphens, lowercase
        [System.BitConverter]::ToString($hashBytes).Replace('-','').ToLowerInvariant()
    }

    end {
        if ($hasher -is [System.IDisposable]) { 
            $hasher.Dispose() 
        }
    }
}
