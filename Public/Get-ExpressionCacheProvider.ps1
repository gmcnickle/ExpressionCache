function Get-ExpressionCacheProvider 
{ 
    param(
        [string]$Name
    ) 

    if ($Name) { 
        $script:RegisteredStorageProviders | Where-Object Name -eq $Name 
    }
    else { 
        $script:RegisteredStorageProviders 
    }
}
