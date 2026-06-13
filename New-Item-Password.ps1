<#
    .SYNOPSIS
    Generate new password for 1Password item and update rotation date.

    .DESCRIPTION
    This script generates a new password for a specified 1Password item using a defined recipe.
    It retrieves the item details, checks for a password recipe field, and generates a new password.
    The script also updates the last password update date to the current date.
    If the item does not have a password recipe field, it uses a default recipe.

    When the recipe includes "words", a memorable password is generated locally by mixing random
    words with the other recipe components (digits, symbols), since the 1Password CLI does not
    support word-based generation natively. Words are sourced from the EFF large wordlist and
    cached locally; the cache is refreshed automatically when missing.

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

. "$PSScriptRoot\Utils.ps1"

$RECIPE = "letters,digits,symbols,32"

$itemDetails = Get-ItemDetail -Id $Item -Vault $Vault
$recipe = Get-PasswordRecipe -Details $itemDetails -Default $RECIPE

$today = Get-Date -Format "yyyy-MM-dd"
$recipeParts = $recipe -split ','
$recipeLength = [int]($recipeParts | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
if ($recipeLength -eq 0) { $recipeLength = 32 }

if ('words' -in $recipeParts) {
    $newPassword = New-MemorablePassword -RecipeParts $recipeParts -Length $recipeLength
    op item edit --vault $Vault $Item "password=$newPassword" | Out-Null
} else {
    op item edit --vault $Vault $Item --generate-password=$recipe | Out-Null
}
op item edit --vault $Vault $Item "rotation.last password update[date]=$today" | Out-Null
Write-Output "Generated password for $($itemDetails.title) with recipe $recipe"
