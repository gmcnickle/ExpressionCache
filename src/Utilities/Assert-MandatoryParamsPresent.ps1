function Assert-MandatoryParamsPresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Splat
    )

    $mandatory =
        (Get-Command -Name $CommandName -ErrorAction Stop).Parameters.Values |
        Where-Object {
            $_.Attributes.Where({
                $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
            }).Count
        } |
        ForEach-Object Name

    $missing = $mandatory | Where-Object { -not $Splat.Contains($_) }

    if ($missing) {
        throw "Initialize '$CommandName' missing required config: $($missing -join ', ')"
    }
}
