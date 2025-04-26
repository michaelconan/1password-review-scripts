<#
    .SYNOPSIS
    Generate new password for 1Password item and update rotation date.

    .DESCRIPTION
    This script generates a new password for a specified 1Password item using a defined recipe.
    It retrieves the item details, checks for a password recipe field, and generates a new password.
    The script also updates the last password update date to the current date.
    If the item does not have a password recipe field, it uses a default recipe.

    .PARAMETER Vault
    The name of the vault to retrieve items from. Default is "private".

    .PARAMETER Item
    The ID or title of the 1Password item to update.

    .EXAMPLE
    PS> .\New-Item-Password.ps1 -Item "MyLogin"

    .EXAMPLE
    PS> .\New-Item-Password.ps1 -Item "MyLogin" -Vault Shared
#>

param(
    [string]$Vault = "private",
    [string]$Item
)

$RECIPE = "letters,digits,symbols,32"

# get specified password recipe or fallback to default
$itemDetails = op item get --format json $Item --vault $Vault | ConvertFrom-Json
$recipeField = $itemDetails.fields | Where-Object { $_.label -eq "password recipe" }
if ($null -ne $recipeField) {
    $recipe = $recipeField.value
} else {
    $recipe = $RECIPE
}

# generate a new password using the recipe and update the rotation date
$today = Get-Date -Format "yyyy-MM-dd"
op item edit --vault $Vault $Item --generate-password=$recipe | Out-Null
op item edit --vault $Vault $Item "rotation.last password update[date]=$today" | Out-Null
Write-Output "Generated password for $($itemDetails.title) with recipe $recipe"
