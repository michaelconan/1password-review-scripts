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
