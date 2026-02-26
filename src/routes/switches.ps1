function global:Add-HvoSwitchRoutes {
    # Define reusable OpenAPI component schemas for Switches
    Add-PodeOAComponentSchema -Name 'SwitchSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'Id' -Required),
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
            (New-PodeOAStringProperty -Name 'Id' -Required),
            (New-PodeOAStringProperty -Name 'Name' -Required),
            (New-PodeOAStringProperty -Name 'SwitchType' -Required -Enum @('Internal', 'External', 'Private')),
            (New-PodeOAStringProperty -Name 'Notes')
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to list switches' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }


    #
    # GET /switches/:id
    #
    $route = Add-PodeRoute -Method Get -Path '/switches/:id' -ScriptBlock {
        try {
            $id = $WebEvent.Parameters['id']
            $sw = Get-HvoSwitch -Id $id
            if (-not $sw) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{ error = "Switch not found" }
                return
            }
            Write-PodeJsonResponse -Value $sw
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{ error = "Failed to get switch"; detail = $_.Exception.Message }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Get virtual switch details by Id' -Description 'Returns detailed information about a specific virtual switch by its GUID' -Tags @('Switches')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'id' -Required | ConvertTo-PodeOAParameter -In Path)
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
    # GET /switches/by-name/:name
    #
    $route = Add-PodeRoute -Method Get -Path '/switches/by-name/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $list = Get-HvoSwitchByName -Name $name
            Write-PodeJsonResponse -Value $list
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{ error = "Failed to get switches by name"; detail = $_.Exception.Message }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Get switches by name' -Description 'Returns an array of virtual switches matching the given name' -Tags @('Switches')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'Array of switches with matching name' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Array -Properties @(
            (New-PodeOAStringProperty -Name 'Id' -Required),
            (New-PodeOAStringProperty -Name 'Name' -Required),
            (New-PodeOAStringProperty -Name 'SwitchType' -Required),
            (New-PodeOAStringProperty -Name 'Notes')
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to get switches by name' -ContentSchemas @{
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

            Write-PodeJsonResponse -StatusCode 201 -Value @{
                created = $result.Name
                id      = $result.Id
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to create switch"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Create a new virtual switch' -Description 'Creates a new virtual switch. Each call returns 201 with id. For External switches, netAdapterName is required.' -Tags @('Switches')
    $route | Set-PodeOARequest -RequestBody (New-PodeOARequestBody -ContentSchemas @{
        'application/json' = 'SwitchCreateSchema'
    } -Required)
    $route | Add-PodeOAResponse -StatusCode 201 -Description 'Switch created successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'created' -Required),
            (New-PodeOAStringProperty -Name 'id' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 400 -Description 'Invalid JSON' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to create switch' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }

    #
    # PUT /switches/:id
    #
    $route = Add-PodeRoute -Method Put -Path '/switches/:id' -ScriptBlock {
        try {
            $id = $WebEvent.Parameters['id']
            $body = Get-HvoJsonBody

            if (-not $body) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            $params = @{ Id = $id }
            if ($body.notes) { $params.Notes = $body.notes }

            $result = Set-HvoSwitch @params

            if (-not $result.Updated) {
                Write-PodeJsonResponse -StatusCode 404 -Value $result
                return
            }

            Write-PodeJsonResponse -Value @{ updated = $result.Name; id = $result.Id }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Failed to update switch"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Update a virtual switch' -Description 'Updates the notes field of an existing virtual switch by Id' -Tags @('Switches')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'id' -Required | ConvertTo-PodeOAParameter -In Path)
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
    # DELETE /switches/:id
    #
    $route = Add-PodeRoute -Method Delete -Path '/switches/:id' -ScriptBlock {
        try {
            $id = $WebEvent.Parameters['id']
            $ok = Remove-HvoSwitch -Id $id

            if (-not $ok) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{ error = "Switch not found" }
                return
            }

            Write-PodeJsonResponse -Value @{ deleted = $id; id = $id }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to delete switch"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Delete a virtual switch' -Description 'Deletes a virtual switch by Id' -Tags @('Switches')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'id' -Required | ConvertTo-PodeOAParameter -In Path)
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
