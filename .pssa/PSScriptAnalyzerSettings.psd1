@{
  ExcludeRules = @(
    'PSAvoidUsingWriteHost'
    'PSUseDeclaredVarsMoreThanAssignments'
  )
  Rules = @{
    # Formatting examples (your existing ones are fine)
    PSPlaceOpenBrace = @{ Enable = $true; OnSameLine = $true }
    PSPlaceCloseBrace = @{ Enable = $true }
    PSAlignAssignmentStatement = @{ Enable = $true }
    PSAvoidGlobalVars = @{ Enable = $true }

    # Change severities per rule
    PSUseShouldProcessForStateChangingFunctions = @{ Enable = $true; Severity = 'Error' }
    PSUseSingularNouns                          = @{ Enable = $true; Severity = 'Information' }
  }
}
