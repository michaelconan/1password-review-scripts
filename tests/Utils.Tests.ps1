BeforeAll {
    . "$PSScriptRoot\..\Utils.ps1"

    function New-FakeDetails {
        param(
            [switch]$WithPassword,
            [switch]$WithRotationField,
            [long]$RotationTimestamp = 0,
            [string]$RecipeValue = '',
            [string[]]$Tags = @(),
            [switch]$WithSignInWith,
            [string]$Title = 'Test Item',
            [string]$Category = 'LOGIN',
            [string]$VaultName = 'private',
            [string]$CreatedAt = '2020-01-01T00:00:00Z',
            [string]$Username = ''
        )
        $fields = @()
        if ($Username) {
            $fields += [PSCustomObject]@{ id = "username"; label = "username"; value = $Username }
        }
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
        return [PSCustomObject]@{
            id         = "item1"
            title      = $Title
            category   = $Category
            created_at = $CreatedAt
            vault      = [PSCustomObject]@{ name = $VaultName }
            fields     = $fields
            tags       = $Tags
        }
    }

    function New-FakeLogin {
        param([string]$Id = "item1", [string]$Title = "Test Item")
        return [PSCustomObject]@{ id = $Id; title = $Title }
    }
}

# ── Get-ItemField ─────────────────────────────────────────────────────────────

Describe "Get-VaultItems" {
    It "passes filters to op and parses the item list" {
        Mock op {
            $script:CapturedOpArgs = $args
            return '[{"id":"one","title":"One"}]'
        }

        $result = Get-VaultItems -Vault "private" -Categories @("login", "password") -Tag "finance" -Long

        $result.Count | Should -Be 1
        $result[0].id | Should -Be "one"
        $script:CapturedOpArgs | Should -Contain "--vault"
        $script:CapturedOpArgs | Should -Contain "private"
        $script:CapturedOpArgs | Should -Contain "--categories"
        $script:CapturedOpArgs | Should -Contain "login,password"
        $script:CapturedOpArgs | Should -Contain "--tags"
        $script:CapturedOpArgs | Should -Contain "finance"
        $script:CapturedOpArgs | Should -Contain "--long"
    }

    It "omits optional filters when they are not supplied" {
        Mock op {
            $script:CapturedOpArgs = $args
            return '[]'
        }

        $result = Get-VaultItems -Vault "private"

        $result.Count | Should -Be 0
        $script:CapturedOpArgs | Should -Contain "--vault"
        $script:CapturedOpArgs | Should -Not -Contain "--categories"
        $script:CapturedOpArgs | Should -Not -Contain "--tags"
        $script:CapturedOpArgs | Should -Not -Contain "--long"
    }
}

# ── Get-ItemDetail ────────────────────────────────────────────────────────────

Describe "Test-OpTransientError" {
    It "returns true for known transient op messages" {
        Test-OpTransientError "request timed out while connecting to desktop app" | Should -Be $true
    }

    It "returns false for non-transient op messages" {
        Test-OpTransientError "authentication required" | Should -Be $false
    }
}

Describe "Get-ItemDetail" {
    It "passes the vault to op and parses item details" {
        Mock op {
            $script:CapturedOpArgs = $args
            $global:LASTEXITCODE = 0
            return '{"id":"abc","title":"Example"}'
        }

        $result = Get-ItemDetail -Id "abc" -Vault "private"

        $result.id | Should -Be "abc"
        $script:CapturedOpArgs | Should -Contain "--vault"
        $script:CapturedOpArgs | Should -Contain "private"
    }

    It "retries transient op failures before returning details" {
        $script:AttemptCount = 0
        Mock op {
            $script:AttemptCount++
            if ($script:AttemptCount -eq 1) {
                $global:LASTEXITCODE = 1
                return "timed out while connecting to desktop app"
            }
            $global:LASTEXITCODE = 0
            return '{"id":"retry-ok"}'
        }

        $result = Get-ItemDetail -Id "retry-ok" -MaxRetries 2 -RetryDelayMs 0

        $result.id | Should -Be "retry-ok"
        $script:AttemptCount | Should -Be 2
    }

    It "throws non-transient op errors without retrying" {
        $script:AttemptCount = 0
        Mock op {
            $script:AttemptCount++
            $global:LASTEXITCODE = 1
            return "authentication required"
        }

        { Get-ItemDetail -Id "abc" -MaxRetries 2 -RetryDelayMs 0 } | Should -Throw "*authentication required*"
        $script:AttemptCount | Should -Be 1
    }
}

