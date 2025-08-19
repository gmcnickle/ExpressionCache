@{
    # Core
    RootModule        = 'ExpressionCache.psm1'
    ModuleVersion     = '0.1.1'
    GUID              = '4ebe238d-ac4f-4731-a0b3-73fe7d28f97d'
    Author            = 'Gary McNickle'
    CompanyName       = 'RogueCivilian'
    Copyright         = '© 2025 Gary McNickle. MIT.'
    PowerShellVersion = '5.1' 
    Description       = 'Lightweight, extensible caching for PowerShell.'
    CompatiblePSEditions = @('Desktop','Core')  # cross-platform

    # Exports
    #FunctionsToExport = @()  
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            LicenseUri   = 'https://opensource.org/license/mit/' 
            ProjectUri   = 'https://github.com/gmcnickle/ExpressionCache'
            Tags         = @('caching', 'powershell', 'scriptblock')
            ReleaseNotes = 'Initial Pre-Release'
            Prerelease = 'beta1'
        }
    }
}
