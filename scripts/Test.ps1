#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$IncludeCoverage
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testPath = Join-Path $repoRoot 'tests'
$coveragePath = Join-Path $repoRoot 'Utils.ps1'
$reportDir = Join-Path $repoRoot 'coverage'

# We don't want to install Pester inside the script if we can avoid it,
# but we'll keep a check for a minimum version if needed.
# However, Pester 5 is significantly different, so we'll just assume it's there
# or let the CI handle installation.

$config = New-PesterConfiguration
$config.Run.Path = $testPath
$config.Run.Exit = $true
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $reportDir 'test-results.xml'
$config.TestResult.OutputFormat = 'NUnitXml'

if ($IncludeCoverage) {
    if (-not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir | Out-Null
    }
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $coveragePath
    $config.CodeCoverage.OutputPath = Join-Path $reportDir 'coverage.xml'
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
}

$result = Invoke-Pester -Configuration $config

# Pester 5 returns a different object structure
if ($IncludeCoverage.IsPresent) {
    $coverageReport = $result.CodeCoverage
    if ($null -eq $coverageReport) {
        Write-Warning 'Coverage was requested but no coverage data was returned.'
    } else {
        $pct = if ($coverageReport.TotalCount -gt 0) {
            [math]::Round(($coverageReport.HitCount / $coverageReport.TotalCount) * 100, 2)
        } else {
            0
        }

        $summary = @(
            "Code coverage: $pct%"
            "Commands covered: $($coverageReport.HitCount) / $($coverageReport.TotalCount)"
            "File: Utils.ps1"
        ) -join [Environment]::NewLine

        Write-Host $summary
        $summaryPath = Join-Path $reportDir 'summary.txt'
        Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

        # In Pester 5, MissedCommands might be handled differently,
        # but let's see if we can still extract them for the summary.
        # It's an array of coverage objects.
        $missed = @($coverageReport.MissedCommands)
        if ($missed.Count -gt 0) {
            $missedPath = Join-Path $reportDir 'missed-commands.txt'
            $missed |
                Sort-Object StartLine |
                Format-Table StartLine, StartColumn, Text -AutoSize |
                Out-String -Width 200 |
                Set-Content -Path $missedPath -Encoding UTF8
        }
    }
}

if ($result.FailedCount -gt 0) {
    exit 1
}
