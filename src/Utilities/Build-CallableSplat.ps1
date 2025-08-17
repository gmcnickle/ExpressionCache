# Cache for parameter metadata to avoid repeated Get-Command lookups
$script:__ParamCache = $script:__ParamCache ?? @{}

function Build-CallableSplat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        # Optional: a PSCustomObject (e.g., provider Config)
        [pscustomobject]$Config,

        # Optional: extra runtime args (hashtable)
        [hashtable]$Arguments,

        # If set, items in -Arguments override same-named values from -Config
        [switch]$PreferArgs,

        # Pass null/empty strings through (default: skip)
        [switch]$IncludeNulls,

        # Emit verbose logging (use -Verbose to see output)
        [switch]$Log,

        # Optional prefix to make logs searchable
        [string]$LogPrefix = ''
    )

    if (-not $script:__ParamCache.ContainsKey($CommandName)) {
        $cmd = Get-Command -Name $CommandName -CommandType Function, Cmdlet, ExternalScript -ErrorAction Stop
        $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $aliasMap = @{}  # alias -> canonical
        foreach ($p in $cmd.Parameters.Values) {
            $null = $names.Add($p.Name)
            foreach ($a in $p.Aliases) {
                $null = $names.Add($a)
                $aliasMap[$a] = $p.Name
            }
        }
        $script:__ParamCache[$CommandName] = [pscustomobject]@{
            Names    = $names
            AliasMap = $aliasMap
            ParamMD  = $cmd.Parameters
        }
    }

    $md = $script:__ParamCache[$CommandName]
    $accepted = $md.Names
    $aliases = $md.AliasMap
    $paramMD = $md.ParamMD

    $prefix = if ([string]::IsNullOrWhiteSpace($LogPrefix)) { "[Build-CallableSplat:$CommandName]" } else { "[$($LogPrefix):$CommandName]" }

    if ($Log) { Write-Verbose "$prefix building splat (PreferArgs=$PreferArgs IncludeNulls=$IncludeNulls)" }

    # Gather raw candidates from Config + Arguments (with precedence)
    $candidates = @{}
    if ($Config) {
        foreach ($prop in $Config.PSObject.Properties) {
            if ($accepted.Contains($prop.Name)) {
                $candidates[$prop.Name] = $prop.Value
            }
        }
    }
    if ($Arguments) {
        foreach ($k in $Arguments.Keys) {
            if ($accepted.Contains($k)) {
                if ($PreferArgs -or -not $candidates.ContainsKey($k)) {
                    $candidates[$k] = $Arguments[$k]
                }
            }
        }
    }

    $included = New-Object System.Collections.Generic.List[string]
    $excluded = New-Object System.Collections.Generic.List[string]
    $reasons = @{} # name -> reason

    # Normalize, filter, and build the final splat
    $splat = @{}
    foreach ($k in $candidates.Keys) {
        $canonical = $aliases[$k]
        if (-not $canonical) { $canonical = $k }

        $v = $candidates[$k]
        $param = $paramMD[$canonical]
        $isSwitch = $param -and $param.ParameterType -eq [switch]

        if ($isSwitch) {
            if ($v) {
                $splat[$canonical] = $true
                $included.Add("$canonical=(switch:$true)")
            }
            else {
                $excluded.Add("$canonical")
                $reasons[$canonical] = 'switch:false'
            }
            continue
        }

        if ($IncludeNulls) {
            $splat[$canonical] = $v
            $included.Add("$canonical=(value:$([bool]($null -ne $v)))")
        }
        else {
            if ($null -ne $v -and ($v -isnot [string] -or $v -ne '')) {
                $splat[$canonical] = $v
                $included.Add("$canonical")
            }
            else {
                $excluded.Add("$canonical")
                $reasons[$canonical] = 'null-or-empty'
            }
        }
    }

    if ($Log) {
        if ($included.Count -gt 0) { Write-Verbose "$prefix included: $(($included -join ', '))" }
        if ($excluded.Count -gt 0) {
            $pairs = $excluded | ForEach-Object { "$_ ($($reasons[$_] ?? 'reason:unknown'))" }
            Write-Verbose "$prefix excluded: $(($pairs -join ', '))"
        }
        Write-Verbose "$prefix final count: $($splat.Count)"
    }

    return $splat
}
