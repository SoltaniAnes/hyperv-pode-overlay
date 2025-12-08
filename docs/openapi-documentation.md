# OpenAPI Documentation - Implementation and Usage Guide

This guide explains how to document API routes with inline comments to automatically generate the OpenAPI v3 specification.

## Overview

The OpenAPI generation system allows keeping documentation synchronized with code by using inline comments in route files. Documentation is automatically generated from these comments, similar to the approach used by safrs (Python) or swagger-jsdoc (Node.js).

## @openapi Comment Format

Each route must be documented with a comment block preceding the `Add-PodeRoute` call. The format uses a simplified YAML syntax in PowerShell comments.

### Basic Structure

```powershell
# @openapi
# path: /endpoint
# method: GET
# summary: Short description
# description: Detailed description (optional)
# tags: [Tag1, Tag2]
# responses:
#   200:
#     description: Success
#     content:
#       application/json:
#         schema:
#           type: object
Add-PodeRoute -Method Get -Path '/endpoint' -ScriptBlock {
    # ...
}
```

### Required Elements

- `# @openapi` : Start marker for the documentation block
- `path` : Endpoint path (use `{name}` for path parameters)
- `method` : HTTP method (GET, POST, PUT, DELETE, etc.)
- `summary` : Short description of the endpoint
- `responses` : At least one response must be defined

### Optional Elements

- `description` : Detailed description of the endpoint
- `tags` : Array of tags to organize endpoints
- `parameters` : Path, query, or header parameters
- `requestBody` : Request body for POST/PUT
- `deprecated` : Mark an endpoint as deprecated

## Documentation Examples

### Simple GET Endpoint

```powershell
# @openapi
# path: /vms
# method: GET
# summary: List all virtual machines
# description: Returns the complete list of VMs with their current state
# tags: [VMs]
# responses:
#   200:
#     description: List of VMs
#     content:
#       application/json:
#         schema:
#           type: array
#           items:
#             $ref: '#/components/schemas/Vm'
#   500:
#     $ref: '#/components/responses/Error'
Add-PodeRoute -Method Get -Path '/vms' -ScriptBlock {
    # ...
}
```

### Endpoint with Path Parameter

```powershell
# @openapi
# path: /vms/{name}
# method: GET
# summary: Get VM details
# tags: [VMs]
# parameters:
#   - name: name
#     in: path
#     required: true
#     schema:
#       type: string
#     description: VM name
# responses:
#   200:
#     description: VM details
#     content:
#       application/json:
#         schema:
#           $ref: '#/components/schemas/Vm'
#   404:
#     $ref: '#/components/responses/NotFound'
Add-PodeRoute -Method Get -Path '/vms/:name' -ScriptBlock {
    # ...
}
```

**Important Note**: In Pode code, use `:name` for path parameters, but in OpenAPI documentation, use `{name}`. The parser automatically converts `:name` to `{name}`.

### POST Endpoint with requestBody

```powershell
# @openapi
# path: /vms
# method: POST
# summary: Create a new virtual machine
# description: Idempotent operation. If the VM already exists, returns 200 instead of 201.
# tags: [VMs]
# requestBody:
#   required: true
#   content:
#     application/json:
#       schema:
#         $ref: '#/components/schemas/VmCreateRequest'
# responses:
#   201:
#     description: VM created
#     content:
#       application/json:
#         schema:
#           type: object
#           properties:
#             created:
#               type: string
#   200:
#     description: VM already exists
#     content:
#       application/json:
#         schema:
#           type: object
#           properties:
#             exists:
#               type: string
#   400:
#     $ref: '#/components/responses/BadRequest'
Add-PodeRoute -Method Post -Path '/vms' -ScriptBlock {
    # ...
}
```

### Endpoint with Query Parameters

```powershell
# @openapi
# path: /vms/{name}/stop
# method: POST
# summary: Stop a virtual machine
# tags: [VMs]
# parameters:
#   - name: name
#     in: path
#     required: true
#     schema:
#       type: string
#   - name: force
#     in: query
#     required: false
#     schema:
#       type: boolean
#     description: Force stop if true
# requestBody:
#   required: false
#   content:
#     application/json:
#       schema:
#         type: object
#         properties:
#           force:
#             type: boolean
# responses:
#   200:
#     description: VM stopped
#     content:
#       application/json:
#         schema:
#           type: object
#           properties:
#             stopped:
#               type: string
Add-PodeRoute -Method Post -Path '/vms/:name/stop' -ScriptBlock {
    # ...
}
```

