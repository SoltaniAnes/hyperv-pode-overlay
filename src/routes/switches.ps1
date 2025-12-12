function global:Add-HvoSwitchRoutes {
    # Define reusable OpenAPI component schemas for Switches
    Add-PodeOAComponentSchema -Name 'SwitchSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'Name' -Required),
            (New-PodeOAStringProperty -Name 'SwitchType' -Required -Enum @('Internal', 'External', 'Private')),
            (New-PodeOAStringProperty -Name 'Notes')
        )
    )

    Add-PodeOAComponentSchema -Name 'SwitchCreateSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'name' -Required),
            (New-PodeOAStringProperty -Name 'type' -Required -Enum @('Internal', 'External', 'Private')),
            (New-PodeOAStringProperty -Name 'netAdapterName'),
            (New-PodeOAStringProperty -Name 'notes')
        )
    )

    Add-PodeOAComponentSchema -Name 'SwitchUpdateSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'notes')
        )
    )

    #
    # GET /switches
    #
    $route = Add-PodeRoute -Method Get -Path '/switches' -ScriptBlock {
        try {
            Write-PodeJsonResponse -Value (Get-HvoSwitches)
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to list switches"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'List all virtual switches' -Description 'Returns a list of all virtual switches on the Hyper-V host' -Tags @('Switches')
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'List of virtual switches' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Array -Properties @(
            (New-PodeOAStringProperty -Name 'Name' -Required),
            (New-PodeOAStringProperty -Name 'SwitchType' -Required -Enum @('Internal', 'External', 'Private')),
            (New-PodeOAStringProperty -Name 'Notes')
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to list switches' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }


    #
    # GET /switches/:name
    #
    $route = Add-PodeRoute -Method Get -Path '/switches/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']

            $sw = Get-HvoSwitch -Name $name
            if (-not $sw) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "Switch not found"
                }
                return
            }

            Write-PodeJsonResponse -Value $sw
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to get switch"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Get virtual switch details' -Description 'Returns detailed information about a specific virtual switch' -Tags @('Switches')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'Virtual switch details' -ContentSchemas @{
        'application/json' = 'SwitchSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'Switch not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to get switch' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }


    #
    # POST /switches
    #
    $route = Add-PodeRoute -Method Post -Path '/switches' -ScriptBlock {
        try {
            $b = Get-HvoJsonBody

            if (-not $b) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            $result = New-HvoSwitch `
                -Name $b.name `
                -Type $b.type `
                -NetAdapterName $b.netAdapterName `
                -Notes $b.notes

            if ($result.Exists) {
                Write-PodeJsonResponse -StatusCode 200 -Value @{
                    exists = $result.Name
                }
            }
            else {
                Write-PodeJsonResponse -StatusCode 201 -Value @{
                    created = $result.Name
                }
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to create switch"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Create a new virtual switch' -Description 'Creates a new virtual switch. For External switches, netAdapterName is required. Returns 200 if switch already exists (idempotent)' -Tags @('Switches')
    $route | Set-PodeOARequest -RequestBody (New-PodeOARequestBody -ContentSchemas @{
        'application/json' = 'SwitchCreateSchema'
    } -Required)
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'Switch already exists' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'exists' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 201 -Description 'Switch created successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'created' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 400 -Description 'Invalid JSON' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to create switch' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }

    #
    # PUT /switches/:name
    #
    $route = Add-PodeRoute -Method Put -Path '/switches/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $body = Get-HvoJsonBody

            if (-not $body) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            # Only pass fields that the user provided
            $params = @{ Name = $name }

            if ($body.notes) {
                $params.Notes = $body.notes
            }

            $result = Set-HvoSwitch @params

            if (-not $result.Updated) {
                Write-PodeJsonResponse -StatusCode 404 -Value $result
                return
            }

            Write-PodeJsonResponse -Value @{ updated = $result.Name }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Failed to update switch"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Update a virtual switch' -Description 'Updates the notes field of an existing virtual switch' -Tags @('Switches')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    ) -RequestBody (New-PodeOARequestBody -ContentSchemas @{
        'application/json' = 'SwitchUpdateSchema'
    } -Required)
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'Switch updated successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'updated' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 400 -Description 'Invalid JSON' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'Switch not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to update switch' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }



    #
    # DELETE /switches/:name
    #
    $route = Add-PodeRoute -Method Delete -Path '/switches/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $ok = Remove-HvoSwitch -Name $name

            if (-not $ok) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "Switch not found"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                deleted = $name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to delete switch"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Delete a virtual switch' -Description 'Deletes a virtual switch' -Tags @('Switches')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'Switch deleted successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'deleted' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'Switch not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to delete switch' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }

}
