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

# item categories to check for untagged items
$CATEGORIES = @("login", "password", "api credential")
$EXCLUDE_TAGS = "secure*"

# retrieve extended items from the specified vault
$items = op item list --categories $($CATEGORIES -join ",") --format json --vault $Vault --long | ConvertFrom-Json

# filter for untagged items and print the results
$items | Where-Object { 
    # no tags at all
    ($null -eq $_.tags) -or
    # only exclude tags
    ($_.tags -is [array] -and ($_.tags | Where-Object { $_ -notlike $EXCLUDE_TAGS } | Measure-Object).Count -eq 0)
} | Select-Object -Property title,category,id,vault
