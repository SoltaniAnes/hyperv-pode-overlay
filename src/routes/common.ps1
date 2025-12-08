function global:Add-HvoCommonRoutes {
    # @openapi
    # path: /health
    # method: GET
    # summary: Check API server status
    # description: Returns the health status of the server and its configuration
    # tags: [Health]
    # responses:
    #   200:
    #     description: Server operational
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/HealthResponse'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Get -Path '/health' -ScriptBlock {
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
    }
}
