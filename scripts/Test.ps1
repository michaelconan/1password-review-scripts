#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$IncludeCoverage,
    [double]$CoverageTarget = 80
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
$config.TestResult.Enabled = $false

if ($IncludeCoverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $coveragePath
    $config.CodeCoverage.CoveragePercentTarget = $CoverageTarget
    $config.CodeCoverage.OutputPath = Join-Path $reportDir 'coverage.xml'
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
}

$result = Invoke-Pester -Configuration $config

$testResultPath = Join-Path $reportDir 'test-results.xml'
$xml = New-Object System.Xml.XmlDocument
$suite = $xml.CreateElement('testsuite')
$suite.SetAttribute('name', 'Pester')
$suite.SetAttribute('tests', [string]$result.TotalCount)
$suite.SetAttribute('failures', [string]$result.FailedCount)
$suite.SetAttribute('skipped', [string]$result.SkippedCount)
$suite.SetAttribute('time', [string][math]::Round($result.Duration.TotalSeconds, 3))
[void]$xml.AppendChild($suite)

foreach ($test in @($result.Tests)) {
    $case = $xml.CreateElement('testcase')
    $case.SetAttribute('name', $test.ExpandedName)
    $case.SetAttribute('classname', ($test.Block -join '.'))
    $case.SetAttribute('time', [string][math]::Round($test.Duration.TotalSeconds, 3))

    if ($test.Result -eq 'Failed') {
        $failure = $xml.CreateElement('failure')
        $failure.SetAttribute('message', $test.ErrorRecord.Exception.Message)
        $failure.InnerText = $test.ErrorRecord.ScriptStackTrace
        [void]$case.AppendChild($failure)
    } elseif ($test.Result -eq 'Skipped') {
        [void]$case.AppendChild($xml.CreateElement('skipped'))
    }

    [void]$suite.AppendChild($case)
}

$xml.Save($testResultPath)

if ($IncludeCoverage.IsPresent) {
    $coverageReport = $result.CodeCoverage
    if ($null -eq $coverageReport) {
        Write-Warning 'Coverage was requested but no coverage data was returned.'
    } else {
        $analyzedCount = if ($null -ne $coverageReport.CommandsAnalyzedCount) {
            $coverageReport.CommandsAnalyzedCount
        } else {
            $coverageReport.NumberOfCommandsAnalyzed
        }
        $executedCount = if ($null -ne $coverageReport.CommandsExecutedCount) {
            $coverageReport.CommandsExecutedCount
        } else {
            $coverageReport.NumberOfCommandsExecuted
        }
        $pct = if ($null -ne $coverageReport.CoveragePercent) {
            [math]::Round($coverageReport.CoveragePercent, 2)
        } elseif ($analyzedCount -gt 0) {
            [math]::Round(($coverageReport.NumberOfCommandsExecuted / $coverageReport.NumberOfCommandsAnalyzed) * 100, 2)
        } else {
            0
        }

        $summary = @(
            "Code coverage: $pct%"
            "Commands covered: $executedCount / $analyzedCount"
            "Coverage target: $CoverageTarget%"
            "File: Utils.ps1"
        ) -join [Environment]::NewLine

        Write-Host $summary
        $summaryPath = Join-Path $reportDir 'summary.txt'
        Set-Content -Path $summaryPath -Value $summary -Encoding UTF8

        $missed = if ($null -ne $coverageReport.CommandsMissed) {
            @($coverageReport.CommandsMissed)
        } else {
            @($coverageReport.MissedCommands)
        }
        if ($missed.Count -gt 0) {
            $missedPath = Join-Path $reportDir 'missed-commands.txt'
            $missed |
                Sort-Object Function, Line |
                Format-Table Function, Line, Command -AutoSize |
                Out-String -Width 200 |
                Set-Content -Path $missedPath -Encoding UTF8
        }

        if ($pct -lt $CoverageTarget) {
            Write-Error "Code coverage $pct% is below the required $CoverageTarget% target."
            exit 1
        }
    }
}

if ($result.FailedCount -gt 0) {
    Write-Error "Tests failed: $($result.FailedCount) failed tests."
    exit 1
}
