# OpenAPI Implementation and Usage Guide

This document provides comprehensive information about the OpenAPI implementation in the Hyper-V API project, including how to use it, how it's implemented, and how to extend it.

---

## Table of Contents

- [Overview](#overview)
- [Accessing the Documentation](#accessing-the-documentation)
- [Implementation Details](#implementation-details)
- [Generating Static OpenAPI Files](#generating-static-openapi-files)
- [Documenting New Routes](#documenting-new-routes)
- [OpenAPI Components and Schemas](#openapi-components-and-schemas)
- [Best Practices](#best-practices)

---

## Overview

The Hyper-V API uses [Pode](https://badgerati.github.io/Pode/) framework's built-in OpenAPI support to automatically generate and serve OpenAPI 3.0 specifications. This provides:

- **Automatic API documentation** from route definitions
- **Interactive documentation viewers** (Swagger UI and ReDoc)
- **Type-safe schema definitions** for request/response validation
- **Static file generation** for CI/CD and external tooling

The OpenAPI specification is generated dynamically from the route definitions, ensuring it stays synchronized with the actual API implementation.

---

## Accessing the Documentation

### Interactive Viewers

When the server is running, you can access interactive documentation at:

#### Swagger UI
```
http://<host>:8080/docs/swagger
```

Swagger UI provides:
- Interactive API exploration
- Try-it-out functionality to test endpoints
- Request/response examples
- Schema validation

#### ReDoc
```
http://<host>:8080/docs/redoc
```

ReDoc provides:
- Clean, responsive documentation layout
- Three-panel view with navigation
- Search functionality
- Better readability for complex APIs

### OpenAPI Specification Endpoints

The OpenAPI specification can be retrieved in different formats:

#### JSON Format
```bash
curl http://<host>:8080/openapi.json
```

#### YAML Format
```bash
curl http://<host>:8080/openapi.yaml
```

These endpoints return the complete OpenAPI 3.0 specification that can be used with:
- API client generators (OpenAPI Generator, Swagger Codegen)
- API testing tools (Postman, Insomnia)
- API gateway configurations
- CI/CD validation pipelines

---

## Implementation Details

### Server Configuration

OpenAPI is enabled in `src/server.ps1`:

```powershell
Start-PodeServer {
    Add-PodeEndpoint -Address "*" -Port $Port -Protocol Http

    # Enable OpenAPI documentation
    Enable-PodeOpenApi -Path '/openapi' -RouteFilter '/*'
    Add-PodeOAInfo -Title 'Hyper-V API' -Version '1.0.0'

    # Enable Swagger UI viewer
    Enable-PodeOpenApiViewer -Type Swagger -Path '/docs/swagger'

    # Enable ReDoc viewer
    Enable-PodeOpenApiViewer -Type ReDoc -Path '/docs/redoc'

    # Document the automatically created OpenAPI routes
    Add-HvoOpenApiDocumentation

    # ... rest of the server configuration
}
```

### Key Components

1. **`Enable-PodeOpenApi`**: Enables OpenAPI generation for all routes matching the filter
2. **`Add-PodeOAInfo`**: Sets the API title and version in the OpenAPI spec
3. **`Enable-PodeOpenApiViewer`**: Adds interactive documentation viewers
4. **`Add-HvoOpenApiDocumentation`**: Documents the OpenAPI endpoints themselves

### Route Documentation

Routes are documented using Pode's OpenAPI cmdlets. Each route file (e.g., `src/routes/vms.ps1`, `src/routes/switches.ps1`) follows this pattern:

1. **Define component schemas** for reusable request/response types
2. **Create the route** with `Add-PodeRoute`
3. **Document the route** with `Set-PodeOARouteInfo`
4. **Add response schemas** with `Add-PodeOAResponse`

Example from `src/routes/vms.ps1`:

```powershell
# Define reusable schema
Add-PodeOAComponentSchema -Name 'VmCreateSchema' -Schema (
    New-PodeOAObjectProperty -Properties @(
        (New-PodeOAStringProperty -Name 'name' -Required),
        (New-PodeOAIntProperty -Name 'memoryMB' -Required),
        (New-PodeOAIntProperty -Name 'vcpu' -Required),
        # ... more properties
    )
)

# Create and document route
$route = Add-PodeRoute -Method Post -Path '/vms' -ScriptBlock {
    # Route implementation
} -PassThru

$route | Set-PodeOARouteInfo -Summary 'Create a virtual machine' `
    -Description 'Creates a new VM with the specified configuration' `
    -Tags @('VMs')

$route | Add-PodeOARequest -RequestBody -ContentSchemas @{
    'application/json' = 'VmCreateSchema'
}

$route | Add-PodeOAResponse -StatusCode 200 -Description 'VM created successfully' `
    -ContentSchemas @{
        'application/json' = 'VmResponseSchema'
    }
```

---

## Generating Static OpenAPI Files

Static OpenAPI specification files are stored in the `docs/` directory and can be generated using the provided script.

### Using the Generation Script

The script `src/scripts/generate-openapi.ps1` automatically:

1. Checks if the server is running
2. Starts a temporary server if needed
3. Retrieves the OpenAPI specification from the running server
4. Saves both JSON and YAML formats to `docs/`

#### Basic Usage

```powershell
cd src/scripts
.\generate-openapi.ps1
```

#### Script Parameters

- **`-Port`**: Server port (default: 8080)
- **`-ListenAddress`**: Server listen address (default: localhost)
- **`-TimeoutSeconds`**: Maximum wait time for server startup (default: 30)
- **`-ForceRestart`**: Force restart of an existing server

#### Examples

Generate with custom port:
```powershell
.\generate-openapi.ps1 -Port 9090
```

Generate with custom timeout:
```powershell
.\generate-openapi.ps1 -TimeoutSeconds 60
```

### When to Generate Static Files

Generate static OpenAPI files when:

- **Before committing changes** - Ensure documentation is up to date
- **For CI/CD pipelines** - Validate API contracts
- **For external tooling** - Import into API gateways, client generators
- **For version control** - Track API changes over time

### Integration with CI/CD

The generation script can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Generate OpenAPI documentation
  run: |
    cd src/scripts
    pwsh -File generate-openapi.ps1
  shell: pwsh

- name: Validate OpenAPI spec
  run: |
    npm install -g @apidevtools/swagger-cli
    swagger-cli validate docs/openapi.yaml
```

---

## Documenting New Routes

When adding new routes to the API, follow these steps to ensure proper OpenAPI documentation:

### Step 1: Define Component Schemas

Define reusable schemas at the top of your route file:

```powershell
function global:Add-HvoNewResourceRoutes {
    # Define request schema
    Add-PodeOAComponentSchema -Name 'NewResourceCreateSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'name' -Required),
            (New-PodeOAStringProperty -Name 'description'),
            (New-PodeOAIntProperty -Name 'value' -Required)
        )
    )

    # Define response schema
    Add-PodeOAComponentSchema -Name 'NewResourceSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'id' -Required),
            (New-PodeOAStringProperty -Name 'name' -Required),
            (New-PodeOAStringProperty -Name 'status' -Required)
        )
    )
```

### Step 2: Create the Route

Create the route with `-PassThru` to get the route object:

```powershell
    $route = Add-PodeRoute -Method Post -Path '/new-resources' -ScriptBlock {
        # Route implementation
        param($e)
        # ... handle request
    } -PassThru
```

### Step 3: Document the Route

Add OpenAPI metadata to the route:

```powershell
    $route | Set-PodeOARouteInfo `
        -Summary 'Create a new resource' `
        -Description 'Creates a new resource with the specified configuration. The operation is idempotent.' `
        -Tags @('NewResources')
```

### Step 4: Document Request Body

For POST/PUT/PATCH routes, document the request body:

```powershell
    $route | Add-PodeOARequest `
        -RequestBody `
        -ContentSchemas @{
            'application/json' = 'NewResourceCreateSchema'
        }
```

### Step 5: Document Responses

Document all possible response codes:

```powershell
    # Success response
    $route | Add-PodeOAResponse -StatusCode 200 `
        -Description 'Resource created successfully' `
        -ContentSchemas @{
            'application/json' = 'NewResourceSchema'
        }

    # Error response
    $route | Add-PodeOAResponse -StatusCode 400 `
        -Description 'Invalid request parameters' `
        -ContentSchemas @{
            'application/json' = 'ErrorSchema'
        }

    $route | Add-PodeOAResponse -StatusCode 500 `
        -Description 'Internal server error' `
        -ContentSchemas @{
            'application/json' = 'ErrorSchema'
        }
```

### Step 6: Document Query Parameters

For GET routes with query parameters:

```powershell
    $route | Add-PodeOARequest `
        -Parameters @(
            (New-PodeOAStringProperty -Name 'filter' -In Query),
            (New-PodeOAIntProperty -Name 'limit' -In Query -Default 10)
        )
```

### Step 7: Document Path Parameters

For routes with path parameters:

```powershell
    $route = Add-PodeRoute -Method Get -Path '/new-resources/:id' -ScriptBlock {
        # Route implementation
    } -PassThru

    $route | Add-PodeOARequest `
        -Parameters @(
            (New-PodeOAStringProperty -Name 'id' -In Path -Required)
        )
```

### Complete Example

Here's a complete example of a documented route:

```powershell
function global:Add-HvoExampleRoutes {
    # Define schemas
    Add-PodeOAComponentSchema -Name 'ExampleCreateSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'name' -Required),
            (New-PodeOAStringProperty -Name 'description')
        )
    )

    Add-PodeOAComponentSchema -Name 'ExampleSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'id' -Required),
            (New-PodeOAStringProperty -Name 'name' -Required),
            (New-PodeOAStringProperty -Name 'description'),
            (New-PodeOAStringProperty -Name 'created' -Required)
        )
    )

    # Create route
    $route = Add-PodeRoute -Method Post -Path '/examples' -ScriptBlock {
        param($e)
        try {
            $body = Get-HvoJsonBody
            # Process request...
            Write-PodeJsonResponse -Value @{
                id = "example-123"
                name = $body.name
                description = $body.description
                created = (Get-Date).ToString('o')
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to create example"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    # Document route
    $route | Set-PodeOARouteInfo `
        -Summary 'Create an example resource' `
        -Description 'Creates a new example resource with the specified name and optional description' `
        -Tags @('Examples')

    # Document request
    $route | Add-PodeOARequest `
        -RequestBody `
        -ContentSchemas @{
            'application/json' = 'ExampleCreateSchema'
        }

    # Document responses
    $route | Add-PodeOAResponse -StatusCode 200 `
        -Description 'Example created successfully' `
        -ContentSchemas @{
            'application/json' = 'ExampleSchema'
        }

    $route | Add-PodeOAResponse -StatusCode 400 `
        -Description 'Invalid request' `
        -ContentSchemas @{
            'application/json' = 'ErrorSchema'
        }

    $route | Add-PodeOAResponse -StatusCode 500 `
        -Description 'Internal server error' `
        -ContentSchemas @{
            'application/json' = 'ErrorSchema'
        }
}
```

---

## OpenAPI Components and Schemas

### Common Schemas

The project defines common reusable schemas in `src/routes/common.ps1`:

#### ErrorSchema

Used for all error responses:

```powershell
Add-PodeOAComponentSchema -Name 'ErrorSchema' -Schema (
    New-PodeOAObjectProperty -Properties @(
        (New-PodeOAStringProperty -Name 'error' -Required),
        (New-PodeOAStringProperty -Name 'detail')
    )
)
```

#### HealthSchema

Used for health check responses:

```powershell
Add-PodeOAComponentSchema -Name 'HealthSchema' -Schema (
    New-PodeOAObjectProperty -Properties @(
        (New-PodeOAStringProperty -Name 'status' -Required),
        (New-PodeOAObjectProperty -Name 'config' -Required),
        (New-PodeOAStringProperty -Name 'root' -Required),
        (New-PodeOAStringProperty -Name 'time' -Required)
    )
)
```

### Schema Property Types

Pode provides several property types for building schemas:

- **`New-PodeOAStringProperty`**: String values
- **`New-PodeOAIntProperty`**: Integer values
- **`New-PodeOABoolProperty`**: Boolean values
- **`New-PodeOAObjectProperty`**: Nested objects
- **`New-PodeOAArrayProperty`**: Arrays

### Property Options

Common options for properties:

- **`-Required`**: Marks the property as required
- **`-Enum`**: Restricts values to a specific set
- **`-Default`**: Sets a default value
- **`-Description`**: Adds a description to the property
- **`-Array`**: Creates an array of the property type

Example with all options:

```powershell
New-PodeOAStringProperty `
    -Name 'switchType' `
    -Required `
    -Enum @('Internal', 'External', 'Private') `
    -Description 'Type of virtual switch to create'
```

---

## Best Practices

### 1. Use Component Schemas

Always define reusable schemas using `Add-PodeOAComponentSchema` rather than inline schemas. This:
- Reduces duplication
- Makes maintenance easier
- Improves consistency

### 2. Document All Responses

Document all possible HTTP status codes, including:
- Success responses (200, 201, etc.)
- Client errors (400, 404, etc.)
- Server errors (500, 503, etc.)

### 3. Provide Clear Descriptions

Use descriptive summaries and descriptions:
- **Summary**: Short, one-line description
- **Description**: Detailed explanation including behavior, idempotency, side effects

### 4. Use Tags for Organization

Group related routes with tags:
```powershell
-Tags @('VMs', 'Lifecycle')
```

### 5. Keep Schemas Synchronized

Ensure OpenAPI schemas match actual request/response structures. Test with Swagger UI to verify.

### 6. Generate Static Files Regularly

Generate static OpenAPI files:
- Before committing route changes
- In CI/CD pipelines
- When releasing new API versions

### 7. Validate Generated Specs

Use OpenAPI validation tools to ensure generated specifications are valid:

```bash
# Using swagger-cli
swagger-cli validate docs/openapi.yaml

# Using openapi-validator
npx @apidevtools/swagger-cli validate docs/openapi.yaml
```

### 8. Version Your API

Update the API version in `src/server.ps1` when making breaking changes:

```powershell
Add-PodeOAInfo -Title 'Hyper-V API' -Version '1.1.0'
```

---

## Troubleshooting

### OpenAPI Endpoints Return 404

- Ensure `Enable-PodeOpenApi` is called in `Start-PodeServer` block
- Check that the route filter matches your routes
- Verify the server is running

### Documentation Viewers Don't Load

- Check browser console for errors
- Verify Pode version supports OpenAPI viewers
- Ensure routes are properly documented

### Generated Files Are Empty or Invalid

- Check server logs for errors
- Verify all routes are properly documented
- Ensure component schemas are defined before use
- Run the generation script with verbose output

### Schema Mismatches

- Use Swagger UI to test actual requests/responses
- Compare OpenAPI spec with actual API behavior
- Update schemas to match implementation

---

## Additional Resources

- [Pode OpenAPI Documentation](https://badgerati.github.io/Pode/docs/features/openapi/overview/)
- [OpenAPI 3.0 Specification](https://swagger.io/specification/)
- [Swagger UI](https://swagger.io/tools/swagger-ui/)
- [ReDoc](https://github.com/Redocly/redoc)

---

## Summary

The OpenAPI implementation in this project provides:

- ✅ Automatic API documentation generation
- ✅ Interactive documentation viewers
- ✅ Static file generation for external tooling
- ✅ Type-safe schema definitions
- ✅ Easy route documentation workflow

By following the patterns and best practices outlined in this guide, you can maintain accurate, up-to-date API documentation that stays synchronized with your implementation.
