#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$IncludeCoverage
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testPath = Join-Path $repoRoot 'tests\Utils.Tests.ps1'
$coveragePath = Join-Path $repoRoot 'Utils.ps1'
$reportDir = Join-Path $repoRoot 'coverage'

$pesterParams = @{
    Path       = $testPath
    PassThru   = $true
    EnableExit = $true
}

if ($IncludeCoverage) {
    $pesterParams['CodeCoverage'] = $coveragePath
    if (-not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir | Out-Null
    }
    $pesterParams['OutputFile'] = Join-Path $reportDir 'test-results.xml'
    $pesterParams['OutputFormat'] = 'NUnitXml'
}

$result = Invoke-Pester @pesterParams

Write-Host "Tests: $($result.PassedCount) passed, $($result.FailedCount) failed"

if ($IncludeCoverage.IsPresent) {
    if ($null -eq $result.CodeCoverage) {
        Write-Warning 'Coverage was requested but no coverage data was returned.'
    } else {
        $coverageReport = $result.CodeCoverage
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
    exit 1
}
