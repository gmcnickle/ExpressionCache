function Get-ProviderSpecificParamNames {
    param(
        [Parameter(Mandatory)][string]$CommandName
    )
    
    $paramInfo = (Get-Command $CommandName -ErrorAction Stop).Parameters

    $common = @(
        [System.Management.Automation.PSCmdlet]::CommonParameters +
        [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    )

    # Return only non-common parameter names
    $paramInfo.Keys | Where-Object { $common -notcontains $_ }
}
