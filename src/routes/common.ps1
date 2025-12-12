function global:Add-HvoCommonRoutes {
    # Define reusable OpenAPI component schemas
    Add-PodeOAComponentSchema -Name 'ErrorSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'error' -Required),
            (New-PodeOAStringProperty -Name 'detail')
        )
    )

    Add-PodeOAComponentSchema -Name 'HealthSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'status' -Required),
            (New-PodeOAObjectProperty -Name 'config' -Required),
            (New-PodeOAStringProperty -Name 'root' -Required),
            (New-PodeOAStringProperty -Name 'time' -Required)
        )
    )

    ###
    ### GET /health
    ###
    $healthRoute = Add-PodeRoute -Method Get -Path '/health' -ScriptBlock {
        try {
            # Ensure config and Get-HvoConfig are available in Pode's runspace
            $configPath = Join-Path $PSScriptRoot '..' 'config.ps1'
            if (Test-Path $configPath) {
                . $configPath
            }

            $cfg = Get-HvoConfig
            Write-PodeJsonResponse -Value @{
                status = "ok"
                config = $cfg
                root   = $PSScriptRoot
                time   = (Get-Date).ToString('o')
            }
        }
        catch {
            # Return structured JSON error similar to other routes
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Health check failed"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $healthRoute | Set-PodeOARouteInfo -Summary 'Health check endpoint' -Description 'Returns the health status of the API along with configuration information' -Tags @('Health')
    $healthRoute | Add-PodeOAResponse -StatusCode 200 -Description 'API is healthy' -ContentSchemas @{
        'application/json' = 'HealthSchema'
    }
    $healthRoute | Add-PodeOAResponse -StatusCode 500 -Description 'Health check failed' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
}
