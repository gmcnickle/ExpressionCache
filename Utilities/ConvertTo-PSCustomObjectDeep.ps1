function ConvertTo-PSCustomObjectDeep {
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    switch ($InputObject) {
        { $_ -is [System.Collections.IDictionary] } {
            $out = [pscustomobject]@{}

            foreach ($k in $_.Keys) {
                Add-Member -InputObject $out -NotePropertyName $k -NotePropertyValue (ConvertTo-PSCustomObjectDeep $_[$k])
            }

            return $out
        }
        { $_ -is [System.Collections.IEnumerable] -and $_ -isnot [string] } {
            $list = @(); foreach ($item in $_) { $list += ,(ConvertTo-PSCustomObjectDeep $item) }; return $list
        }

        default { 
            return $InputObject 
        }
    }
}
