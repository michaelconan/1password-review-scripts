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

$CADENCES = @{
    "finance" = 90
    "main"    = 90
}
$EXCLUDE_TAG = "other/*"

# get cadence days from the tag or default to 360 days
if ($CADENCES.ContainsKey($Tag)) {
    $days = $CADENCES[$Tag]
}
else {
    $days = 360
}

# get items from the vault with the specified tag
$logins = op item list --categories login --tags $Tag --format json --vault $Vault | ConvertFrom-Json
$stale = @()
Write-Output "Reviewing $($logins.Count) login items with tag: $Tag"


foreach ($login in $logins) {
    # get the login details, check for passwords and fields
    $loginDetails = op item get --format json $login.id | ConvertFrom-Json
    $loginPassword = $loginDetails.fields | Where-Object { 
        ($_.id -eq "password") -and ($null -ne $_.value) 
    }
    $loginFields = $loginDetails.fields | ForEach-Object { $_.label }

    $excludeTags = $loginDetails.tags | Where-Object { $_ -like $EXCLUDE_TAG }
    # add a last password update field to password-based logins without it
    if (
        ($excludeTags.Count -eq 0) -and 
        ($null -ne $loginPassword) -and 
        ($loginFields -contains "last password update")
    ) {
        # get the last password update date and calculate days since last update
        $lastUpdate = $loginDetails.fields | Where-Object { 
            $_.label -eq "last password update" 
        } | Select-Object -ExpandProperty value
        $lastUpdateDate = ([System.DateTimeOffset]::FromUnixTimeSeconds($lastUpdate)).DateTime
        $daysSinceLastUpdate = (New-TimeSpan -Start $lastUpdateDate -End (Get-Date)).Days

        if ($daysSinceLastUpdate -gt $days) {
            $stale += [PSCustomObject]@{
                Title           = $login.title
                ID              = $login.id
                LastUpdate      = $lastUpdateDate.ToString("yyyy-MM-dd")
                DaysSinceUpdate = $daysSinceLastUpdate
            }
        }
    }
}

Write-Output "$($stale.Count) stale items with tag: $Tag"
$stale | Sort-Object -Property DaysSinceUpdate -Descending | Format-Table -AutoSize
