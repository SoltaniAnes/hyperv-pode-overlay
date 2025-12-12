# src/config.ps1

$global:HvoConfig = @{
    ApiName       = 'hyperv-api'
    Port          = 8080
    ListenAddress = '0.0.0.0'
}

function global:Get-HvoConfig {
    return $global:HvoConfig
}
