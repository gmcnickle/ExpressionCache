function Get-ProviderSpecificParamNames {
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Intentional plural for clarity: returns multiple parameter names.')]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName
    )
    
    $paramInfo = (Get-Command $CommandName -ErrorAction Stop).Parameters

    $common = @(
        [System.Management.Automation.PSCmdlet]::CommonParameters +
        [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    )

    # Return only non-common parameter names
    $paramInfo.Keys | Where-Object { $common -notcontains $_ }
}