# ── Get-ItemDetails ───────────────────────────────────────────────────────────

Describe "Get-ItemDetails" {
    It "returns an empty array when no items are supplied" {
        $result = Get-ItemDetails -Items @()
        $result.Count | Should -Be 0
    }

    It "fetches item details in worker runspaces" {
        $shimDir = Join-Path $TestDrive "bin"
        New-Item -ItemType Directory -Path $shimDir | Out-Null
        $opShim = Join-Path $shimDir "op.cmd"
        @(
            "@echo off"
            "echo {""id"":""%5"",""title"":""Title %5""}"
        ) | Set-Content -Path $opShim -Encoding ASCII

        $oldPath = $env:PATH
        $env:PATH = "$shimDir;$oldPath"

        try {
            $items = @(
                [PSCustomObject]@{ id = "one"; title = "One" },
                [PSCustomObject]@{ id = "two"; title = "Two" }
            )

            $result = Get-ItemDetails -Items $items -ThrottleLimit 2

            $result.Count | Should -Be 2
            $result[0].Login.title | Should -Be "One"
            $result[0].Details.id | Should -Be "one"
            $result[1].Login.title | Should -Be "Two"
            $result[1].Details.id | Should -Be "two"
        } finally {
            $env:PATH = $oldPath
        }
    }
}

Describe "Get-ItemField" {
    It "returns field when found by id" {
        $details = New-FakeDetails -WithPassword
        $result = Get-ItemField -Details $details -Id "password"
        $result | Should -Not -BeNullOrEmpty
        $result.value | Should -Be "secret"
    }

    It "returns null when field id does not exist" {
        $details = New-FakeDetails
        $result = Get-ItemField -Details $details -Id "password"
        $result | Should -BeNullOrEmpty
    }

    It "returns field when found by label" {
        $details = New-FakeDetails -RecipeValue "words,digits,32"
        $result = Get-ItemField -Details $details -Label "password recipe"
        $result | Should -Not -BeNullOrEmpty
        $result.value | Should -Be "words,digits,32"
    }

    It "returns null when field label does not exist" {
        $details = New-FakeDetails
        $result = Get-ItemField -Details $details -Label "password recipe"
        $result | Should -BeNullOrEmpty
    }
}

# ── Test-ItemExcluded ─────────────────────────────────────────────────────────

Describe "Test-ItemExcluded" {
    It "returns true when item has a matching excluded tag" {
        $details = New-FakeDetails -Tags @("other/personal")
        Test-ItemExcluded -Details $details -Pattern "other/*" | Should -Be $true
    }

    It "returns false when item has no matching excluded tag" {
        $details = New-FakeDetails -Tags @("finance", "main")
        Test-ItemExcluded -Details $details -Pattern "other/*" | Should -Be $false
    }

    It "returns false when item has no tags" {
        $details = New-FakeDetails
        Test-ItemExcluded -Details $details -Pattern "other/*" | Should -Be $false
    }
}

# ── Test-ItemUntagged ─────────────────────────────────────────────────────────

Describe "Test-ItemUntagged" {
    It "returns true when item has no tags" {
        $item = [PSCustomObject]@{ tags = $null }
        Test-ItemUntagged -Item $item -ExcludePattern "secure*" | Should -Be $true
    }

    It "returns true when item has only excluded tags" {
        $item = [PSCustomObject]@{ tags = @("secure/work") }
        Test-ItemUntagged -Item $item -ExcludePattern "secure*" | Should -Be $true
    }

    It "returns false when item has at least one non-excluded tag" {
        $item = [PSCustomObject]@{ tags = @("secure/work", "finance") }
        Test-ItemUntagged -Item $item -ExcludePattern "secure*" | Should -Be $false
    }
}

# ── ConvertFrom-UnixDate ──────────────────────────────────────────────────────

Describe "ConvertFrom-UnixDate" {
    It "converts timestamp 0 to 1970-01-01" {
        $result = ConvertFrom-UnixDate -Timestamp 0
        $result.Year  | Should -Be 1970
        $result.Month | Should -Be 1
        $result.Day   | Should -Be 1
    }

    It "converts a known timestamp to the correct date" {
        # 1609459200 = 2021-01-01 00:00:00 UTC
        $result = ConvertFrom-UnixDate -Timestamp 1609459200
        $result.Year  | Should -Be 2021
        $result.Month | Should -Be 1
        $result.Day   | Should -Be 1
    }
}

