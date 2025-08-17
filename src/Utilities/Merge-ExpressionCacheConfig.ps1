function Merge-ExpressionCacheConfig {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Base,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Overrides
    )

    foreach ($k in $Overrides.Keys) {
        # Create prop if missing
        if (-not ($Base.PSObject.Properties.Name -contains $k)) {
            Add-Member -InputObject $Base -NotePropertyName $k -NotePropertyValue $Overrides[$k]
        } 
        else {
            $Base.$k = $Overrides[$k]
        }
    }

    $Base
}
