# ── Shared test fixtures ──────────────────────────────────────────────────────

function New-FakeDetails {
    param(
        [switch]$WithPassword,
        [switch]$WithRotationField,
        [long]$RotationTimestamp = 0,
        [string]$RecipeValue = '',
        [string[]]$Tags = @(),
        [switch]$WithSignInWith
    )
    $fields = @()
    if ($WithPassword) {
        $fields += [PSCustomObject]@{ id = "password"; label = "password"; value = "secret" }
    }
    if ($WithRotationField) {
        $fields += [PSCustomObject]@{ id = "rot"; label = "last password update"; value = $RotationTimestamp }
    }
    if ($RecipeValue) {
        $fields += [PSCustomObject]@{ id = "rec"; label = "password recipe"; value = $RecipeValue }
    }
    if ($WithSignInWith) {
        $fields += [PSCustomObject]@{ id = "sso"; label = "sign in with"; value = "Google" }
    }
    return [PSCustomObject]@{ fields = $fields; tags = $Tags }
}

function New-FakeLogin {
    param([string]$Id = "item1", [string]$Title = "Test Item")
    return [PSCustomObject]@{ id = $Id; title = $Title }
}

# ── Get-ItemField ─────────────────────────────────────────────────────────────

Describe "Get-ItemField" {
    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    It "returns field when found by id" {
        $details = New-FakeDetails -WithPassword
        $result = Get-ItemField -Details $details -Id "password"
        $result | Should Not Be $null
        $result.value | Should Be "secret"
    }

    It "returns null when field id does not exist" {
        $details = New-FakeDetails
        $result = Get-ItemField -Details $details -Id "password"
        $result | Should Be $null
    }

    It "returns field when found by label" {
        $details = New-FakeDetails -RecipeValue "words,digits,32"
        $result = Get-ItemField -Details $details -Label "password recipe"
        $result | Should Not Be $null
        $result.value | Should Be "words,digits,32"
    }

    It "returns null when field label does not exist" {
        $details = New-FakeDetails
        $result = Get-ItemField -Details $details -Label "password recipe"
        $result | Should Be $null
    }
}

# ── Test-ItemExcluded ─────────────────────────────────────────────────────────

Describe "Test-ItemExcluded" {
    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    It "returns true when item has a matching excluded tag" {
        $details = New-FakeDetails -Tags @("other/personal")
        Test-ItemExcluded -Details $details -Pattern "other/*" | Should Be $true
    }

    It "returns false when item has no matching excluded tag" {
        $details = New-FakeDetails -Tags @("finance", "main")
        Test-ItemExcluded -Details $details -Pattern "other/*" | Should Be $false
    }

    It "returns false when item has no tags" {
        $details = New-FakeDetails
        Test-ItemExcluded -Details $details -Pattern "other/*" | Should Be $false
    }
}

# ── Test-ItemUntagged ─────────────────────────────────────────────────────────

Describe "Test-ItemUntagged" {
    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    It "returns true when item has no tags" {
        $item = [PSCustomObject]@{ tags = $null }
        Test-ItemUntagged -Item $item -ExcludePattern "secure*" | Should Be $true
    }

    It "returns true when item has only excluded tags" {
        $item = [PSCustomObject]@{ tags = @("secure/work") }
        Test-ItemUntagged -Item $item -ExcludePattern "secure*" | Should Be $true
    }

    It "returns false when item has at least one non-excluded tag" {
        $item = [PSCustomObject]@{ tags = @("secure/work", "finance") }
        Test-ItemUntagged -Item $item -ExcludePattern "secure*" | Should Be $false
    }
}

# ── ConvertFrom-UnixDate ──────────────────────────────────────────────────────

Describe "ConvertFrom-UnixDate" {
    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    It "converts timestamp 0 to 1970-01-01" {
        $result = ConvertFrom-UnixDate -Timestamp 0
        $result.Year  | Should Be 1970
        $result.Month | Should Be 1
        $result.Day   | Should Be 1
    }

    It "converts a known timestamp to the correct date" {
        # 1609459200 = 2021-01-01 00:00:00 UTC
        $result = ConvertFrom-UnixDate -Timestamp 1609459200
        $result.Year  | Should Be 2021
        $result.Month | Should Be 1
        $result.Day   | Should Be 1
    }
}

# ── Get-PasswordRecipe ────────────────────────────────────────────────────────

Describe "Get-PasswordRecipe" {
    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    It "returns the recipe field value when present" {
        $details = New-FakeDetails -RecipeValue "words,digits,32"
        $result = Get-PasswordRecipe -Details $details -Default "letters,digits,32"
        $result | Should Be "words,digits,32"
    }

    It "returns the default when no recipe field exists" {
        $details = New-FakeDetails
        $result = Get-PasswordRecipe -Details $details -Default "letters,digits,32"
        $result | Should Be "letters,digits,32"
    }
}

# ── Test-NeedsRotationField ───────────────────────────────────────────────────

Describe "Test-NeedsRotationField" {
    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    It "returns false when item has no password field" {
        $details = New-FakeDetails
        Test-NeedsRotationField -Details $details | Should Be $false
    }

    It "returns false when item already has a rotation field" {
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp 1609459200
        Test-NeedsRotationField -Details $details | Should Be $false
    }

    It "returns true when item has a password but no rotation field" {
        $details = New-FakeDetails -WithPassword
        Test-NeedsRotationField -Details $details | Should Be $true
    }

    It "returns false when password field exists but has no value" {
        $details = [PSCustomObject]@{
            fields = @([PSCustomObject]@{ id = "password"; label = "password"; value = $null })
            tags   = @()
        }
        Test-NeedsRotationField -Details $details | Should Be $false
    }
}

# ── Get-StaleItemInfo ─────────────────────────────────────────────────────────

