function New-DirectoryIfMissing {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Path','FullName')]
        [string]$Folder,

        [switch]$PassThru
    )

    begin { }

    process {

        if ([string]::IsNullOrWhiteSpace($Folder)) { 
            return 
        }

        # Resolve to a provider path (handles relative paths)
        $target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Folder)

        if (-not (Test-Path -LiteralPath $target -PathType Container)) {
            Write-Verbose "ExpressionCache: Creating missing folder '$target'."

            if ($PSCmdlet.ShouldProcess($target, 'Create directory')) {

                $item = New-Item -ItemType Directory -LiteralPath $target -Force -ErrorAction Stop

                if ($PassThru) { 
                    $item 
                }
            }
        }
        elseif ($PassThru) {
            Get-Item -LiteralPath $target
        }
    }

    end { }
}