# ── Get-PasswordRecipe ────────────────────────────────────────────────────────

Describe "Get-PasswordRecipe" {
    It "returns the recipe field value when present" {
        $details = New-FakeDetails -RecipeValue "words,digits,32"
        $result = Get-PasswordRecipe -Details $details -Default "letters,digits,32"
        $result | Should -Be "words,digits,32"
    }

    It "returns the default when no recipe field exists" {
        $details = New-FakeDetails
        $result = Get-PasswordRecipe -Details $details -Default "letters,digits,32"
        $result | Should -Be "letters,digits,32"
    }
}

# ── Test-NeedsRotationField ───────────────────────────────────────────────────

Describe "Test-NeedsRotationField" {
    It "returns false when item has no password field" {
        $details = New-FakeDetails
        Test-NeedsRotationField -Details $details | Should -Be $false
    }

    It "returns false when item already has a rotation field" {
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp 1609459200
        Test-NeedsRotationField -Details $details | Should -Be $false
    }

    It "returns true when item has a password but no rotation field" {
        $details = New-FakeDetails -WithPassword
        Test-NeedsRotationField -Details $details | Should -Be $true
    }

    It "returns false when password field exists but has no value" {
        $details = [PSCustomObject]@{
            fields = @([PSCustomObject]@{ id = "password"; label = "password"; value = $null })
            tags   = @()
        }
        Test-NeedsRotationField -Details $details | Should -Be $false
    }
}

# ── Get-StaleItemInfo ─────────────────────────────────────────────────────────

Describe "Get-StaleItemInfo" {
    It "returns null for an excluded item" {
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp 0 -Tags @("other/personal")
        $result = Get-StaleItemInfo -Login (New-FakeLogin) -Details $details -Days 90 -ExcludePattern "other/*"
        $result | Should -BeNullOrEmpty
    }

    It "returns null when item has no password" {
        $details = New-FakeDetails -WithRotationField -RotationTimestamp 0
        $result = Get-StaleItemInfo -Login (New-FakeLogin) -Details $details -Days 90 -ExcludePattern "other/*"
        $result | Should -BeNullOrEmpty
    }

    It "returns null when item has no rotation field" {
        $details = New-FakeDetails -WithPassword
        $result = Get-StaleItemInfo -Login (New-FakeLogin) -Details $details -Days 90 -ExcludePattern "other/*"
        $result | Should -BeNullOrEmpty
    }

    It "returns null when item was updated within the cadence" {
        $recentTimestamp = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp $recentTimestamp
        $result = Get-StaleItemInfo -Login (New-FakeLogin) -Details $details -Days 90 -ExcludePattern "other/*"
        $result | Should -BeNullOrEmpty
    }

    It "returns stale info when item exceeds the cadence" {
        # Timestamp 0 = 1970-01-01, definitely older than any cadence
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp 0
        $login = New-FakeLogin -Id "abc123" -Title "My Login"
        $result = Get-StaleItemInfo -Login $login -Details $details -Days 90 -ExcludePattern "other/*"
        $result             | Should -Not -BeNullOrEmpty
        $result.ID          | Should -Be "abc123"
        $result.Title       | Should -Be "My Login"
        $result.LastUpdate  | Should -Be "1970-01-01"
        $result.DaysSinceUpdate | Should -BeGreaterThan 90
    }
}

# ── Test-ItemSso ─────────────────────────────────────────────────────────────

Describe "Test-ItemSso" {
    It "returns true when item has a 'sign in with' field" {
        $details = New-FakeDetails -WithSignInWith
        Test-ItemSso -Details $details -SsoTag "secure/sso" | Should -Be $true
    }

    It "returns true when item has the SSO tag" {
        $details = New-FakeDetails -Tags @("secure/sso")
        Test-ItemSso -Details $details -SsoTag "secure/sso" | Should -Be $true
    }

    It "returns false when item has neither a sign-in field nor the SSO tag" {
        $details = New-FakeDetails
        Test-ItemSso -Details $details -SsoTag "secure/sso" | Should -Be $false
    }
}

# ── Test-ItemMfa ──────────────────────────────────────────────────────────────

