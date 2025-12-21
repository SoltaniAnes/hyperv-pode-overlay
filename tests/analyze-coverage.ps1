# Analyze code coverage from coverage.xml
# Usage: .\tests\analyze-coverage.ps1

param(
    [string]$CoverageFile = "coverage.xml"
)

if (-not (Test-Path $CoverageFile)) {
    Write-Error "Coverage file not found: $CoverageFile"
    exit 1
}

[xml]$coverage = Get-Content $CoverageFile

Write-Host "`n=== Coverage by Module ===" -ForegroundColor Cyan
$packages = $coverage.report.package
foreach ($pkg in $packages) {
    $counter = $pkg.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
    if ($counter) {
        $missed = [int]$counter.missed
        $covered = [int]$counter.covered
        $total = $missed + $covered
        if ($total -gt 0) {
            $pct = [math]::Round(($covered / $total) * 100, 1)
            $pkgName = $pkg.name -replace '.*/([^/]+)$', '$1'
            Write-Host "$pkgName : $pct% ($covered/$total)"
        }
    }
}

Write-Host "`n=== Critical Functions (VM Lifecycle) ===" -ForegroundColor Cyan
$criticalFunctions = @('New-HvoVm', 'Remove-HvoVm', 'Start-HvoVm', 'Stop-HvoVm', 'Restart-HvoVm', 'Suspend-HvoVm', 'Resume-HvoVm')
$methods = $coverage.SelectNodes('//method')
foreach ($method in $methods) {
    $methodName = $method.name
    if ($criticalFunctions -contains $methodName) {
        $counter = $method.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
        if ($counter) {
            $missed = [int]$counter.missed
            $covered = [int]$counter.covered
            $total = $missed + $covered
            if ($total -gt 0) {
                $pct = [math]::Round(($covered / $total) * 100, 1)
                $status = if ($pct -ge 90) { "✓" } else { "✗" }
                Write-Host "  $status $methodName : $pct% ($covered/$total)" -ForegroundColor $(if ($pct -ge 90) { "Green" } else { "Yellow" })
            }
        }
    }
}

Write-Host "`n=== Business Logic Modules ===" -ForegroundColor Cyan
$businessModules = @('HvoVm', 'HvoSwitch')
foreach ($pkg in $packages) {
    $pkgName = $pkg.name -replace '.*/([^/]+)$', '$1'
    if ($businessModules -contains $pkgName) {
        $counter = $pkg.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
        if ($counter) {
            $missed = [int]$counter.missed
            $covered = [int]$counter.covered
            $total = $missed + $covered
            if ($total -gt 0) {
                $pct = [math]::Round(($covered / $total) * 100, 1)
                $status = if ($pct -ge 80) { "✓" } else { "✗" }
                Write-Host "$status $pkgName : $pct% ($covered/$total)" -ForegroundColor $(if ($pct -ge 80) { "Green" } else { "Yellow" })
            }
        }
    }
}

Write-Host "`n=== Utility Code ===" -ForegroundColor Cyan
foreach ($pkg in $packages) {
    $pkgName = $pkg.name -replace '.*/([^/]+)$', '$1'
    if ($pkgName -eq 'src' -or $pkgName -eq 'utils') {
        $counter = $pkg.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
        if ($counter) {
            $missed = [int]$counter.missed
            $covered = [int]$counter.covered
            $total = $missed + $covered
            if ($total -gt 0) {
                $pct = [math]::Round(($covered / $total) * 100, 1)
                $status = if ($pct -ge 60) { "✓" } else { "✗" }
                Write-Host "$status $pkgName : $pct% ($covered/$total)" -ForegroundColor $(if ($pct -ge 60) { "Green" } else { "Yellow" })
            }
        }
    }
}

Write-Host "`n=== Overall Coverage ===" -ForegroundColor Cyan
$overallCounter = $coverage.report.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
if ($overallCounter) {
    $missed = [int]$overallCounter.missed
    $covered = [int]$overallCounter.covered
    $total = $missed + $covered
    if ($total -gt 0) {
        $pct = [math]::Round(($covered / $total) * 100, 1)
        $status = if ($pct -ge 75) { "✓" } else { "✗" }
        Write-Host "$status Overall : $pct% ($covered/$total)" -ForegroundColor $(if ($pct -ge 75) { "Green" } else { "Yellow" })
    }
}

Write-Host "`n=== Coverage Goals Check ===" -ForegroundColor Cyan
Write-Host "Critical code (>90%): " -NoNewline
$criticalCoverage = $coverage.SelectNodes('//method') | Where-Object {
    $criticalFunctions -contains $_.name
} | ForEach-Object {
    $counter = $_.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
    if ($counter) {
        $missed = [int]$counter.missed
        $covered = [int]$counter.covered
        $total = $missed + $covered
        if ($total -gt 0) { ($covered / $total) * 100 } else { 0 }
    }
} | Measure-Object -Average

if ($criticalCoverage.Average -ge 90) {
    Write-Host "✓ PASSED ($([math]::Round($criticalCoverage.Average, 1))%)" -ForegroundColor Green
} else {
    Write-Host "✗ FAILED ($([math]::Round($criticalCoverage.Average, 1))%)" -ForegroundColor Red
}

Write-Host "Business logic (>80%): " -NoNewline
$businessCoverage = $packages | Where-Object {
    $pkgName = $_.name -replace '.*/([^/]+)$', '$1'
    $businessModules -contains $pkgName
} | ForEach-Object {
    $counter = $_.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
    if ($counter) {
        $missed = [int]$counter.missed
        $covered = [int]$counter.covered
        $total = $missed + $covered
        if ($total -gt 0) { ($covered / $total) * 100 } else { 0 }
    }
} | Measure-Object -Average

if ($businessCoverage.Average -ge 80) {
    Write-Host "✓ PASSED ($([math]::Round($businessCoverage.Average, 1))%)" -ForegroundColor Green
} else {
    Write-Host "✗ FAILED ($([math]::Round($businessCoverage.Average, 1))%)" -ForegroundColor Red
}

Write-Host "Utility code (>60%): " -NoNewline
$utilityCoverage = $packages | Where-Object {
    $pkgName = $_.name -replace '.*/([^/]+)$', '$1'
    $pkgName -eq 'src' -or $pkgName -eq 'utils'
} | ForEach-Object {
    $counter = $_.counter | Where-Object { $_.type -eq 'INSTRUCTION' }
    if ($counter) {
        $missed = [int]$counter.missed
        $covered = [int]$counter.covered
        $total = $missed + $covered
        if ($total -gt 0) { ($covered / $total) * 100 } else { 0 }
    }
} | Measure-Object -Average

if ($utilityCoverage.Average -ge 60) {
    Write-Host "✓ PASSED ($([math]::Round($utilityCoverage.Average, 1))%)" -ForegroundColor Green
} else {
    Write-Host "✗ FAILED ($([math]::Round($utilityCoverage.Average, 1))%)" -ForegroundColor Red
}

Write-Host "Overall (>75%): " -NoNewline
if ($overallCounter) {
    $missed = [int]$overallCounter.missed
    $covered = [int]$overallCounter.covered
    $total = $missed + $covered
    if ($total -gt 0) {
        $pct = ($covered / $total) * 100
        if ($pct -ge 75) {
            Write-Host "✓ PASSED ($([math]::Round($pct, 1))%)" -ForegroundColor Green
        } else {
            Write-Host "✗ FAILED ($([math]::Round($pct, 1))%)" -ForegroundColor Red
        }
    }
}
