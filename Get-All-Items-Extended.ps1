<#
    .SYNOPSIS
    Retrieve all 1Password items with SSO, MFA, and last password update fields.

    .DESCRIPTION
    This script retrieves all items from a specified 1Password vault, labels each item as SSO or not using the logic from Add-Rotation-Fields.ps1, checks for a 'secure/mfa' tag to set an MFA boolean flag, and creates a field for the last password update date for password-based items using the same logic. The output is a list of items with these additional fields for further analysis or reporting.

    .PARAMETER Vault
    The name of the vault to retrieve items from. Default is "private".

    .EXAMPLE
    PS> .\Get-All-Items-Extended.ps1

    .EXAMPLE
    PS> .\Get-All-Items-Extended.ps1 -Vault shared
#>

param([string]$vault = "private")

$SSO_TAG = "secure/sso"
$MFA_TAG = "secure/mfa"
$EXCLUDE_TAG = "other/*"

# Retrieve all items from the specified vault
$items = op item list --format json --vault $vault | ConvertFrom-Json
Write-Output "Found $($items.Count) items in the vault $vault"

$results = @()
$totalItems = $items.Count
for ($i = 0; $i -lt $totalItems; $i++) {
    $item = $items[$i]
    try {
        $details = op item get --format json $item.id | ConvertFrom-Json
        $fields = $details.fields | ForEach-Object { $_.label }
        $tags = $details.tags
        $security = [System.Collections.Generic.List[string]]::new()

        # Exclude items with tags matching the exclude pattern
        $excludeTags = $tags | Where-Object { $_ -like $EXCLUDE_TAG }
        if ($excludeTags.Count -ne 0) {
            continue
        }

        # SSO logic: has 'sign in with' field or SSO tag
        $isSso = ($fields -contains "sign in with") -or ($tags -contains $SSO_TAG)
        if ($isSso) {
            $security.Add("SSO")
        }
        # not supported by CLI as of version 2.32.0
        # $hasPasskey = $fields -contains "passkey"

        # MFA logic: has 'secure/mfa' tag
        $isMfa = ($tags -contains $MFA_TAG)
        if ($isMfa) {
            $security.Add("MFA")
        }

        # Last password update logic for password-based items
        $RECIPE = "letters,digits,symbols,32"
        $recipe = $null
        $lastUpdateString = $null
        $daysSinceUpdate = $null
        $usernameField = $details.fields | Where-Object { $_.id -eq "username" }
        $passwordField = $details.fields | Where-Object { ($_.id -eq "password") -and ($null -ne $_.value) }
        if ($null -ne $passwordField) {
            $lastUpdate = $details.fields | Where-Object { 
                $_.label -eq "last password update" 
            } | Select-Object -ExpandProperty value
            if ($null -eq $lastUpdate) {
                # If no last password update field, use created date
                $lastUpdateDate = [datetime]$details.created_at
            } else {
                $lastUpdateDate = ([System.DateTimeOffset]::FromUnixTimeSeconds($lastUpdate)).DateTime
            }
            $daysSinceUpdate = (New-TimeSpan -Start $lastUpdateDate -End (Get-Date)).Days
            $lastUpdateString = $lastUpdateDate.ToString("yyyy-MM-dd")
            $recipeField = $details.fields | Where-Object { $_.label -eq "password recipe" }
            if ($null -ne $recipeField) {
                $recipe = $recipeField.value
            } else {
                $recipe = $RECIPE
            }
        }

        $results += [PSCustomObject]@{
            Title = $details.title
            Username = $usernameField.value
            Category = $details.category
            Id = $details.id
            Vault = $details.vault.name
            Security = ($security -join ",")
            Recipe = $recipe
            LastPwUpdate = $lastUpdateString
            DaysSince = $daysSinceUpdate
        }
    } catch {
        Write-Warning "Error processing item: $($_.Exception.Message) | Title: $($item.title)"
    }

    Write-Progress -PercentComplete ((($i + 1) / $totalItems) * 100) `
        -Status "Processing $($item.title)" `
        -Activity "Retrieving and analyzing items"
}

$results | Sort-Object -Property DaysSinceUpdate -Descending | Export-Csv -Path "items.csv" -NoTypeInformation