Describe "Test-ItemMfa" {
    It "returns true when item has the MFA tag" {
        $details = New-FakeDetails -Tags @("secure/mfa")
        Test-ItemMfa -Details $details -MfaTag "secure/mfa" | Should -Be $true
    }

    It "returns false when item does not have the MFA tag" {
        $details = New-FakeDetails -Tags @("finance")
        Test-ItemMfa -Details $details -MfaTag "secure/mfa" | Should -Be $false
    }
}

# ── Get-ItemExtendedInfo ──────────────────────────────────────────────────────

Describe "Get-ItemExtendedInfo" {
    It "returns null for an excluded item" {
        $details = New-FakeDetails -Tags @("other/personal")
        $result = Get-ItemExtendedInfo -Details $details -ExcludePattern "other/*" -SsoTag "secure/sso" -MfaTag "secure/mfa"
        $result | Should -BeNullOrEmpty
    }

    It "includes SSO in Security when item has a sign-in field" {
        $details = New-FakeDetails -WithSignInWith
        $result = Get-ItemExtendedInfo -Details $details -ExcludePattern "other/*" -SsoTag "secure/sso" -MfaTag "secure/mfa"
        $result.Security | Should -Be "SSO"
    }

    It "includes MFA in Security when item has the MFA tag" {
        $details = New-FakeDetails -Tags @("secure/mfa")
        $result = Get-ItemExtendedInfo -Details $details -ExcludePattern "other/*" -SsoTag "secure/sso" -MfaTag "secure/mfa"
        $result.Security | Should -Be "MFA"
    }

    It "includes both SSO and MFA when both apply" {
        $details = New-FakeDetails -WithSignInWith -Tags @("secure/mfa")
        $result = Get-ItemExtendedInfo -Details $details -ExcludePattern "other/*" -SsoTag "secure/sso" -MfaTag "secure/mfa"
        $result.Security | Should -Be "SSO,MFA"
    }

    It "falls back to created_at date when no rotation field is present" {
        $details = New-FakeDetails -WithPassword -CreatedAt "2022-06-15T00:00:00Z"
        $result = Get-ItemExtendedInfo -Details $details -ExcludePattern "other/*" -SsoTag "secure/sso" -MfaTag "secure/mfa"
        $result.LastPwUpdate | Should -Be "2022-06-15"
    }

    It "uses the rotation field date when present" {
        # 1609459200 = 2021-01-01
        $details = New-FakeDetails -WithPassword -WithRotationField -RotationTimestamp 1609459200
        $result = Get-ItemExtendedInfo -Details $details -ExcludePattern "other/*" -SsoTag "secure/sso" -MfaTag "secure/mfa"
        $result.LastPwUpdate | Should -Be "2021-01-01"
    }

    It "returns null recipe and dates for an item without a password" {
        $details = New-FakeDetails
        $result = Get-ItemExtendedInfo -Details $details -ExcludePattern "other/*" -SsoTag "secure/sso" -MfaTag "secure/mfa"
        $result         | Should -Not -BeNullOrEmpty
        $result.Recipe  | Should -BeNullOrEmpty
        $result.LastPwUpdate | Should -BeNullOrEmpty
        $result.DaysSince    | Should -BeNullOrEmpty
    }

    It "populates item metadata from Details" {
        $details = New-FakeDetails -Title "My Login" -Category "LOGIN" -VaultName "shared" -Username "user@example.com"
        $result = Get-ItemExtendedInfo -Details $details -ExcludePattern "other/*" -SsoTag "secure/sso" -MfaTag "secure/mfa"
        $result.Title    | Should -Be "My Login"
        $result.Category | Should -Be "LOGIN"
        $result.Vault    | Should -Be "shared"
        $result.Username | Should -Be "user@example.com"
    }
}

# ── Get-WordList ──────────────────────────────────────────────────────────────

