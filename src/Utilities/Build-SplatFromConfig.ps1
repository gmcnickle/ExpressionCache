function Build-SplatFromConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Config
    )

    # Discover provider-specific (non-common) parameter names
    $paramNames = Get-ProviderSpecificParamNames -CommandName $CommandName

    $splat = @{}
    foreach ($name in $paramNames) {
        if ($Config.Contains($name)) {  
            $splat[$name] = $Config[$name]
        }
    }
    return $splat
}
