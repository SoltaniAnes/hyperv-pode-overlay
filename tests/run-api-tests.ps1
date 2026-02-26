# API test script - Full scenario against a running Hyper-V API server
# Usage: .\tests\run-api-tests.ps1 [-BaseUrl <url>] [-VmDiskPath <path>]
# Prerequisite: Start the API server (e.g. .\src\server.ps1) before running.

param(
    [string]$BaseUrl = 'http://localhost:8080',
    [string]$VmDiskPath = 'C:\ProgramData\hvo-api-test'
)

$ErrorActionPreference = 'Stop'

# Naming pattern: hvo-test-{type}-<YYYYMMDDHHmm> (low conflict, clearly test-related)
$runTimestamp = Get-Date -Format 'yyyyMMddHHmm'
$testSwitchName = "hvo-test-switch-$runTimestamp"
$testVmName = "hvo-test-vm-$runTimestamp"

$reportLines = [System.Collections.ArrayList]@()
$failedTests = [System.Collections.ArrayList]@()
$createdResourceNames = [System.Collections.ArrayList]@()
$totalTests = 0
$passedTests = 0
$script:SwitchId = $null
$script:VmId = $null

function Add-Report {
    param([string]$Text, [string]$Indent = '')
    $null = $reportLines.Add("$Indent$Text")
    Write-Host "$Indent$Text"
}

function Invoke-ApiRequest {
    param(
        [string]$Method,
        [string]$Path,
        [int[]]$ExpectedStatus = @(200),
        [hashtable]$Body = $null,
        [string]$TestName = "$Method $Path"
    )
    $url = "$BaseUrl$Path"
    $headers = @{ 'Accept' = 'application/json'; 'Content-Type' = 'application/json' }
    $params = @{
        Uri             = $url
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
        TimeoutSec      = 30
    }
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Compress -Depth 10)
    }
    try {
        $response = Invoke-WebRequest @params -SkipHttpErrorCheck
        $content = $response.Content
        try {
            $json = $response.Content | ConvertFrom-Json
        } catch {
            $json = $null
        }
        $ok = $response.StatusCode -in $ExpectedStatus
        $script:totalTests++
        if ($ok) { $script:passedTests++ }
        return @{
            Success = $ok
            StatusCode = $response.StatusCode
            Content = $content
            Json = $json
            TestName = $TestName
        }
    } catch {
        $script:totalTests++
        return @{
            Success = $false
            StatusCode = $null
            Content = $_.Exception.Message
            Json = $null
            TestName = $TestName
        }
    }
}

function Add-TestResult {
    param(
        [hashtable]$Result,
        [string]$Phase
    )
    $status = if ($Result.Success) { 'OK' } else { 'FAIL' }
    Add-Report "  [$status] $($Result.TestName) -> $($Result.StatusCode)" "  "
    if (-not $Result.Success) {
        $null = $failedTests.Add(@{ Phase = $Phase; Result = $Result })
        $preview = if ($Result.Content.Length -gt 200) { $Result.Content.Substring(0, 200) + '...' } else { $Result.Content }
        Add-Report "      Response: $preview" "  "
    }
    return $Result
}

# ----- Confirmation and health check -----
Add-Report "=== Hyper-V API - Tests de scenario complet ===" ""
Add-Report "Base URL: $BaseUrl" ""
Add-Report "Ressources de test: $testSwitchName, $testVmName" ""
Add-Report ""

Write-Host "Le serveur API doit etre demarre (ex: .\src\server.ps1)." -ForegroundColor Yellow
$confirm = Read-Host "Le serveur API est-il demarre sur $BaseUrl ? (O/N)"
if ($confirm -notmatch '^[oOyY]') {
    Add-Report "Annule par l'utilisateur." ""
    exit 0
}

$healthResult = Invoke-ApiRequest -Method Get -Path '/health' -ExpectedStatus 200 -TestName 'GET /health'
if (-not $healthResult.Success) {
    Add-Report "ERREUR: Le serveur ne repond pas sur $BaseUrl (GET /health a echoue)." ""
    Add-Report "Demarrez le serveur avec: .\src\server.ps1" ""
    exit 1
}
Add-Report "[OK] Serveur accessible (GET /health -> $($healthResult.StatusCode))" ""
Add-Report ""

$startTime = Get-Date

# ========== Phase 1: Basic ==========
Add-Report "--- Phase 1: Health et documentation ---" ""

$r = Invoke-ApiRequest -Method Get -Path '/openapi.json' -ExpectedStatus 200 -TestName 'GET /openapi.json'
Add-TestResult -Result $r -Phase 'Phase1' | Out-Null
if ($r.Success -and $r.Json) {
    $hasOpenApi = $null -ne ($r.Json.psobject.Properties | Where-Object { $_.Name -eq 'openapi' -or $_.Name -eq 'swagger' })
    if (-not $hasOpenApi) {
        $r.Success = $false
        $r.Content = 'Response is not a valid OpenAPI document (missing openapi/swagger field)'
        $script:passedTests--
        $null = $failedTests.Add(@{ Phase = 'Phase1'; Result = $r })
    }
}

