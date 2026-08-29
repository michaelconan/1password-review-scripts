<#
    .SYNOPSIS
    Adds password rotation date fields to 1Password logins.

    .DESCRIPTION
    This script sets up the last password update field for all logins in the vault that have a password
    but do not have a last password update field. It retrieves all logins from the vault, checks if they
    have a password and a last password update field, and if not, adds the last password update field with
    the created date.

    .PARAMETER Vault
    The name of the vault to retrieve logins from. Default is "private".

    .EXAMPLE
    PS> .\Add-Rotation-Fields.ps1

    .EXAMPLE
    PS> .\Add-Rotation-Fields.ps1 -Vault shared
#>

param([string]$Vault = "private")

. "$PSScriptRoot\Utils.ps1"

$ITEM_CATEGORIES = @("login", "api credential", "password")
$SSO_TAG = "secure/sso"
$EXCLUDE_TAG = "other/*"

$logins = @(Get-VaultItems -Vault $Vault -Categories $ITEM_CATEGORIES)
Write-Output "Found $($logins.Count) items matching $($ITEM_CATEGORIES -join ',') in the vault $Vault"

$itemDetails = @(Get-ItemDetails -Items $logins)
Write-Output "Evaluating $($itemDetails.Count) item(s) for missing rotation fields..."

$updatedCount = 0
$skippedCount = 0
$excludedCount = 0
$totalItems = $itemDetails.Count
$processedCount = 0

foreach ($pair in $itemDetails) {
    $processedCount++
    $login   = $pair.Login
    $details = $pair.Details

    if ($totalItems -gt 0) {
        Write-Progress -Activity "Evaluating rotation fields" `
            -Status "Item $processedCount of ${totalItems}: $($login.title)" `
            -PercentComplete (($processedCount / $totalItems) * 100)
    }

    if (Test-ItemExcluded -Details $details -Pattern $EXCLUDE_TAG) {
        $excludedCount++
    }
    else {
        if (Test-NeedsRotationField -Details $details) {
            $createdAt = if ($login.created_at) { $login.created_at } else { $details.created_at }
            $createdDate = ([datetime]$createdAt).ToString("yyyy-MM-dd")

            Write-Output "Adding last password update field to $($login.title)..."
            $editOutput = op item edit --vault $Vault $login.id "rotation.last password update[date]=$createdDate" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Output "Added last password update field to $($login.title)"
                $updatedCount++
            } else {
                $errMsg = ($editOutput | ForEach-Object { "$_" }) -join "`n"
                Write-Warning "Failed to add last password update field to $($login.title): $errMsg"
            }
        }
        elseif (
            ($null -ne (Get-ItemField -Details $details -Label "sign in with")) -and
            ($details.tags -notcontains $SSO_TAG)
        ) {
            Write-Output "Add SSO tag to $($login.title)"
            # NOTE: CLI does not currently support ssoLogin fields, this will error
            # $newTags = $details.tags + $SSO_TAG
            # op item edit $login.id --tags $($newTags -join ',') | Out-Null
            # Write-Output "Added SSO tag to $($login.title)"
            $skippedCount++
        }
        else {
            $skippedCount++
        }
    }
}

if ($totalItems -gt 0) {
    Write-Progress -Activity "Evaluating rotation fields" -Completed
}

Write-Output "Completed rotation field check for vault '$Vault'. Updated $updatedCount item(s), $skippedCount item(s) up to date, $excludedCount item(s) excluded."
