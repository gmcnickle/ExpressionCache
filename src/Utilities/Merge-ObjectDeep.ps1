function Merge-ObjectDeep {
    param(
        [Parameter(Mandatory)] $Base,
        [Parameter(Mandatory)] $Override
    )

    if ($null -eq $Override) { return $Base }

    function _ToHashtable($o) {
        if ($null -eq $o) { return $null }
        if ($o -is [hashtable]) { return $o }
        if ($o -is [pscustomobject]) {
            $ht = @{}
            foreach ($prop in $o.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }
            return $ht
        }
        return $o
    }

    $bIsMap = ($Base -is [hashtable] -or $Base -is [pscustomobject])
    $oIsMap = ($Override -is [hashtable] -or $Override -is [pscustomobject])

    if ($bIsMap -or $oIsMap) {
        $b = _ToHashtable $Base
        $o = _ToHashtable $Override

        $resultIsPso = ($Base -is [pscustomobject])
        $result = if ($resultIsPso) { [pscustomobject]@{} } else { @{} }

        $bKeys = if ($b) { $b.Keys } else { @() }
        $oKeys = if ($o) { $o.Keys } else { @() }
        $allKeys = @($bKeys + $oKeys | Select-Object -Unique)

        foreach ($k in $allKeys) {
            $bv = if ($b -and $b.ContainsKey($k)) { $b[$k] } else { $null }
            $ov = if ($o -and $o.ContainsKey($k)) { $o[$k] } else { $null }

            $val =
                if ($null -ne $ov -and ($bv -is [hashtable] -or $bv -is [pscustomobject])) { Merge-ObjectDeep $bv $ov }
                elseif ($null -ne $ov) { $ov }
                else { $bv }

            if ($resultIsPso) {
                $result | Add-Member -NotePropertyName $k -NotePropertyValue $val
            } else {
                $result[$k] = $val
            }
        }
        return $result
    }

    # arrays/scalars: override wins if provided
    if ($null -ne $Override) { return $Override }
    return $Base
}
