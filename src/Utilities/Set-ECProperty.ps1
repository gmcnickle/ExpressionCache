<#
.SYNOPSIS
Adds or updates a property on pipeline objects, with optional overwrite controls and type enforcement.

.DESCRIPTION
Set-ECProperty ensures an object has a given NoteProperty. If it doesn't exist, it is added; if it
exists, it may be updated depending on flags:
- -NoOverwrite     : never change an existing value
- -OnlyIfNull      : update only when the current value is $null
- -DontEnforceType : skip type checks when updating existing properties

Supports -WhatIf / -Confirm via ShouldProcess. Returns the SAME input instance for pipeline chaining.

.PARAMETER Object
Input object (ValueFromPipeline) that will receive or update the property.

.PARAMETER Name
Property name to add or update (case-insensitive). If the name differs only by case, no duplicate is created.

.PARAMETER Value
Value to assign when adding or updating the property.

.PARAMETER NoOverwrite
If specified, do not overwrite an existing value.

.PARAMETER OnlyIfNull
If specified, only overwrite when the existing value is $null. New properties are still added.

.PARAMETER DontEnforceType
If specified, skip type enforcement when updating an existing property. By default, updating a
property throws if the new value's type differs from the existing property's value type.

.INPUTS
psobject

.OUTPUTS
psobject

.EXAMPLE
# Add, then update
$obj = [pscustomobject]@{ Name='Jane' }
$obj | Set-ECProperty -Name Title -Value Engineer | Out-Null
$obj | Set-ECProperty -Name Title -Value Manager  | Out-Null

.EXAMPLE
# Respect -OnlyIfNull
$obj = [pscustomobject]@{ Title = $null }
$obj | Set-ECProperty -Name Title -Value Engineer -OnlyIfNull

.EXAMPLE
# Preview changes with -WhatIf
$obj | Set-ECProperty -Name Title -Value Director -WhatIf

.LINK
about_CommonParameters
#>
function Set-ECProperty {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject]$Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        $Value,

        [switch]$NoOverwrite,
        [switch]$OnlyIfNull,

        [switch]$DontEnforceType
    )

    process {
        if ($null -eq $Object) {
            throw "Object cannot be null."
        }

        $prop   = $Object.PSObject.Properties[$Name]
        $target = "{0}::{1}" -f $Object.GetType().FullName, $Name

        if ($null -eq $prop) {
            # Add new NoteProperty
            if ($PSCmdlet.ShouldProcess($target, "Add property '$Name'")) {
                Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value | Out-Null
            }
            return $Object
        }

        if (-not $prop.IsSettable) {
            throw "Property '$Name' is read-only on type [$($Object.GetType().FullName)]."
        }

        # Type enforcement (null-safe)
        if (-not $DontEnforceType -and $null -ne $Value -and $prop.TypeNameOfValue -ne $Value.GetType().FullName) {
            throw "Type mismatch: property '$Name' is of type [$($prop.TypeNameOfValue)], value is [$($Value.GetType().FullName)]."
        }

        # Decide whether to update
        if ($NoOverwrite) {
            return $Object
        }
        if ($OnlyIfNull -and $null -ne $Object.$Name) {
            return $Object
        }

        if ($PSCmdlet.ShouldProcess($target, "Set property '$Name'")) {
            $Object.$Name = $Value
        }

        return $Object
    }
}