## Using References ($ref)

To avoid duplication, use references to common schemas and responses defined in the OpenAPI module.

### Schema References

```yaml
# schema:
#   $ref: '#/components/schemas/Vm'
```

### Common Response References

```yaml
# 404:
#   $ref: '#/components/responses/NotFound'
# 500:
#   $ref: '#/components/responses/Error'
```

## Available Schemas

The following schemas are predefined in the OpenAPI module:

### Data Schemas

- `Error` : Standard error structure with `error` and `detail`
- `Vm` : VM object with Name, State, CPUUsage, MemoryAssigned, Uptime
- `VmCreateRequest` : VM creation request
- `VmUpdateRequest` : VM update request
- `VmActionResponse` : VM action responses (created, exists, deleted, etc.)
- `Switch` : Switch object with Name, SwitchType, Notes
- `SwitchCreateRequest` : Switch creation request
- `SwitchUpdateRequest` : Switch update request
- `HealthResponse` : Health check response

### Common Responses

- `Error` : Server error (500)
- `NotFound` : Resource not found (404)
- `BadRequest` : Invalid request (400)

## Documentation Generation

### Static Generation

Generates an `openapi.json` file from comments:

```powershell
pwsh src/scripts/generate-openapi.ps1
```

The file is generated by default in `docs/openapi.json`. You can specify a custom path:

```powershell
pwsh src/scripts/generate-openapi.ps1 -OutputPath "./custom-path/openapi.json"
```

The script automatically uses the server configuration (`config.ps1`) to determine the base URL. You can also specify it manually:

```powershell
pwsh src/scripts/generate-openapi.ps1 -BaseUrl "http://example.com:8080"
```

### Dynamic Generation

The `/openapi.json` route exposes the generated OpenAPI specification on the fly:

```bash
curl http://localhost:8080/openapi.json
```

This route generates documentation in real-time from code comments, ensuring it's always up-to-date with the implementation.

## Rules and Best Practices

### Formatting Rules

1. **@openapi Marker** : Must be on a separate line, preceded by `#`
2. **Indentation** : Use 2 spaces for each indentation level
3. **Comments** : All documentation lines must start with `#`
4. **Continuous Block** : The comment block must be continuous until the `Add-PodeRoute` call

### Path Conversion

- **In Pode Code** : Use `:name` for path parameters
- **In Documentation** : Use `{name}` for path parameters
- The parser automatically converts `:name` to `{name}` during generation

### Tags

Use consistent tags to organize endpoints:

- `[VMs]` : Endpoints related to virtual machines
- `[Switches]` : Endpoints related to virtual switches
- `[Health]` : Health check endpoints
- `[Meta]` : Metadata endpoints (like `/openapi.json`)

### Responses

1. **Always document possible status codes** : 200, 201, 400, 404, 500, etc.
2. **Use common references** : Prefer `$ref: '#/components/responses/Error'` rather than redefining
3. **Describe responses** : Add a description for each response
4. **Content schemas** : Specify the JSON schema for 200/201 responses

### Parameters

1. **Path parameters** : Always marked as `required: true`
2. **Query parameters** : Mark `required: false` if optional
3. **Descriptions** : Add a description for each parameter

### RequestBody

1. **Required** : Specify if the body is mandatory (`required: true/false`)
2. **Schemas** : Use references to predefined schemas when possible
3. **Content-Type** : Always specify `application/json`

## File Structure

Route files must follow this structure:

```powershell
function global:Add-HvoXxxRoutes {
    
    # @openapi
    # ... documentation ...
    Add-PodeRoute -Method Get -Path '/endpoint' -ScriptBlock {
        # Implementation
    }
    
    # @openapi
    # ... documentation ...
    Add-PodeRoute -Method Post -Path '/endpoint' -ScriptBlock {
        # Implementation
    }
}
```

