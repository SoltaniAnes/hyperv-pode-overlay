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

    # Charger les modules AVANT la découverte des tests par Pester
    # InModuleScope nécessite que les modules soient déjà chargés
    $srcRoot = Resolve-Path "$PSScriptRoot/../src" | Select-Object -ExpandProperty Path

    Write-Host "Chargement des modules..." -ForegroundColor Gray
    $hvoVmModulePath = Join-Path $srcRoot "modules/HvoVm/HvoVm.psd1"
    $hvoSwitchModulePath = Join-Path $srcRoot "modules/HvoSwitch/HvoSwitch.psd1"
    $utilsModulePath = Join-Path $srcRoot "utils.psm1"

    if (Test-Path $hvoVmModulePath) {
        Import-Module $hvoVmModulePath -Force -ErrorAction Stop
        Write-Host "  ✓ Module HvoVm chargé" -ForegroundColor Gray
    }
    if (Test-Path $hvoSwitchModulePath) {
        Import-Module $hvoSwitchModulePath -Force -ErrorAction Stop
        Write-Host "  ✓ Module HvoSwitch chargé" -ForegroundColor Gray
    }
    if (Test-Path $utilsModulePath) {
        Import-Module $utilsModulePath -Force -ErrorAction Stop
        Write-Host "  ✓ Module utils chargé" -ForegroundColor Gray
    }

    $unitConfig = New-PesterConfiguration
    $unitConfig.Run.Path = $unitPath
    $unitConfig.Output.Verbosity = 'Detailed'

    if ($Coverage) {
        $unitConfig.CodeCoverage.Enabled = $true

        # Construire la liste des fichiers à couvrir avec des chemins absolus
        $coveragePaths = @()

        # Fichiers de modules
        $hvoVmPath = Join-Path $srcRoot "modules/HvoVm/HvoVm.psm1"
        $hvoSwitchPath = Join-Path $srcRoot "modules/HvoSwitch/HvoSwitch.psm1"
        $utilsPath = Join-Path $srcRoot "utils.psm1"

        if (Test-Path $hvoVmPath) {
            $coveragePaths += (Resolve-Path $hvoVmPath).Path
        }
        if (Test-Path $hvoSwitchPath) {
            $coveragePaths += (Resolve-Path $hvoSwitchPath).Path
        }
        if (Test-Path $utilsPath) {
            $coveragePaths += (Resolve-Path $utilsPath).Path
        }

        if ($coveragePaths.Count -eq 0) {
            Write-Warning "Aucun fichier source trouvé pour la couverture de code"
        } else {
            Write-Host "Fichiers à couvrir:" -ForegroundColor Gray
            foreach ($path in $coveragePaths) {
                Write-Host "  - $path" -ForegroundColor Gray
            }
        }

        $unitConfig.CodeCoverage.Path = $coveragePaths
        $unitConfig.CodeCoverage.OutputFormat = 'JaCoCo'

        $coverageOutputPath = Join-Path (Resolve-Path "$PSScriptRoot/..").Path "coverage.xml"
        $unitConfig.CodeCoverage.OutputPath = $coverageOutputPath

        Write-Host "Fichier de couverture: $coverageOutputPath" -ForegroundColor Gray
    }

    $unitResults = Invoke-Pester -Configuration $unitConfig

    if ($unitResults.FailedCount -gt 0) {
        $allPassed = $false
    }

    if ($Coverage -and $unitResults.CodeCoverage) {
        $coverage = $unitResults.CodeCoverage
        $percentage = [math]::Round($coverage.CoveragePercent, 2)
        Write-Host "`nCouverture de code: $percentage%" -ForegroundColor $(if ($percentage -ge 75) { "Green" } else { "Yellow" })
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
