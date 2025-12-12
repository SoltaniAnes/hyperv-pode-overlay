function global:Add-HvoOpenApiDocumentation {
    # Document OpenAPI routes that are created automatically by Enable-PodeOpenApi
    # We don't create routes here, only add OpenAPI documentation to existing routes

    # Document /openapi route (created by Enable-PodeOpenApi -Path '/openapi')
    $route = Get-PodeRoute -Method Get -Path '/openapi' -ErrorAction SilentlyContinue
    if ($route) {
        $route | Set-PodeOARouteInfo -Summary 'Get OpenAPI specification' -Description 'Returns the OpenAPI 3.0 specification in JSON format' -Tags @('Documentation')
        $route | Add-PodeOAResponse -StatusCode 200 -Description 'OpenAPI specification in JSON format' -ContentSchemas @{
            'application/json' = (New-PodeOAObjectProperty)
        }
        $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to generate OpenAPI specification' -ContentSchemas @{
            'application/json' = 'ErrorSchema'
        }
    }

    # Document /openapi.json route (if it exists)
    $route = Get-PodeRoute -Method Get -Path '/openapi.json' -ErrorAction SilentlyContinue
    if ($route) {
        $route | Set-PodeOARouteInfo -Summary 'Get OpenAPI specification (JSON)' -Description 'Returns the OpenAPI 3.0 specification in JSON format' -Tags @('Documentation')
        $route | Add-PodeOAResponse -StatusCode 200 -Description 'OpenAPI specification in JSON format' -ContentSchemas @{
            'application/json' = (New-PodeOAObjectProperty)
        }
        $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to generate OpenAPI specification' -ContentSchemas @{
            'application/json' = 'ErrorSchema'
        }
    }

    # Document /openapi.yaml route (if it exists)
    $route = Get-PodeRoute -Method Get -Path '/openapi.yaml' -ErrorAction SilentlyContinue
    if ($route) {
        $route | Set-PodeOARouteInfo -Summary 'Get OpenAPI specification (YAML)' -Description 'Returns the OpenAPI 3.0 specification in YAML format' -Tags @('Documentation')
        $route | Add-PodeOAResponse -StatusCode 200 -Description 'OpenAPI specification in YAML format' -ContentSchemas @{
            'application/yaml' = (New-PodeOAStringProperty)
        }
        $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to generate OpenAPI specification' -ContentSchemas @{
            'application/yaml' = 'ErrorSchema'
        }
    }

    # Document /docs/swagger route (created by Enable-PodeOpenApiViewer)
    $route = Get-PodeRoute -Method Get -Path '/docs/swagger' -ErrorAction SilentlyContinue
    if ($route) {
        $route | Set-PodeOARouteInfo -Summary 'Swagger UI documentation viewer' -Description 'Interactive Swagger UI interface for exploring and testing the API' -Tags @('Documentation')
        $route | Add-PodeOAResponse -StatusCode 200 -Description 'Swagger UI HTML page'
        $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to load Swagger UI'
    }

    # Document /docs/redoc route (created by Enable-PodeOpenApiViewer)
    $route = Get-PodeRoute -Method Get -Path '/docs/redoc' -ErrorAction SilentlyContinue
    if ($route) {
        $route | Set-PodeOARouteInfo -Summary 'ReDoc documentation viewer' -Description 'Interactive ReDoc interface for viewing the API documentation' -Tags @('Documentation')
        $route | Add-PodeOAResponse -StatusCode 200 -Description 'ReDoc HTML page'
        $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to load ReDoc'
    }
}