Describe "Get-StaleItemInfo" {
    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    It "returns null for an excluded item" {
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp 0 -Tags @("other/personal")
        $result = Get-StaleItemInfo -Login (New-FakeLogin) -Details $details -Days 90 -ExcludePattern "other/*"
        $result | Should Be $null
    }

    It "returns null when item has no password" {
        $details = New-FakeDetails -WithRotationField -RotationTimestamp 0
        $result = Get-StaleItemInfo -Login (New-FakeLogin) -Details $details -Days 90 -ExcludePattern "other/*"
        $result | Should Be $null
    }

    It "returns null when item has no rotation field" {
        $details = New-FakeDetails -WithPassword
        $result = Get-StaleItemInfo -Login (New-FakeLogin) -Details $details -Days 90 -ExcludePattern "other/*"
        $result | Should Be $null
    }

    It "returns null when item was updated within the cadence" {
        $recentTimestamp = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp $recentTimestamp
        $result = Get-StaleItemInfo -Login (New-FakeLogin) -Details $details -Days 90 -ExcludePattern "other/*"
        $result | Should Be $null
    }

    It "returns stale info when item exceeds the cadence" {
        # Timestamp 0 = 1970-01-01, definitely older than any cadence
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp 0
        $login = New-FakeLogin -Id "abc123" -Title "My Login"
        $result = Get-StaleItemInfo -Login $login -Details $details -Days 90 -ExcludePattern "other/*"
        $result             | Should Not Be $null
        $result.ID          | Should Be "abc123"
        $result.Title       | Should Be "My Login"
        $result.LastUpdate  | Should Be "1970-01-01"
        $result.DaysSinceUpdate | Should BeGreaterThan 90
    }
}

# ── Get-WordList ──────────────────────────────────────────────────────────────

Describe "Get-WordList" {
    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    It "downloads and caches the word list on first use" {
        $testCache = Join-Path $TestDrive "wordlist.txt"
        Mock Invoke-WebRequest {
            [PSCustomObject]@{ Content = "11111`table`n11112`tbird`n11113`tcalm`n" }
        }

        $result = Get-WordList -CachePath $testCache

        Test-Path $testCache | Should Be $true
        $result -contains "able" | Should Be $true
        $result -contains "bird" | Should Be $true
    }

    It "does not download when cache already exists" {
        $testCache = Join-Path $TestDrive "cached.txt"
        @("able", "bird") | Out-File $testCache -Encoding UTF8
        Mock Invoke-WebRequest { throw "Should not download" }

        { Get-WordList -CachePath $testCache } | Should Not Throw
    }

    It "filters out words shorter than 3 characters" {
        $testCache = Join-Path $TestDrive "filter-short.txt"
        Mock Invoke-WebRequest {
            [PSCustomObject]@{ Content = "11111`tab`n11112`table`n11113`tbird`n" }
        }

        $result = Get-WordList -CachePath $testCache

        $result -contains "ab"   | Should Be $false
        $result -contains "able" | Should Be $true
    }

    It "filters out words longer than 8 characters" {
        $testCache = Join-Path $TestDrive "filter-long.txt"
        Mock Invoke-WebRequest {
            [PSCustomObject]@{ Content = "11111`table`n11112`tverylongword`n" }
        }

        $result = Get-WordList -CachePath $testCache

        $result -contains "able"         | Should Be $true
        $result -contains "verylongword" | Should Be $false
    }
}

# ── New-MemorablePassword ─────────────────────────────────────────────────────

Describe "New-MemorablePassword" {
    # All test words are 4 characters for predictable length arithmetic
    $knownWords = @("able", "bird", "calm", "desk", "edge", "fire", "gold", "hike")

    BeforeAll { . "$PSScriptRoot\..\Utils.ps1" }

    BeforeEach {
        Mock Get-WordList { return @("able", "bird", "calm", "desk", "edge", "fire", "gold", "hike") }
    }

    It "returns exactly 12 characters" {
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 12
        $result.Length | Should Be 12
    }

    It "returns exactly 20 characters" {
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 20
        $result.Length | Should Be 20
    }

    It "returns exactly 32 characters" {
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 32
        $result.Length | Should Be 32
    }

    It "contains only alpha characters with a words-only recipe" {
        $result = New-MemorablePassword -RecipeParts @("words") -Length 20
        $result | Should Match '^[a-zA-Z]+$'
    }

    It "contains no truncated words with a digits recipe" {
        # With 4-char words: segments between digits must all be complete words (case-insensitive)
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 20
        $wordSegments = $result -split '\d' | Where-Object { $_ -ne '' }
        foreach ($segment in $wordSegments) {
            $knownWords -contains $segment.ToLower() | Should Be $true
        }
    }

    It "contains no truncated words with a symbols recipe" {
        $result = New-MemorablePassword -RecipeParts @("words", "symbols") -Length 20
        $wordSegments = $result -split '[!@#$%^&*\-_]' | Where-Object { $_ -ne '' }
        foreach ($segment in $wordSegments) {
            $knownWords -contains $segment.ToLower() | Should Be $true
        }
    }

    It "always includes at least one digit with a words,digits recipe" {
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 20
        $result | Should Match '\d'
    }

    It "always includes at least one symbol with a words,symbols recipe" {
        $result = New-MemorablePassword -RecipeParts @("words", "symbols") -Length 20
        $result | Should Match '[!@#$%^&*\-_]'
    }

    It "fills remainder with separators when no word fits the remaining space" {
        # Length 13 with 4-char words + digits: 2 full cycles = 10 chars, 3 remaining
        # maxWordLen becomes 2, no 2-char words in list, so fills with 3 digits
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 13
        $result.Length | Should Be 13
        $result | Should Match '\d'
    }
}
