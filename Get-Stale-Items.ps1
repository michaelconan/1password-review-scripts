param(
    [string]$Vault = "private",
    [string]$Tag
)

$CADENCES = @{
    "finance" = 90
    "main" = 90
}

# get cadence days from the tag or default to 360 days
if ($CADENCES.ContainsKey($Tag)) {
    $days = $CADENCES[$Tag]
} else {
    $days = 360
}

# get items from the vault with the specified tag
$logins = op item list --categories login --tags $Tag --format json --vault $Vault | ConvertFrom-Json
$stale = @()
Write-Output "Reviewing $($logins.Count) login items with tag: $Tag"


foreach ($login in $logins) {
    # get the login details, check for passwords and fields
    $loginDetails = op item get --format json $login.id | ConvertFrom-Json
    $loginPassword = $loginDetails.fields | Where-Object { ($_.id -eq "password") -and ($null -ne $_.value) }
    $loginFields = $loginDetails.fields | ForEach-Object { $_.label }

    # add a last password update field to password-based logins without it
    if (($null -ne $loginPassword) -and ($loginFields -contains "last password update")) {
        # get the last password update date and calculate days since last update
        $lastUpdate = $loginDetails.fields | Where-Object { $_.label -eq "last password update" } | Select-Object -ExpandProperty value
        $lastUpdateDate = ([System.DateTimeOffset]::FromUnixTimeSeconds($lastUpdate)).DateTime
        $daysSinceLastUpdate = (New-TimeSpan -Start $lastUpdateDate -End (Get-Date)).Days

        if ($daysSinceLastUpdate -gt $days) {
            $stale += [PSCustomObject]@{
                Title = $login.title
                ID = $login.id
                LastUpdate = $lastUpdateDate.ToString("yyyy-MM-dd")
                DaysSinceUpdate = $daysSinceLastUpdate
            }
        }
    }
}

Write-Output "$($stale.Count) stale items with tag: $Tag"
$stale | Sort-Object -Property DaysSinceUpdate -Descending | Format-Table -AutoSize
