function Assert-MandatoryParamsPresent {
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [hashtable]$Splat
    )

    $mandatory =
    (Get-Command $CommandName -ErrorAction Stop).Parameters.Values |
    Where-Object { $_.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count } |
    ForEach-Object Name

    $missing = $mandatory | Where-Object { -not $Splat.ContainsKey($_) }

    if ($missing) { 
        throw "Initialize '$CommandName' missing required config: $($missing -join ', ')" 
    }
}