Describe "Get-WordList" {
    It "downloads and caches the word list on first use" {
        $testCache = Join-Path $TestDrive "wordlist.txt"
        Mock Invoke-WebRequest {
            [PSCustomObject]@{ Content = "11111`table`n11112`tbird`n11113`tcalm`n" }
        }

        $result = Get-WordList -CachePath $testCache

        Test-Path $testCache | Should -Be $true
        $result | Should -Contain "able"
        $result | Should -Contain "bird"
    }

    It "creates the cache directory when it is missing" {
        $testCache = Join-Path (Join-Path $TestDrive "nested") "wordlist.txt"
        Mock Invoke-WebRequest {
            [PSCustomObject]@{ Content = "11111`table`n11112`tbird`n" }
        }

        $result = Get-WordList -CachePath $testCache

        Test-Path (Split-Path $testCache) | Should -Be $true
        Test-Path $testCache | Should -Be $true
        $result | Should -Contain "able"
    }

    It "reads words from an existing cache" {
        $testCache = Join-Path $TestDrive "cached-read.txt"
        @("able", "bird") | Out-File $testCache -Encoding UTF8
        Mock Invoke-WebRequest { throw "Should not download" }

        $result = Get-WordList -CachePath $testCache

        $result | Should -Contain "able"
        $result | Should -Contain "bird"
    }

    It "does not download when cache already exists" {
        $testCache = Join-Path $TestDrive "cached.txt"
        @("able", "bird") | Out-File $testCache -Encoding UTF8
        Mock Invoke-WebRequest { throw "Should not download" }

        { Get-WordList -CachePath $testCache } | Should -Not -Throw
    }

    It "filters out words shorter than 3 characters" {
        $testCache = Join-Path $TestDrive "filter-short.txt"
        Mock Invoke-WebRequest {
            [PSCustomObject]@{ Content = "11111`tab`n11112`table`n11113`tbird`n" }
        }

        $result = Get-WordList -CachePath $testCache

        $result | Should -Not -Contain "ab"
        $result | Should -Contain "able"
    }

    It "filters out words longer than 8 characters" {
        $testCache = Join-Path $TestDrive "filter-long.txt"
        Mock Invoke-WebRequest {
            [PSCustomObject]@{ Content = "11111`table`n11112`tverylongword`n" }
        }

        $result = Get-WordList -CachePath $testCache

        $result | Should -Contain "able"
        $result | Should -Not -Contain "verylongword"
    }
}

# ── New-MemorablePassword ─────────────────────────────────────────────────────

Describe "New-MemorablePassword" {
    BeforeAll {
        # All test words are 4 characters for predictable length arithmetic
        $knownWords = @("able", "bird", "calm", "desk", "edge", "fire", "gold", "hike")
    }

    BeforeEach {
        Mock Get-WordList { return $knownWords }
    }

    It "returns exactly 12 characters" {
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 12
        $result.Length | Should -Be 12
    }

    It "returns exactly 20 characters" {
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 20
        $result.Length | Should -Be 20
    }

    It "returns exactly 32 characters" {
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 32
        $result.Length | Should -Be 32
    }

    It "contains only alpha characters with a words-only recipe" {
        $result = New-MemorablePassword -RecipeParts @("words") -Length 20
        $result | Should -Match '^[a-zA-Z]+$'
    }

    It "contains no truncated words with a digits recipe" {
        # With 4-char words: segments between digits must all be complete words (case-insensitive)
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 20
        $wordSegments = $result -split '\d' | Where-Object { $_ -ne '' }
        foreach ($segment in $wordSegments) {
            $knownWords | Should -Contain $segment.ToLower()
        }
    }

    It "contains no truncated words with a symbols recipe" {
        $result = New-MemorablePassword -RecipeParts @("words", "symbols") -Length 20
        $wordSegments = $result -split '[!@#$%^&*\-_]' | Where-Object { $_ -ne '' }
        foreach ($segment in $wordSegments) {
            $knownWords | Should -Contain $segment.ToLower()
        }
    }

    It "always includes at least one digit with a words,digits recipe" {
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 20
        $result | Should -Match '\d'
    }

    It "always includes at least one symbol with a words,symbols recipe" {
        $result = New-MemorablePassword -RecipeParts @("words", "symbols") -Length 20
        $result | Should -Match '[!@#$%^&*\-_]'
    }

    It "fills remainder with separators when no word fits the remaining space" {
        # Length 13 with 4-char words + digits: 2 full cycles = 10 chars, 3 remaining
        # maxWordLen becomes 2, no 2-char words in list, so fills with 3 digits
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 13
        $result.Length | Should -Be 13
        $result | Should -Match '\d'
    }

    It "fills a short words-only password with lowercase letters when no word fits" {
        $result = New-MemorablePassword -RecipeParts @("words") -Length 2

        $result.Length | Should -Be 2
        $result | Should -Match '^[a-z]{2}$'
    }
}
