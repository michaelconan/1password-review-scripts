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

$SSO_TAG = "secure/sso"
$EXCLUDE_TAG = "other/*"

# retrieve all logins from the specified vault
$logins = op item list --categories login --format json --vault $Vault | ConvertFrom-Json

foreach ($login in $logins) {
    # get the login details, check for passwords and fields
    $loginDetails = op item get --format json $login.id | ConvertFrom-Json
    $loginPassword = $loginDetails.fields | Where-Object { ($_.id -eq "password") -and ($null -ne $_.value) }
    $loginFields = $loginDetails.fields | ForEach-Object { $_.label }

    if ($loginDetails.tags -notlike $EXCLUDE_TAG) {
        # add a last password update field to password-based logins without it
        if (($null -ne $loginPassword) -and ($loginFields -notcontains "last password update")) {
            $createdDate = $login.created_at.Substring(0, 10)
            op item edit $login.id "rotation.last password update[date]=$createdDate" | Out-Null
            Write-Output "Added last password update field to $($login.title)"
        }
        
        # add SSO tag to logins with SSO but without the tag
        elseif (($loginFields -contains "sign in with") -and ($loginDetails.tags -notcontains $SSO_TAG)) {
            $newTags = $loginDetails.tags + $SSO_TAG
            Write-Output "Add SSO tag to $($login.title)"
            # NOTE: CLI does not currently support ssoLogin fields, this will error
            # op item edit $login.id --tags $($newTags -join ',') | Out-Null
            # Write-Output "Added SSO tag to $($login.title)"
        }
    }
}
