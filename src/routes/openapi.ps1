function global:Add-HvoOpenApiRoutes {
    # @openapi
    # path: /openapi.json
    # method: GET
    # summary: Returns the OpenAPI specification
    # description: Generates and returns the complete OpenAPI specification of the API from inline comments
    # tags: [Documentation]
    # responses:
    #   200:
    #     description: OpenAPI specification
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Get -Path '/openapi.json' -ScriptBlock {
        try {
            # Load config to get BaseUrl
            $configPath = Join-Path $PSScriptRoot '..' 'config.ps1'
            if (Test-Path $configPath) {
                . $configPath
            }

            $cfg = Get-HvoConfig
            $BaseUrl = "http://$($cfg.ListenAddress):$($cfg.Port)"

            # Determine routes path
            # $PSScriptRoot points to the routes directory, so we use it directly
            $routesPath = $PSScriptRoot

            # Generate OpenAPI specification
            $spec = Get-HvoOpenApiSpec -RoutesPath $routesPath -BaseUrl $BaseUrl -Quiet

            if (-not $spec) {
                Write-PodeJsonResponse -StatusCode 500 -Value @{
                    error  = "Failed to generate OpenAPI specification"
                    detail = "Get-HvoOpenApiSpec returned null"
                }
                return
            }

            # Return JSON response
            # Use Write-PodeJsonResponse which automatically handles JSON conversion
            # with appropriate depth for complex structures
            Write-PodeJsonResponse -Value $spec
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Failed to generate OpenAPI specification"
                detail = $_.Exception.Message
            }
        }
    }
}

