@{
    # Core
    RootModule        = 'ExpressionCache.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '4ebe238d-ac4f-4731-a0b3-73fe7d28f97d'
    Author            = 'Gary McNickle'
    CompanyName       = ''
    Copyright         = ''
    PowerShellVersion = '5.1' 

    # Exports
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
    PSData = @{
        LicenseUri  = 'https://opensource.org/license/mit/' 
        ProjectUri  = 'https://github.com/gmcnickle/ExpressionCache'
        Tags        = @('caching','powershell','scriptblock')
        ReleaseNotes = ''
    }
}
