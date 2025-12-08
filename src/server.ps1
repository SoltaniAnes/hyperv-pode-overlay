Import-Module Pode -ErrorAction Stop
Import-Module Hyper-V -ErrorAction Stop

try {
    . "$PSScriptRoot/config.ps1"

    # Load our modules
    Import-Module "$PSScriptRoot/utils.psm1"  -Force
    Import-Module "$PSScriptRoot/modules/HvoVm/HvoVm.psd1" -Force
    Import-Module "$PSScriptRoot/modules/HvoSwitch/HvoSwitch.psd1" -Force
    Import-Module "$PSScriptRoot/modules/HvoOpenApi/HvoOpenApi.psd1" -Force

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

    # Store server root path for use in routes
    $script:ServerRoot = $PSScriptRoot

    # Export modules into runspaces
    Export-PodeModule HvoVm
    Export-PodeModule HvoSwitch
    Export-PodeModule HvoOpenApi

    Add-HvoCommonRoutes
    Add-HvoVmRoutes
    Add-HvoSwitchRoutes
    Add-HvoOpenApiRoutes
}