# ========== Phase 2: Switches ==========
Add-Report "" ""
Add-Report "--- Phase 2: Switches ---" ""

$r = Invoke-ApiRequest -Method Get -Path '/switches' -ExpectedStatus 200 -TestName 'GET /switches'
Add-TestResult -Result $r -Phase 'Phase2' | Out-Null

$bodySwitch = @{
    name = $testSwitchName
    type = 'Internal'
    notes = 'hvo-api-test'
}
$r = Invoke-ApiRequest -Method Post -Path '/switches' -Body $bodySwitch -ExpectedStatus 201 -TestName 'POST /switches (create)'
Add-TestResult -Result $r -Phase 'Phase2' | Out-Null
if ($r.Success -and $r.Json.id) {
    $script:SwitchId = $r.Json.id
    $null = $createdResourceNames.Add("Switch: $testSwitchName (Id: $($script:SwitchId))")
}

if ($script:SwitchId) {
    $r = Invoke-ApiRequest -Method Get -Path "/switches/$($script:SwitchId)" -ExpectedStatus 200 -TestName 'GET /switches/:id'
    Add-TestResult -Result $r -Phase 'Phase2' | Out-Null

        $encodedName = [uri]::EscapeDataString($testSwitchName)
    $r = Invoke-ApiRequest -Method Get -Path "/switches/by-name/$encodedName" -ExpectedStatus 200 -TestName 'GET /switches/by-name/:name'
    Add-TestResult -Result $r -Phase 'Phase2' | Out-Null

    $r = Invoke-ApiRequest -Method Put -Path "/switches/$($script:SwitchId)" -Body @{ notes = 'hvo-api-test-updated' } -ExpectedStatus 200 -TestName 'PUT /switches/:id'
    Add-TestResult -Result $r -Phase 'Phase2' | Out-Null
}

# ========== Phase 3: VMs (full scenario) ==========
Add-Report "" ""
Add-Report "--- Phase 3: VMs ---" ""

$r = Invoke-ApiRequest -Method Get -Path '/vms' -ExpectedStatus 200 -TestName 'GET /vms'
Add-TestResult -Result $r -Phase 'Phase3' | Out-Null

if (-not $script:SwitchId) {
    Add-Report "  [SKIP] Creation VM ignoree (switch non cree)." "  "
} else {
    $bodyVm = @{
        name       = $testVmName
        memoryMB   = 512
        vcpu       = 1
        diskPath   = $VmDiskPath
        diskGB     = 2
        switchName = $testSwitchName
    }
    $r = Invoke-ApiRequest -Method Post -Path '/vms' -Body $bodyVm -ExpectedStatus 201 -TestName 'POST /vms (create)'
    Add-TestResult -Result $r -Phase 'Phase3' | Out-Null
    if ($r.Success -and $r.Json.id) {
        $script:VmId = $r.Json.id
        $null = $createdResourceNames.Add("VM: $testVmName (Id: $($script:VmId))")
    }

    if ($script:VmId) {
        $r = Invoke-ApiRequest -Method Get -Path "/vms/$($script:VmId)" -ExpectedStatus 200 -TestName 'GET /vms/:id'
        Add-TestResult -Result $r -Phase 'Phase3' | Out-Null

        $encodedVmName = [uri]::EscapeDataString($testVmName)
        $r = Invoke-ApiRequest -Method Get -Path "/vms/by-name/$encodedVmName" -ExpectedStatus 200 -TestName 'GET /vms/by-name/:name'
        Add-TestResult -Result $r -Phase 'Phase3' | Out-Null

        $r = Invoke-ApiRequest -Method Post -Path "/vms/$($script:VmId)/start" -ExpectedStatus 200 -TestName 'POST /vms/:id/start'
        Add-TestResult -Result $r -Phase 'Phase3' | Out-Null

        Start-Sleep -Seconds 3
        $r = Invoke-ApiRequest -Method Get -Path "/vms/$($script:VmId)" -ExpectedStatus 200 -TestName 'GET /vms/:id (state Running)'
        if ($r.Success -and $r.Json.State -ne 'Running') {
            $r.Success = $false
            $r.Content = "Expected State=Running, got $($r.Json.State)"
            $null = $failedTests.Add(@{ Phase = 'Phase3'; Result = $r })
        }
        $script:totalTests++
        if ($r.Success) { $script:passedTests++ }
        Add-Report "  [$(if ($r.Success) { 'OK' } else { 'FAIL' })] $($r.TestName) -> $($r.StatusCode)" "  "
        if (-not $r.Success) { Add-Report "      Response: $($r.Content)" "  " }

        $r = Invoke-ApiRequest -Method Post -Path "/vms/$($script:VmId)/stop" -Body @{ force = $true } -ExpectedStatus 200 -TestName 'POST /vms/:id/stop'
        Add-TestResult -Result $r -Phase 'Phase3' | Out-Null

        Start-Sleep -Seconds 2
        $r = Invoke-ApiRequest -Method Get -Path "/vms/$($script:VmId)" -ExpectedStatus 200 -TestName 'GET /vms/:id (state Off)'
        if ($r.Success -and $r.Json.State -ne 'Off') {
            $r.Success = $false
            $r.Content = "Expected State=Off, got $($r.Json.State)"
            $null = $failedTests.Add(@{ Phase = 'Phase3'; Result = $r })
        }
        $script:totalTests++
        if ($r.Success) { $script:passedTests++ }
        Add-Report "  [$(if ($r.Success) { 'OK' } else { 'FAIL' })] $($r.TestName) -> $($r.StatusCode)" "  "
        if (-not $r.Success) { Add-Report "      Response: $($r.Content)" "  " }

        $r = Invoke-ApiRequest -Method Get -Path "/vms/$($script:VmId)/network-adapters" -ExpectedStatus 200 -TestName 'GET /vms/:id/network-adapters'
        Add-TestResult -Result $r -Phase 'Phase3' | Out-Null

        $r = Invoke-ApiRequest -Method Put -Path "/vms/$($script:VmId)" -Body @{ memoryMB = 512; vcpu = 1 } -ExpectedStatus 200 -TestName 'PUT /vms/:id'
        Add-TestResult -Result $r -Phase 'Phase3' | Out-Null

        $r = Invoke-ApiRequest -Method Delete -Path "/vms/$($script:VmId)" -ExpectedStatus 200 -TestName 'DELETE /vms/:id'
        Add-TestResult -Result $r -Phase 'Phase3' | Out-Null
    }

    # Delete test switch (after VM so VM is gone first)
    if ($script:SwitchId) {
        $r = Invoke-ApiRequest -Method Delete -Path "/switches/$($script:SwitchId)" -ExpectedStatus 200 -TestName 'DELETE /switches/:id'
        Add-TestResult -Result $r -Phase 'Phase2' | Out-Null
    }
}

