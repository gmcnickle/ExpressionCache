function Build-SplatFromConfig {
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $names = Get-ProviderSpecificParamNames -CommandName $CommandName
    $splat = @{}

    foreach ($n in $names) {
        if ($Config.PSObject.Properties.Name -contains $n) {
            $splat[$n] = $Config.$n
        }
    }
    
    $splat
}
