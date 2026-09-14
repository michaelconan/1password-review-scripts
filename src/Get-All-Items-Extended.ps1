<#
    .SYNOPSIS
    Retrieve all 1Password items with SSO, MFA, and last password update fields.

    .DESCRIPTION
    This script retrieves all items from one or all 1Password vaults and enriches each with
    computed security metadata: whether the item uses SSO (detected via a "sign in with" field
    or the "secure/sso" tag), whether it has MFA (via the "secure/mfa" tag), the last password
    update date, and the password recipe. Items tagged "other/*" are excluded. Results are
    exported to a CSV file for further analysis or reporting. Full item details can optionally
    also be written as one JSON file per item. Concealed fields are always masked in those files.

    .PARAMETER Vault
    The name of the vault to retrieve items from. Default is "private".

    .PARAMETER AllVaults
    Retrieve items from every vault visible to the authenticated account. Cannot be combined
    with an explicit vault selection.

    .PARAMETER ExportPath
    Path for the output CSV file. Default is "items.csv" in the current directory.

    .PARAMETER JsonExportPath
    Optional directory for one full-detail JSON file per item. Concealed fields are masked.

    .EXAMPLE
    PS> .\src\Get-All-Items-Extended.ps1

    .EXAMPLE
    PS> .\src\Get-All-Items-Extended.ps1 -Vault Shared -ExportPath "C:\reports\vault.csv"

    .EXAMPLE
    PS> .\src\Get-All-Items-Extended.ps1 -AllVaults -JsonExportPath .\items-json
#>

param(
    [string]$Vault = "private",
    [switch]$AllVaults,
    [string]$ExportPath = "items.csv",
    [string]$JsonExportPath = ""
)

. "$PSScriptRoot\Utils.ps1"

$SSO_TAG     = "secure/sso"
$MFA_TAG     = "secure/mfa"
$EXCLUDE_TAG = "other/*"

function Get-ItemJsonPath {
    param($Item, [string]$Root)

    $vaultName = if ($Item.vault -and $Item.vault.name) { $Item.vault.name } else { $Item.vault }
    $safeVault = [regex]::Replace([string]$vaultName, '[^a-zA-Z0-9._-]', '_')
    $safeId = [regex]::Replace([string]$Item.id, '[^a-zA-Z0-9._-]', '_')
    return Join-Path $Root "$safeVault`_$safeId.json"
}

if ($AllVaults -and $PSBoundParameters.ContainsKey('Vault')) {
    throw "-AllVaults cannot be combined with -Vault."
}

$vaults = if ($AllVaults) {
    @(Get-Vaults)
} else {
    @([PSCustomObject]@{ id = $Vault; name = $Vault })
}

$items = @(
    foreach ($selectedVault in $vaults) {
        $vaultItems = @(Get-VaultItems -Vault $selectedVault.id -Long)
        foreach ($item in $vaultItems) {
            if (-not $item.PSObject.Properties['vault']) {
                $item | Add-Member -MemberType NoteProperty -Name vault -Value $selectedVault
            }
            $item
        }
        Write-Information "Found $($vaultItems.Count) items in vault $($selectedVault.name)" -InformationAction Continue
    }
)
Write-Output "Found $($items.Count) items across $($vaults.Count) vault(s)"

$cachedDetails = @()
$itemsToFetch = @($items)
if ($JsonExportPath) {
    if (-not (Test-Path $JsonExportPath)) {
        New-Item -ItemType Directory -Path $JsonExportPath -Force | Out-Null
    }

    $itemsToFetch = @()
    foreach ($item in $items) {
        $jsonPath = Get-ItemJsonPath -Item $item -Root $JsonExportPath
        if (-not (Test-Path $jsonPath) -or -not $item.PSObject.Properties['updated_at']) {
            $itemsToFetch += $item
            continue
        }

        try {
            $cached = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        } catch {
            $cached = $null
        }

        if ($cached -and $cached.PSObject.Properties['updated_at'] -and
            [string]$cached.updated_at -eq [string]$item.updated_at) {
            $cachedDetails += [PSCustomObject]@{ Login = $item; Details = $cached }
        } else {
            $itemsToFetch += $item
        }
    }

    Write-Output "Reused $($cachedDetails.Count) cached item details; fetching $($itemsToFetch.Count) item details"
}

$details = @($cachedDetails) + @(Get-ItemDetails -Items $itemsToFetch)

if ($JsonExportPath) {
    $jsonExported = 0
    $jsonSkipped = 0
    foreach ($entry in $details) {
        $jsonPath = Get-ItemJsonPath -Item $entry.Login -Root $JsonExportPath
        $protected = Protect-ConcealedFields -Value $entry.Details
        $json = $protected | ConvertTo-Json -Depth 100
        if (Test-FileContentChanged -Path $jsonPath -Content $json) {
            $json | Set-Content -Path $jsonPath -Encoding UTF8
            $jsonExported++
        } else {
            $jsonSkipped++
        }
    }
    Write-Output "Exported $jsonExported detailed item JSON files to $JsonExportPath; skipped $jsonSkipped unchanged"
}

$results = @($details | ForEach-Object {
    Get-ItemExtendedInfo -Details $_.Details -ExcludePattern $EXCLUDE_TAG -SsoTag $SSO_TAG -MfaTag $MFA_TAG
} | Where-Object { $null -ne $_ })

$csv = (($results | Sort-Object -Property DaysSince -Descending | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine)
if (Test-FileContentChanged -Path $ExportPath -Content $csv) {
    $csv | Set-Content -Path $ExportPath -Encoding UTF8
    Write-Output "Exported $($results.Count) items to $ExportPath"
} else {
    Write-Output "Skipped $ExportPath because it is unchanged"
}
