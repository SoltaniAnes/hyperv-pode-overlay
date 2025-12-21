# Unit test execution script
# Usage: .\tests\run-tests.ps1 [-Unit] [-Integration] [-Coverage]

param(
    [switch]$Unit,
    [switch]$Integration,
    [switch]$Coverage,
    [switch]$All
)

$ErrorActionPreference = 'Stop'

# Check if Pester is installed
$pesterModule = Get-Module -ListAvailable -Name 'Pester' -ErrorAction SilentlyContinue
if (-not $pesterModule) {
    Write-Host "Pester is not installed. Installing..." -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck -Scope CurrentUser
    Import-Module Pester -Force
} else {
    Write-Host "Pester version $($pesterModule.Version) detected" -ForegroundColor Green
    Import-Module Pester -Force
}

# Determine which tests to run
$runUnit = $Unit -or $All -or (-not $Integration)
$runIntegration = $Integration -or $All

$unitPath = Join-Path $PSScriptRoot "unit"
$integrationPath = Join-Path $PSScriptRoot "integration"

$allPassed = $true

# Run unit tests
if ($runUnit) {
    Write-Host "`n=== Unit Tests ===" -ForegroundColor Cyan
    $unitConfig = New-PesterConfiguration
    $unitConfig.Run.Path = $unitPath
    $unitConfig.Output.Verbosity = 'Detailed'

    if ($Coverage) {
        $unitConfig.CodeCoverage.Enabled = $true
        $unitConfig.CodeCoverage.Path = @(
            "$PSScriptRoot/../src/modules/**/*.psm1",
            "$PSScriptRoot/../src/utils.psm1"
        )
        $unitConfig.CodeCoverage.OutputFormat = 'CoverageGutters'
        $unitConfig.CodeCoverage.OutputPath = "$PSScriptRoot/../coverage.xml"
    }

    $unitResults = Invoke-Pester -Configuration $unitConfig

    if ($unitResults.FailedCount -gt 0) {
        $allPassed = $false
    }
}

# Run integration tests
if ($runIntegration) {
    Write-Host "`n=== Integration Tests ===" -ForegroundColor Cyan
    $integrationConfig = New-PesterConfiguration
    $integrationConfig.Run.Path = $integrationPath
    $integrationConfig.Output.Verbosity = 'Detailed'

    $integrationResults = Invoke-Pester -Configuration $integrationConfig

    if ($integrationResults.FailedCount -gt 0) {
        $allPassed = $false
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed." -ForegroundColor Red
    exit 1
}
