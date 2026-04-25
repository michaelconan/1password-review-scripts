<#
    .SYNOPSIS
    Retrieve password login items not updated recently.

    .DESCRIPTION
    This script retrieves password login items from a specified 1Password vault that have not been updated recently.
    It checks for the presence of a password and a last password update field, and if the last update date exceeds a specified cadence,
    then adds the item to a list of stale items. The cadence is determined by the tag applied to the item.
    These items can be reviewed for potential updates or deletions.

    .PARAMETER Vault
    The name of the vault to retrieve logins from. Default is "private".

    .PARAMETER Tag
    The tag to filter logins by.

    .EXAMPLE
    PS> .\Get-Stale-Items.ps1 -Tag finance

    .EXAMPLE
    PS> .\Get-Stale-Items.ps1 -Vault shared -Tag finance
#>

param(
    [string]$Vault = "private",
    [string]$Tag
)

. "$PSScriptRoot\Utils.ps1"

$CADENCES = @{
    "finance" = 90
    "main"    = 90
}
$EXCLUDE_TAG = "other/*"

$days = if ($CADENCES.ContainsKey($Tag)) { $CADENCES[$Tag] } else { 360 }

$logins = Get-VaultItems -Vault $Vault -Categories @("login") -Tag $Tag
$stale = @()
Write-Output "Reviewing $($logins.Count) login items with tag: $Tag"

$stale = Get-ItemDetails -Items $logins | ForEach-Object {
    Get-StaleItemInfo -Login $_.Login -Details $_.Details -Days $days -ExcludePattern $EXCLUDE_TAG
} | Where-Object { $null -ne $_ }

Write-Output "$($stale.Count) stale items with tag: $Tag"
$stale | Sort-Object -Property DaysSinceUpdate -Descending | Format-Table -AutoSize