## Documentation Verification

### Verify Generation

After adding or modifying comments, test the generation:

```powershell
# Generate the file
pwsh src/scripts/generate-openapi.ps1

# Verify that the file is valid (optional, requires external tools)
# npx swagger-cli validate docs/openapi.json
```

### Visualize Documentation

Once generated, you can visualize the documentation with:

- **Swagger UI** : <https://swagger.io/tools/swagger-ui/>
- **Redoc** : <https://github.com/Redocly/redoc>
- **Postman** : Import the `openapi.json` file

### Example with Swagger UI

```bash
# Install swagger-ui (via Docker)
docker run -p 8081:8080 -e SWAGGER_JSON=/openapi.json -v $(pwd)/docs:/openapi swaggerapi/swagger-ui

# Access http://localhost:8081
```

## Troubleshooting

### Parser Doesn't Detect Comments

1. Verify that `# @openapi` is on a separate line
2. Verify there are no empty lines between `# @openapi` and other comments
3. Verify that the comment block ends just before `Add-PodeRoute`

### Path Parameters Are Not Converted

Make sure that in the documentation, you use `{name}` and not `:name`. The parser converts `:name` from code to `{name}` in the spec, but in inline documentation, use `{name}` directly.

### $ref References Don't Work

1. Verify that the schema or response exists in `Add-OpenApiSchemas` or `Add-OpenApiResponses`
2. Verify the syntax: `$ref: '#/components/schemas/Vm'` (with the `#` at the beginning)
3. Verify indentation: the reference must be at the correct level

### Generation Errors

If generation fails:

1. Check the script logs to identify the problematic endpoint
2. Verify YAML syntax in comments
3. Verify that all required fields are present

## Adding New Schemas

To add a new reusable schema:

1. Modify `src/modules/HvoOpenApi/HvoOpenApi.psm1`
1. Add the schema in the `Add-OpenApiSchemas` function:

```powershell
$Spec.components.schemas.NewSchema = @{
    type = "object"
    properties = @{
        field1 = @{ type = "string" }
        field2 = @{ type = "integer" }
    }
    required = @("field1")
}
```

1. Use it in your comments with `$ref: '#/components/schemas/NewSchema'`

## Complete Example

Here is a complete example of a documented endpoint:

```powershell
# @openapi
# path: /vms/{name}
# method: PUT
# summary: Update a virtual machine
# description: Updates properties of an existing VM. Idempotent operation.
# tags: [VMs]
# parameters:
#   - name: name
#     in: path
#     required: true
#     schema:
#       type: string
#     description: VM name
# requestBody:
#   required: true
#   content:
#     application/json:
#       schema:
#         $ref: '#/components/schemas/VmUpdateRequest'
# responses:
#   200:
#     description: VM updated or unchanged
#     content:
#       application/json:
#         schema:
#           $ref: '#/components/schemas/VmActionResponse'
#   404:
#     $ref: '#/components/responses/NotFound'
#   409:
#     description: Conflict (e.g., VM is running)
#     content:
#       application/json:
#         schema:
#           $ref: '#/components/schemas/Error'
#   400:
#     $ref: '#/components/responses/BadRequest'
#   500:
#     $ref: '#/components/responses/Error'
Add-PodeRoute -Method Put -Path '/vms/:name' -ScriptBlock {
    try {
        $name = $WebEvent.Parameters['name']
        $body = Get-HvoJsonBody
        # ... implementation ...
    }
    catch {
        # ... error handling ...
    }
}
```

## Advantages of This Approach

1. **Up-to-date Documentation** : Documentation is always synchronized with code
2. **Less Maintenance** : No need to maintain a separate OpenAPI file
3. **Inline Documentation** : Documentation is visible directly in the code
4. **Automatic Generation** : No need to manually generate the specification
5. **Standards** : Compatible with all OpenAPI tools (Swagger UI, Redoc, Postman, etc.)

## Resources

- [OpenAPI 3.0 Specification](https://swagger.io/specification/)
- [Swagger UI](https://swagger.io/tools/swagger-ui/)
- [Redoc](https://github.com/Redocly/redoc)
