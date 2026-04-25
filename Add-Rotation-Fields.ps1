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

$SSO_TAG = "secure/sso"
$EXCLUDE_TAG = "other/*"

$logins = Get-VaultItems -Vault $Vault -Categories @("login")
Write-Output "Found $($logins.Count) logins in the vault $Vault"

foreach ($pair in (Get-ItemDetails -Items $logins)) {
    $login   = $pair.Login
    $details = $pair.Details

    if (-not (Test-ItemExcluded -Details $details -Pattern $EXCLUDE_TAG)) {
        if (Test-NeedsRotationField -Details $details) {
            $createdDate = ([datetime]$login.created_at).ToString("yyyy-MM-dd")
            op item edit $login.id "rotation.last password update[date]=$createdDate" | Out-Null
            Write-Output "Added last password update field to $($login.title)"
        }
        elseif (
            ($null -ne (Get-ItemField -Details $details -Label "sign in with")) -and
            ($details.tags -notcontains $SSO_TAG)
        ) {
            $newTags = $details.tags + $SSO_TAG
            Write-Output "Add SSO tag to $($login.title)"
            # NOTE: CLI does not currently support ssoLogin fields, this will error
            # op item edit $login.id --tags $($newTags -join ',') | Out-Null
            # Write-Output "Added SSO tag to $($login.title)"
        }
    }
}
