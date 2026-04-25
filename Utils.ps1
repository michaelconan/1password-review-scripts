# ── 1Password CLI wrappers ────────────────────────────────────────────────────

function Get-VaultItems {
    param(
        [string]$Vault,
        [string[]]$Categories,
        [string]$Tag = '',
        [switch]$Long
    )
    $opArgs = @("--categories", ($Categories -join ","), "--format", "json", "--vault", $Vault)
    if ($Tag)  { $opArgs += "--tags",  $Tag }
    if ($Long) { $opArgs += "--long" }
    op item list @opArgs | ConvertFrom-Json
}

function Get-ItemDetail {
    param([string]$Id, [string]$Vault = '')
    $opArgs = @("--format", "json", $Id)
    if ($Vault) { $opArgs += "--vault", $Vault }
    op item get @opArgs | ConvertFrom-Json
}

# ── Item field helpers ────────────────────────────────────────────────────────

function Get-ItemField {
    param($Details, [string]$Id = '', [string]$Label = '')
    if ($Id) {
        return $Details.fields | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    }
    return $Details.fields | Where-Object { $_.label -eq $Label } | Select-Object -First 1
}

# ── Tag helpers ───────────────────────────────────────────────────────────────

function Test-ItemExcluded {
    param($Details, [string]$Pattern)
    $excludeTags = $Details.tags | Where-Object { $_ -like $Pattern }
    return $excludeTags.Count -gt 0
}

function Test-ItemUntagged {
    param($Item, [string]$ExcludePattern)
    if ($null -eq $Item.tags) { return $true }
    $significantTags = $Item.tags | Where-Object { $_ -notlike $ExcludePattern }
    return $significantTags.Count -eq 0
}

# ── Date helpers ──────────────────────────────────────────────────────────────

function ConvertFrom-UnixDate {
    param([long]$Timestamp)
    return ([System.DateTimeOffset]::FromUnixTimeSeconds($Timestamp)).DateTime
}

# ── Parallel item detail fetching ────────────────────────────────────────────

function Get-ItemDetails {
    param($Items, [int]$ThrottleLimit = 10)

    if (-not $Items -or $Items.Count -eq 0) { return @() }

    $pool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
    $pool.Open()

    $jobs = $Items | ForEach-Object {
        $itemId = $_.id
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript({
            param($id)
            op item get --format json $id | ConvertFrom-Json
        }).AddArgument($itemId)
        [PSCustomObject]@{ PS = $ps; Token = $ps.BeginInvoke(); Login = $_ }
    }

    $total = $jobs.Count
    while (($jobs | Where-Object { -not $_.Token.IsCompleted }).Count -gt 0) {
        $done = ($jobs | Where-Object { $_.Token.IsCompleted }).Count
        Write-Progress -Activity "Fetching item details" `
            -Status "$done / $total complete" `
            -PercentComplete (($done / $total) * 100)
        Start-Sleep -Milliseconds 200
    }
    Write-Progress -Activity "Fetching item details" -Completed

    $results = $jobs | ForEach-Object {
        [PSCustomObject]@{
            Login   = $_.Login
            Details = $_.PS.EndInvoke($_.Token)[0]
        }
        $_.PS.Dispose()
    }

    $pool.Close()
    $pool.Dispose()
    return $results
}

# ── Business logic ────────────────────────────────────────────────────────────

function Get-StaleItemInfo {
    param($Login, $Details, [int]$Days, [string]$ExcludePattern)

    if (Test-ItemExcluded -Details $Details -Pattern $ExcludePattern) { return $null }

    $passwordField = Get-ItemField -Details $Details -Id "password"
    if ($null -eq $passwordField -or $null -eq $passwordField.value) { return $null }

    $lastUpdateField = Get-ItemField -Details $Details -Label "last password update"
    if ($null -eq $lastUpdateField) { return $null }

    $lastUpdateDate = ConvertFrom-UnixDate -Timestamp ([long]$lastUpdateField.value)
    $daysSince = (New-TimeSpan -Start $lastUpdateDate -End (Get-Date)).Days

    if ($daysSince -le $Days) { return $null }

    return [PSCustomObject]@{
        Title           = $Login.title
        ID              = $Login.id
        LastUpdate      = $lastUpdateDate.ToString("yyyy-MM-dd")
        DaysSinceUpdate = $daysSince
    }
}

function Test-NeedsRotationField {
    param($Details)
    $passwordField = Get-ItemField -Details $Details -Id "password"
    if ($null -eq $passwordField -or $null -eq $passwordField.value) { return $false }
    $updateField = Get-ItemField -Details $Details -Label "last password update"
    return $null -eq $updateField
}

function Get-PasswordRecipe {
    param($Details, [string]$Default)
    $recipeField = Get-ItemField -Details $Details -Label "password recipe"
    if ($null -ne $recipeField -and $null -ne $recipeField.value) {
        return $recipeField.value
    }
    return $Default
}

# ── Password generation ───────────────────────────────────────────────────────

$WORDLIST_URL = "https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt"
$WORDLIST_CACHE = Join-Path $env:LOCALAPPDATA "1password-scripts\eff-wordlist.txt"

function Get-WordList {
    param([string]$CachePath = $WORDLIST_CACHE)

    if (-not (Test-Path $CachePath)) {
        Write-Verbose "Downloading EFF wordlist..."
        $cacheDir = Split-Path $CachePath
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir | Out-Null
        }
        $raw = Invoke-WebRequest -Uri $WORDLIST_URL -UseBasicParsing
        $raw.Content -split "`n" |
            Where-Object { $_ -match '^\d+\t\w+$' } |
            ForEach-Object { ($_ -split "`t")[1].Trim() } |
            Where-Object { $_.Length -ge 3 -and $_.Length -le 8 } |
            Out-File -FilePath $CachePath -Encoding UTF8
    }
    return @(Get-Content -Path $CachePath)
}

function New-MemorablePassword {
    param([string[]]$RecipeParts, [int]$Length)

    $wordList = Get-WordList

    $separators = @()
    if ('digits' -in $RecipeParts) { $separators += '0123456789'.ToCharArray() }
    if ('symbols' -in $RecipeParts) { $separators += '!@#$%^&*-_'.ToCharArray() }
    $hasSeparator = $separators.Count -gt 0

    $password = [System.Text.StringBuilder]::new()

    while ($password.Length -lt $Length) {
        $remaining = $Length - $password.Length

        # Reserve 1 char for a separator so every word is followed by one
        $maxWordLen = if ($hasSeparator -and $remaining -gt 1) { $remaining - 1 } else { $remaining }

        $candidates = @($wordList | Where-Object { $_.Length -le $maxWordLen })

        if ($candidates.Count -eq 0) {
            # No whole word fits; fill the remainder char-by-char
            $fillChars = if ($hasSeparator) { $separators } else { 'abcdefghijklmnopqrstuvwxyz'.ToCharArray() }
            while ($password.Length -lt $Length) {
                [void]$password.Append(($fillChars | Get-Random))
            }
            break
        }

        [void]$password.Append(($candidates | Get-Random))

        if ($hasSeparator -and $password.Length -lt $Length) {
            [void]$password.Append(($separators | Get-Random))
        }
    }

    return $password.ToString()
}
