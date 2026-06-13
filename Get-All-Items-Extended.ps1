<#
    .SYNOPSIS
    Retrieve all 1Password items with SSO, MFA, and last password update fields.

    .DESCRIPTION
    This script retrieves all items from a specified 1Password vault and enriches each with
    computed security metadata: whether the item uses SSO (detected via a "sign in with" field
    or the "secure/sso" tag), whether it has MFA (via the "secure/mfa" tag), the last password
    update date, and the password recipe. Items tagged "other/*" are excluded. Results are
    exported to a CSV file for further analysis or reporting.

    .PARAMETER Vault
    The name of the vault to retrieve items from. Default is "private".

    .PARAMETER ExportPath
    Path for the output CSV file. Default is "items.csv" in the current directory.

    .EXAMPLE
    PS> .\Get-All-Items-Extended.ps1

    .EXAMPLE
    PS> .\Get-All-Items-Extended.ps1 -Vault Shared -ExportPath "C:\reports\vault.csv"
#>

param(
    [string]$Vault = "private",
    [string]$ExportPath = "items.csv"
)

. "$PSScriptRoot\Utils.ps1"

$SSO_TAG     = "secure/sso"
$MFA_TAG     = "secure/mfa"
$EXCLUDE_TAG = "other/*"

$items = Get-VaultItems -Vault $Vault
Write-Output "Found $($items.Count) items in the vault $Vault"

$results = Get-ItemDetails -Items $items | ForEach-Object {
    Get-ItemExtendedInfo -Details $_.Details -ExcludePattern $EXCLUDE_TAG -SsoTag $SSO_TAG -MfaTag $MFA_TAG
} | Where-Object { $null -ne $_ }

$results | Sort-Object -Property DaysSince -Descending | Export-Csv -Path $ExportPath -NoTypeInformation
Write-Output "Exported $($results.Count) items to $ExportPath"
