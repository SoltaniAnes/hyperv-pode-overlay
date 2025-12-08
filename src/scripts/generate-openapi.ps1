# src/scripts/generate-openapi.ps1
# Script to generate openapi.json file from inline comments

param(
    [string]$OutputPath = "$PSScriptRoot/../../docs/openapi.json",
    [string]$BaseUrl = "http://localhost:8080"
)

$ErrorActionPreference = "Stop"

try {
    # Import OpenAPI module
    # Build path more robustly
    $moduleDir = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'modules') 'HvoOpenApi'
    $modulePath = Join-Path $moduleDir 'HvoOpenApi.psd1'
    
    if (-not (Test-Path $modulePath)) {
        Write-Error "OpenAPI module not found at: $modulePath"
        Write-Error "Expected directory structure: src/modules/HvoOpenApi/HvoOpenApi.psd1"
        exit 1
    }
    
    Write-Host "Importing HvoOpenApi module..." -ForegroundColor Cyan
    Write-Host "  Path: $modulePath" -ForegroundColor Gray
    
    Import-Module $modulePath -Force -ErrorAction Stop
    
    # Verify that the function is available after import
    if (-not (Get-Command Get-HvoOpenApiSpec -ErrorAction SilentlyContinue)) {
        Write-Error "Get-HvoOpenApiSpec function is not available after module import"
        Write-Error "Verify that the module exports its functions correctly"
        exit 1
    }
    
    Write-Host "  Module imported successfully" -ForegroundColor Green
    
    # Load config if available
    $configPath = Join-Path (Join-Path $PSScriptRoot '..') 'config.ps1'
    if (Test-Path $configPath) {
        Write-Host "Loading configuration..." -ForegroundColor Cyan
        . $configPath
        
        if (Get-Command Get-HvoConfig -ErrorAction SilentlyContinue) {
            $cfg = Get-HvoConfig
            if ($cfg -and $cfg.ListenAddress -and $cfg.Port) {
                $BaseUrl = "http://$($cfg.ListenAddress):$($cfg.Port)"
                Write-Host "  Base URL from config: $BaseUrl" -ForegroundColor Gray
            }
        } else {
            Write-Warning "Get-HvoConfig is not available, using default BaseUrl"
        }
    } else {
        Write-Host "No configuration file found, using default values" -ForegroundColor Yellow
    }
    
    # Generate spec
    $routesPath = Join-Path (Join-Path $PSScriptRoot '..') 'routes'
    
    # Verify that the routes directory exists
    if (-not (Test-Path $routesPath)) {
        Write-Error "Routes directory does not exist: $routesPath"
        exit 1
    }
    
    if (-not (Test-Path $routesPath -PathType Container)) {
        Write-Error "The specified path is not a directory: $routesPath"
        exit 1
    }
    
    Write-Host "Generating OpenAPI specification..." -ForegroundColor Cyan
    Write-Host "  Routes: $routesPath" -ForegroundColor Gray
    Write-Host "  Base URL: $BaseUrl" -ForegroundColor Gray
    
    $spec = Get-HvoOpenApiSpec -RoutesPath $routesPath -BaseUrl $BaseUrl
    
    if (-not $spec) {
        Write-Error "OpenAPI specification generation failed (null result)"
        exit 1
    }
    
    # Convert to JSON with sufficient depth
    $json = $spec | ConvertTo-Json -Depth 50 -Compress:$false
    
    if (-not $json) {
        Write-Error "JSON conversion failed"
        exit 1
    }
    
    # Create directory if necessary
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-Host "Directory created: $outputDir" -ForegroundColor Yellow
    }
    
    # Write file
    $json | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "OpenAPI spec generated successfully: $OutputPath" -ForegroundColor Green
    
    # Display some statistics
    if ($spec.paths) {
        $pathCount = ($spec.paths.PSObject.Properties | Measure-Object).Count
        Write-Host "  Documented endpoints: $pathCount" -ForegroundColor Gray
        
        # Display number of schemas
        if ($spec.components -and $spec.components.schemas) {
            $schemaCount = ($spec.components.schemas.PSObject.Properties | Measure-Object).Count
            Write-Host "  Defined schemas: $schemaCount" -ForegroundColor Gray
        }
    } else {
        Write-Warning "No endpoints found in specification"
    }
}
catch {
    Write-Error "Error during generation: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}

