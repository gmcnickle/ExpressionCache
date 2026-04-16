Describe 'InMemoryCache sample' {

    It 'runs the sample end-to-end without errors' {
        $repoRoot   = Split-Path $PSScriptRoot -Parent
        $srcDir     = Join-Path $repoRoot 'src'
        $modulePath = Join-Path $srcDir 'ExpressionCache.psd1'
        $sampleDir  = Join-Path (Join-Path $repoRoot 'samples') 'implementing-yourown-provider'
        $provider   = Join-Path $sampleDir 'InMemoryCache.Provider.ps1'
        $sample     = Join-Path $sampleDir 'InMemoryCache.Sample.ps1'

        $output = & pwsh -NoProfile -Command @"
            Import-Module '$modulePath' -Force
            . '$provider'
            & '$sample'
"@
        $LASTEXITCODE | Should -Be 0 -Because "sample output was: $($output -join "`n")"
    }
}