# ----- Report -----
$endTime = Get-Date
$duration = $endTime - $startTime
Add-Report "" ""
Add-Report "=== Rapport ===" ""
Add-Report "Date/heure: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" ""
Add-Report "Duree: $($duration.TotalSeconds.ToString('F1')) s" ""
Add-Report "Resultat: $passedTests / $totalTests tests reussis" ""
if ($failedTests.Count -gt 0) {
    Add-Report "" ""
    Add-Report "--- Echecs ---" ""
    foreach ($f in $failedTests) {
        Add-Report "  - $($f.Result.TestName)" ""
        Add-Report "    HTTP $($f.Result.StatusCode) | $($f.Result.Content)" ""
    }
    Add-Report "" ""
    Add-Report "--- Remise en condition initiale Hyper-V ---" ""
    Add-Report "Si des ressources de test sont restees, supprimez-les avec PowerShell (en administrateur):" ""
    Add-Report "" ""
    Add-Report "  # Supprimer les VMs de test (nom commencant par hvo-test-vm-)" ""
    Add-Report "  Get-VM | Where-Object { `$_.Name -like 'hvo-test-vm-*' } | Stop-VM -Force -ErrorAction SilentlyContinue; Get-VM | Where-Object { `$_.Name -like 'hvo-test-vm-*' } | Remove-VM -Force" ""
    Add-Report "" ""
    Add-Report "  # Supprimer les switches de test (nom commencant par hvo-test-switch-)" ""
    Add-Report "  Get-VMSwitch | Where-Object { `$_.Name -like 'hvo-test-switch-*' } | Remove-VMSwitch -Force" ""
    Add-Report "" ""
    Add-Report "  # Lister les ressources restantes (optionnel)" ""
    Add-Report "  Get-VM | Where-Object { `$_.Name -like 'hvo-test-*' }; Get-VMSwitch | Where-Object { `$_.Name -like 'hvo-test-*' }" ""
    Add-Report "" ""
    if ($createdResourceNames.Count -gt 0) {
        Add-Report "Ressources creees pendant ce run (a nettoyer si besoin):" ""
        foreach ($name in $createdResourceNames) {
            Add-Report "  - $name" ""
        }
    }
}

$reportDir = Join-Path $PSScriptRoot 'reports'
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}
$reportFile = Join-Path $reportDir "api-test-report-$runTimestamp.txt"
$reportLines -join "`n" | Set-Content -Path $reportFile -Encoding UTF8
Add-Report "" ""
Add-Report "Rapport enregistre: $reportFile" ""

if ($failedTests.Count -gt 0) {
    exit 1
}
exit 0
