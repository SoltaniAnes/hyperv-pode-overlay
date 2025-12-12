Import-Module Pode -ErrorAction Stop

# Import Hyper-V module conditionally
# This allows the server to start for documentation generation even without Hyper-V
$hyperVModuleAvailable = $false
try {
    $hyperVModule = Get-Module -ListAvailable -Name 'Hyper-V' -ErrorAction SilentlyContinue
    if ($null -ne $hyperVModule) {
        Import-Module Hyper-V -ErrorAction Stop
        $hyperVModuleAvailable = $true
        Write-Host "Hyper-V module loaded successfully" -ForegroundColor Green
    }
    else {
        Write-Host "Warning: Hyper-V module is not available. API endpoints requiring Hyper-V will not function." -ForegroundColor Yellow
        Write-Host "This is acceptable for documentation generation only." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Warning: Failed to load Hyper-V module: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "This is acceptable for documentation generation only." -ForegroundColor Yellow
}

try {
    . "$PSScriptRoot/config.ps1"

    # Load our modules
    Import-Module "$PSScriptRoot/utils.psm1"  -Force
    Import-Module "$PSScriptRoot/modules/HvoVm/HvoVm.psd1" -Force
    Import-Module "$PSScriptRoot/modules/HvoSwitch/HvoSwitch.psd1" -Force

    # Load routes after modules
    . "$PSScriptRoot/routes/common.ps1"
    . "$PSScriptRoot/routes/vms.ps1"
    . "$PSScriptRoot/routes/switches.ps1"
    . "$PSScriptRoot/routes/openapi.ps1"
}
catch {
    Write-Host "Error loading: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

$cfg = Get-HvoConfig
$Port = $cfg.Port
$ListenAddress = $cfg.ListenAddress

Write-Host "Starting Hyper-V API on http://$ListenAddress`:$Port"

Start-PodeServer {
    Add-PodeEndpoint -Address "*" -Port $Port -Protocol Http

    # Enable OpenAPI documentation
    # This creates the /openapi route automatically
    Enable-PodeOpenApi -Path '/openapi' -RouteFilter '/*'
    Add-PodeOAInfo -Title 'Hyper-V API' -Version '1.0.0'

    # Enable Swagger UI viewer
    Enable-PodeOpenApiViewer -Type Swagger -Path '/docs/swagger'

    # Enable ReDoc viewer
    Enable-PodeOpenApiViewer -Type ReDoc -Path '/docs/redoc'

    # Document the automatically created OpenAPI routes
    # We don't create routes here, only add OpenAPI documentation
    Add-HvoOpenApiDocumentation

    # Export modules into runspaces
    Export-PodeModule HvoVm
    Export-PodeModule HvoSwitch

    Add-HvoCommonRoutes
    Add-HvoVmRoutes
    Add-HvoSwitchRoutes
}
