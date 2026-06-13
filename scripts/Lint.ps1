#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Error', 'Warning', 'Information')]
    [string]$FailOnSeverity = 'Error'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'Installing PSScriptAnalyzer...'
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
}

$paths = @(
    (Join-Path $repoRoot '*.ps1')
    (Join-Path $repoRoot 'tests\*.ps1')
) | ForEach-Object { Resolve-Path -Path $_ } | ForEach-Object { $_.Path }

$settingsPath = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
$issues = foreach ($path in $paths) {
    Invoke-ScriptAnalyzer -Path $path -Settings $settingsPath
}

if ($issues) {
    $issues | Sort-Object ScriptName, Line | Format-Table RuleName, Severity, ScriptName, Line, Message -Wrap -AutoSize
}

$errors = @($issues | Where-Object { $_.Severity -eq 'Error' })
$warnings = @($issues | Where-Object { $_.Severity -eq 'Warning' })
Write-Host "Lint: $($errors.Count) error(s), $($warnings.Count) warning(s)"

$fail = switch ($FailOnSeverity) {
    'Error'       { $errors.Count -gt 0 }
    'Warning'     { ($errors.Count + $warnings.Count) -gt 0 }
    'Information' { $issues.Count -gt 0 }
}

if ($fail) {
    exit 1
}
