Describe 'InMemoryCache sample' {

    It 'runs the sample end-to-end without errors' {
        $repoRoot   = Split-Path $PSScriptRoot -Parent
        $modulePath = Join-Path $repoRoot 'src' 'ExpressionCache.psd1'
        $provider   = Join-Path $repoRoot 'samples' 'implementing-yourown-provider' 'InMemoryCache.Provider.ps1'
        $sample     = Join-Path $repoRoot 'samples' 'implementing-yourown-provider' 'InMemoryCache.Sample.ps1'

        $output = & pwsh -NoProfile -Command @"
            Import-Module '$modulePath' -Force
            . '$provider'
            & '$sample'
"@
        $LASTEXITCODE | Should -Be 0 -Because "sample output was: $($output -join "`n")"
    }
}
