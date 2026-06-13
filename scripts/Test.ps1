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

if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir | Out-Null
}

$config = New-PesterConfiguration
$config.Run.Path = $testPath
$config.Run.Exit = $false # Handle exit manually to allow summary generation
$config.Run.PassThru = $true # Return results object
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $reportDir 'test-results.xml'
$config.TestResult.OutputFormat = 'NUnitXml'

if ($IncludeCoverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $coveragePath
    $config.CodeCoverage.OutputPath = Join-Path $reportDir 'coverage.xml'
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
}

$result = Invoke-Pester -Configuration $config

if ($IncludeCoverage.IsPresent) {
    $coverageReport = $result.CodeCoverage
    if ($null -eq $coverageReport) {
        Write-Warning 'Coverage was requested but no coverage data was returned.'
    } else {
        # Pester 5 still uses these property names for the summary display
        $pct = if ($coverageReport.NumberOfCommandsAnalyzed -gt 0) {
            [math]::Round(($coverageReport.NumberOfCommandsExecuted / $coverageReport.NumberOfCommandsAnalyzed) * 100, 2)
        } else {
            0
        }

        $summary = @(
            "Code coverage: $pct%"
            "Commands covered: $($coverageReport.NumberOfCommandsExecuted) / $($coverageReport.NumberOfCommandsAnalyzed)"
            "File: Utils.ps1"
        ) -join [Environment]::NewLine

        Write-Host $summary
        $summaryPath = Join-Path $reportDir 'summary.txt'
        Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

        $missed = @($coverageReport.MissedCommands)
        if ($missed.Count -gt 0) {
            $missedPath = Join-Path $reportDir 'missed-commands.txt'
            $missed |
                Sort-Object Function, Line |
                Format-Table Function, Line, Command -AutoSize |
                Out-String -Width 200 |
                Set-Content -Path $missedPath -Encoding UTF8
        }
    }
}

if ($result.FailedCount -gt 0) {
    Write-Error "Tests failed: $($result.FailedCount) failed tests."
    exit 1
}
