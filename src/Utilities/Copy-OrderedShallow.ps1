# Shallow ordered copy (fast; good if values are scalars/strings/arrays)
function script:Copy-OrderedShallow([hashtable]$h) {
    $copy = [ordered]@{}

    foreach ($k in $h.Keys) { 
        $copy[$k] = $h[$k] 
    }
    
    return $copy
}
