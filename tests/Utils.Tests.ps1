Describe "Get-WordList" {
    BeforeAll {
        . "$PSScriptRoot\..\Utils.ps1"
    }

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
        # Mock throws so any download attempt fails the test
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

Describe "New-MemorablePassword" {
    # All test words are 4 characters for predictable length arithmetic
    $knownWords = @("able", "bird", "calm", "desk", "edge", "fire", "gold", "hike")

    BeforeAll {
        . "$PSScriptRoot\..\Utils.ps1"
    }

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
        $result | Should Match '^[a-z]+$'
    }

    It "contains no truncated words with a digits recipe" {
        # With 4-char words: segments between digits must all be complete words
        $result = New-MemorablePassword -RecipeParts @("words", "digits") -Length 20
        $wordSegments = $result -split '\d' | Where-Object { $_ -ne '' }
        foreach ($segment in $wordSegments) {
            $knownWords -contains $segment | Should Be $true
        }
    }

    It "contains no truncated words with a symbols recipe" {
        $result = New-MemorablePassword -RecipeParts @("words", "symbols") -Length 20
        $wordSegments = $result -split '[!@#$%^&*\-_]' | Where-Object { $_ -ne '' }
        foreach ($segment in $wordSegments) {
            $knownWords -contains $segment | Should Be $true
        }
    }

    It "always includes at least one digit with a words,digits recipe" {
        # word(4) + digit(1) pattern guarantees digits appear for any length > 4
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
