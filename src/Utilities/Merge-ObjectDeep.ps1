function Merge-ObjectDeep {
    param(
        [Parameter(Mandatory)] 
        $Base,
        
        [Parameter(Mandatory)] 
        $Override
    )

    if ($null -eq $Override) { 
        return $Base 
    }

    # For hashtables and PSCustomObjects, walk properties
    if ($Base -is [hashtable] -or $Base -is [pscustomobject]) {

        $result = if ($Base -is [hashtable]) { 
            @{} 
        } 
        else { 
            [pscustomobject]@{} 
        }

        $allKeys = @(if ($Base -is [hashtable]) { $Base.Keys } else { $Base.PSObject.Properties.Name }) + @(if ($Override -is [hashtable]) { $Override.Keys } else { $Override.PSObject.Properties.Name }) | Select-Object -Unique

        foreach ($k in $allKeys) {
            $b = if ($Base -is [hashtable]) { 
                $Base[$k] 
            } 
            else { 
                $Base.$k 
            }

            $o = if ($Override -is [hashtable]) { 
                $Override[$k] 
            } 
            else { 
                $Override.$k 
            }

            if ($null -ne $o -and ($b -is [hashtable] -or $b -is [pscustomobject])) {
                $result | Add-Member -NotePropertyName $k -NotePropertyValue (Merge-ObjectDeep $b $o)
            } 
            elseif ($null -ne $o) {
                $result | Add-Member -NotePropertyName $k -NotePropertyValue $o
            } 
            else {
                $result | Add-Member -NotePropertyName $k -NotePropertyValue $b
            }
        }
        return $result
    }

    # For scalars/arrays: override wins if provided, else base
    if ($null -ne $Override) { 
        return $Override 
    } 
    else { 
        return $Base 
    }
}
