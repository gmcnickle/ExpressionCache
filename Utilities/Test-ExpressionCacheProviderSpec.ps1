function Test-ExpressionCacheProviderSpec {
    param(
        [Parameter(Mandatory)]
        [object]$Spec
    )

    # Accept hashtable or PSCustomObject; normalize to PSCustomObject
    if ($Spec -is [hashtable]) { 
        $Spec = [pscustomobject]$Spec 
    }

    $required = 'Name','ReadFromCache','Config'
    foreach ($r in $required) {
        if (-not ($Spec.PSObject.Properties.Name -contains $r) -or -not $Spec.$r) {
            throw "ExpressionCache: Provider spec missing required property '$r'."
        }
    }

    # Ensure command names resolve
    foreach ($cmdProp in 'ReadFromCache','Initialize') {
        $cmd = $Spec.$cmdProp

        if ($cmd) {
            if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
                throw "ExpressionCache: Provider spec '$($Spec.Name)': command '$cmd' (from '$cmdProp') not found."
            }
        }
    }

    # Ensure Config is an object (PSCO/hashtable ok). Coerce hashtable to PSCO for dot access.
    if ($Spec.Config -is [hashtable] -or $Spec.Config -is [System.Collections.IDictionary]) {
        Write-Verbose "ExpressionCache: Normalizing provider Config (hashtable -> PSCustomObject)."
        $Spec.Config = ConvertTo-PSCustomObjectDeep $Spec.Config
    } 
    elseif ($Spec.Config -isnot [pscustomobject]) {
        throw "ExpressionCache: Provider '$($Spec.Name)': Config must be a hashtable or PSCustomObject."
    }

    # Optional InitializeArgs must be splattable (hashtable/IDictionary)
    if ($Spec.PSObject.Properties.Name -contains 'InitializeArgs' -and $Spec.InitializeArgs) {
        if ($Spec.InitializeArgs -isnot [System.Collections.IDictionary]) {
            throw "ExpressionCache: Provider spec '$($Spec.Name)': InitializeArgs must be a hashtable/IDictionary."
        }
    }

    return $Spec
}
