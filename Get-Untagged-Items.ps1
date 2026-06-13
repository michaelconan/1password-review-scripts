<#
    .SYNOPSIS
    Identify 1Password items without any tags applied.

    .DESCRIPTION
    This script sets identifies items in a specified 1Password vault that do not have any tags applied.
    It retrieves all items from the vault, checks for the presence of tags, and outputs the details of untagged items.

    .PARAMETER Vault
    The name of the vault to retrieve items from. Default is "private".

    .EXAMPLE
    PS> .\Get-Untagged-Items.ps1

    .EXAMPLE
    PS> .\Get-Untagged-Items.ps1 -Vault Shared
#>

param([string]$Vault = "private")

. "$PSScriptRoot\Utils.ps1"

# item categories to check for untagged items
$CATEGORIES = @("login", "password", "api credential")
$EXCLUDE_TAGS = "secure*"

$items = Get-VaultItems -Vault $Vault -Categories $CATEGORIES -Long

$items | Where-Object { Test-ItemUntagged -Item $_ -ExcludePattern $EXCLUDE_TAGS } |
    Select-Object -Property title, category, id, vault
