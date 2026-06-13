@{
    IncludeDefaultRules = $true
    ExcludeRules        = @(
        'PSUseSingularNouns' # Get-VaultItems and Get-ItemDetails are established public API
    )
}
