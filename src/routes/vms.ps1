function global:Add-HvoVmRoutes {
    # Define reusable OpenAPI component schemas for VMs
    Add-PodeOAComponentSchema -Name 'VmSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'Name' -Required),
            (New-PodeOAStringProperty -Name 'State' -Required),
            (New-PodeOAIntProperty -Name 'CPUUsage' -Required),
            (New-PodeOAIntProperty -Name 'MemoryAssigned' -Required),
            (New-PodeOAStringProperty -Name 'Uptime' -Required)
        )
    )

    Add-PodeOAComponentSchema -Name 'VmCreateSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'name' -Required),
            (New-PodeOAIntProperty -Name 'memoryMB' -Required),
            (New-PodeOAIntProperty -Name 'vcpu' -Required),
            (New-PodeOAStringProperty -Name 'diskPath' -Required),
            (New-PodeOAIntProperty -Name 'diskGB' -Required),
            (New-PodeOAStringProperty -Name 'switchName' -Required),
            (New-PodeOAStringProperty -Name 'isoPath')
        )
    )

    Add-PodeOAComponentSchema -Name 'VmUpdateSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAIntProperty -Name 'memoryMB'),
            (New-PodeOAIntProperty -Name 'vcpu'),
            (New-PodeOAStringProperty -Name 'switchName'),
            (New-PodeOAStringProperty -Name 'isoPath')
        )
    )

    Add-PodeOAComponentSchema -Name 'VmResponseSchema' -Schema (
        New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'created'),
            (New-PodeOAStringProperty -Name 'exists'),
            (New-PodeOAStringProperty -Name 'updated'),
            (New-PodeOABoolProperty -Name 'unchanged'),
            (New-PodeOAStringProperty -Name 'name'),
            (New-PodeOAStringProperty -Name 'deleted'),
            (New-PodeOAStringProperty -Name 'started'),
            (New-PodeOAStringProperty -Name 'stopped'),
            (New-PodeOAStringProperty -Name 'restarted'),
            (New-PodeOAStringProperty -Name 'suspended'),
            (New-PodeOAStringProperty -Name 'resumed')
        )
    )

    #
    # GET /vms
    #
    $route = Add-PodeRoute -Method Get -Path '/vms' -ScriptBlock {
        try {
            $vms = Get-HvoVms
            Write-PodeJsonResponse -Value $vms
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to list VMs"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'List all virtual machines' -Description 'Returns a list of all virtual machines on the Hyper-V host' -Tags @('VMs')
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'List of virtual machines' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Array -Properties @(
            (New-PodeOAStringProperty -Name 'Name' -Required),
            (New-PodeOAStringProperty -Name 'State' -Required),
            (New-PodeOAIntProperty -Name 'CPUUsage' -Required),
            (New-PodeOAIntProperty -Name 'MemoryAssigned' -Required),
            (New-PodeOAStringProperty -Name 'Uptime' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to list VMs' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    #
    # GET /vms/:name
    #
    $route = Add-PodeRoute -Method Get -Path '/vms/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']

            $vm = Get-HvoVm -Name $name
            if (-not $vm) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value $vm
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to get VM"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Get virtual machine details' -Description 'Returns detailed information about a specific virtual machine' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'Virtual machine details' -ContentSchemas @{
        'application/json' = 'VmSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to get VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }





    #
    # GET /vms/by-name/:name
    #

    $route = Add-PodeRoute -Method Get -Path '/vms/by-name/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']

            $vms = Get-HvoVmByName -Name $name

            # Always return an array (even if empty)
            Write-PodeJsonResponse -StatusCode 200 -Value $vms
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Failed to retrieve VMs by name"
                detail = $_.Exception.Message
            }
        }
    } -PassThru


    #
    # POST /vms
    #

    $route = Add-PodeRoute -Method Post -Path '/vms' -ScriptBlock {
        try {
            $b = Get-HvoJsonBody

            if (-not $b) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            $result = New-HvoVm @b

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
                error = "Failed to create VM"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    <#

    $route | Set-PodeOARouteInfo -Summary 'Create a new virtual machine' -Description 'Creates a new virtual machine with the specified configuration. Returns 200 if VM already exists (idempotent)' -Tags @('VMs')
    $route | Set-PodeOARequest -RequestBody (New-PodeOARequestBody -ContentSchemas @{
        'application/json' = 'VmCreateSchema'
    } -Required)
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'VM already exists' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'exists' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 201 -Description 'VM created successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'created' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 400 -Description 'Invalid JSON' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to create VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }

    #
    # PUT /vms/:name
    #

    $route = Add-PodeRoute -Method Put -Path '/vms/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $body = Get-HvoJsonBody

            if (-not $body) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            # Only pass parameters actually provided by the client
            $params = @{ Name = $name }

            if ($body.memoryMB)   { $params.MemoryMB   = $body.memoryMB }
            if ($body.vcpu)       { $params.Vcpu       = $body.vcpu }
            if ($body.switchName) { $params.SwitchName = $body.switchName }
            if ($body.isoPath)    { $params.IsoPath    = $body.isoPath }

            $result = Set-HvoVm @params

            #
            # Return 404 when VM does not exist
            #
            if ($result.Error -eq "VM not found") {
                Write-PodeJsonResponse -StatusCode 404 -Value $result
                return
            }

            #
            # If no changes were needed -> idempotent behavior
            #
            if ($result.Updated -eq $false -and $result.Unchanged) {
                Write-PodeJsonResponse -StatusCode 200 -Value @{
                    unchanged = $true
                    name      = $name
                }
                return
            }

            #
            # If an update condition failed (e.g., VM running)
            #
            if ($result.Updated -eq $false -and $result.Error) {
                Write-PodeJsonResponse -StatusCode 409 -Value $result
                return
            }

            #
            # Success: the VM was updated
            #
            Write-PodeJsonResponse -StatusCode 200 -Value @{
                updated = $true
                name    = $name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Failed to update VM"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Update a virtual machine' -Description 'Updates configuration of an existing virtual machine. VM must be stopped. Returns 200 with unchanged=true if no changes were needed' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    ) -RequestBody (New-PodeOARequestBody -ContentSchemas @{
        'application/json' = 'VmUpdateSchema'
    } -Required)
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'VM updated successfully or unchanged' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOABoolProperty -Name 'updated'),
            (New-PodeOABoolProperty -Name 'unchanged'),
            (New-PodeOAStringProperty -Name 'name')
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 400 -Description 'Invalid JSON' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 409 -Description 'Update conflict (e.g., VM is running)' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to update VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }

#>


$route = Add-PodeRoute -Method Put -Path '/vms/:id' -ScriptBlock {
    try {
        $idRaw = $WebEvent.Parameters['id']

        # Validate GUID
        try { $id = [Guid]$idRaw }
        catch {
            Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid VM id (expected GUID)" }
            return
        }

        $body = Get-HvoJsonBody
        if (-not $body) {
            Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
            return
        }

        # Only pass parameters actually provided by the client
        $params = @{ Id = $id }

        if ($null -ne $body.memoryMB)        { $params.MemoryMB        = [int]$body.memoryMB }
        if ($null -ne $body.vcpu)            { $params.Vcpu            = [int]$body.vcpu }
        if ($null -ne $body.isoPath)         { $params.IsoPath         = [string]$body.isoPath }
        if ($null -ne $body.networkAdapters) { $params.NetworkAdapters = $body.networkAdapters }

        $result = Set-HvoVm @params

        # 404
        if ($result.Error -eq "VM not found") {
            Write-PodeJsonResponse -StatusCode 404 -Value $result
            return
        }

        # unchanged (idempotent)
        if ($result.Updated -eq $false -and $result.Unchanged) {
            Write-PodeJsonResponse -StatusCode 200 -Value @{
                unchanged = $true
                id        = "$id"
                name      = $result.Name
            }
            return
        }

        # conflict (eg running)
        if ($result.Updated -eq $false -and $result.Error) {
            Write-PodeJsonResponse -StatusCode 409 -Value $result
            return
        }

        # updated
        Write-PodeJsonResponse -StatusCode 200 -Value @{
            updated = $true
            id      = "$id"
            name    = $result.Name
        }
    }
    catch {
        Write-PodeJsonResponse -StatusCode 500 -Value @{
            error  = "Failed to update VM"
            detail = $_.Exception.Message
        }
    }
} -PassThru


    #
    # DELETE /vms/:name
    #
    $route = Add-PodeRoute -Method Delete -Path '/vms/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $ok = Remove-HvoVm -Name $name -RemoveDisks:$true

            if (-not $ok) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                deleted = $name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to delete VM"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Delete a virtual machine' -Description 'Deletes a virtual machine and its associated virtual hard disks' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'VM deleted successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'deleted' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to delete VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }


    #
    # POST /vms/:name/start
    #
    $route = Add-PodeRoute -Method Post -Path '/vms/:name/start' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $result = Start-HvoVm -Name $name

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                started = $result.Name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to start VM"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Start a virtual machine' -Description 'Starts a virtual machine. If the VM is paused, it will be resumed' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'VM started successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'started' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to start VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }


    #
    # POST /vms/:name/stop
    #
    $route = Add-PodeRoute -Method Post -Path '/vms/:name/stop' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']

            # Extract force parameter from query or body
            $force = $false
            if ($WebEvent.Query['force'] -eq "true") {
                $force = $true
            }
            else {
                $b = Get-HvoJsonBody
                if ($b -and $b.force -eq $true) {
                    $force = $true
                }
            }

            $result = Stop-HvoVm -Name $name -Force:$force

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            if ($result.AlreadyStopped) {
                Write-PodeJsonResponse -StatusCode 409 -Value @{
                    error = "VM is already stopped"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                stopped = $result.Name
            }
        }
        catch {
            $errorMessage = $_.Exception.Message

            # Detect errors related to the shutdown integration service
            if ($errorMessage -match 'SHUTDOWN_SERVICE_NOT_AVAILABLE|SHUTDOWN_SERVICE_NOT_ENABLED') {
                # Extract the message without the prefix
                $detail = $errorMessage -replace '^[^:]+:\s*', ''
                Write-PodeJsonResponse -StatusCode 422 -Value @{
                    error = "Shutdown integration service not available or not enabled"
                    detail = $detail
                }
                return
            }

            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to stop VM"
                detail = $errorMessage
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Stop a virtual machine' -Description 'Stops a virtual machine gracefully. Use force=true query parameter or body to force shutdown' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path),
        (New-PodeOABoolProperty -Name 'force' | ConvertTo-PodeOAParameter -In Query)
    ) -RequestBody (New-PodeOARequestBody -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOABoolProperty -Name 'force')
        ))
    })
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'VM stopped successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'stopped' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 409 -Description 'VM is already stopped' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 422 -Description 'Shutdown integration service not available or not enabled' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to stop VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }


    #
    # POST /vms/:name/restart
    #
    $route = Add-PodeRoute -Method Post -Path '/vms/:name/restart' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']

            # Extract force parameter from query or body
            $force = $false
            if ($WebEvent.Query['force'] -eq "true") {
                $force = $true
            }
            else {
                $b = Get-HvoJsonBody
                if ($b -and $b.force -eq $true) {
                    $force = $true
                }
            }

            $result = Restart-HvoVm -Name $name -Force:$force

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                restarted = $result.Name
            }
        }
        catch {
            $errorMessage = $_.Exception.Message

            # Detect errors related to the shutdown integration service
            if ($errorMessage -match 'SHUTDOWN_SERVICE_NOT_AVAILABLE|SHUTDOWN_SERVICE_NOT_ENABLED') {
                # Extract the message without the prefix
                $detail = $errorMessage -replace '^[^:]+:\s*', ''
                Write-PodeJsonResponse -StatusCode 422 -Value @{
                    error = "Shutdown integration service not available or not enabled"
                    detail = $detail
                }
                return
            }

            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to restart VM"
                detail = $errorMessage
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Restart a virtual machine' -Description 'Restarts a virtual machine. Use force=true query parameter or body to force shutdown before restart' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path),
        (New-PodeOABoolProperty -Name 'force' | ConvertTo-PodeOAParameter -In Query)
    ) -RequestBody (New-PodeOARequestBody -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOABoolProperty -Name 'force')
        ))
    })
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'VM restarted successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'restarted' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 422 -Description 'Shutdown integration service not available or not enabled' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to restart VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }


    #
    # POST /vms/:name/suspend
    #
    $route = Add-PodeRoute -Method Post -Path '/vms/:name/suspend' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $result = Suspend-HvoVm -Name $name

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            if ($result.AlreadySuspended) {
                Write-PodeJsonResponse -StatusCode 409 -Value @{
                    error = "VM is already suspended"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                suspended = $result.Name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to suspend VM"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Suspend a virtual machine' -Description 'Suspends (pauses) a running virtual machine' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'VM suspended successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'suspended' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 409 -Description 'VM is already suspended' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to suspend VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }


    #
    # POST /vms/:name/resume
    #
    $route = Add-PodeRoute -Method Post -Path '/vms/:name/resume' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $result = Resume-HvoVm -Name $name

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            if ($result.AlreadyRunning) {
                Write-PodeJsonResponse -StatusCode 409 -Value @{
                    error = "VM is already running"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                resumed = $result.Name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to resume VM"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'Resume a virtual machine' -Description 'Resumes a suspended virtual machine' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'VM resumed successfully' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Properties @(
            (New-PodeOAStringProperty -Name 'resumed' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 409 -Description 'VM is already running' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to resume VM' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }

    #
    # GET /vms/:name/network-adapters
    #
    $route = Add-PodeRoute -Method Get -Path '/vms/:name/network-adapters' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']

            $adapters = Get-HvoVmNetworkAdapters -Name $name
            if ($null -eq $adapters) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value $adapters
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to list network adapters"
                detail = $_.Exception.Message
            }
        }
    } -PassThru

    $route | Set-PodeOARouteInfo -Summary 'List network adapters of a virtual machine' -Description 'Returns a list of all network adapters for a specific virtual machine' -Tags @('VMs')
    $route | Set-PodeOARequest -Parameters @(
        (New-PodeOAStringProperty -Name 'name' -Required | ConvertTo-PodeOAParameter -In Path)
    )
    $route | Add-PodeOAResponse -StatusCode 200 -Description 'List of network adapters' -ContentSchemas @{
        'application/json' = (New-PodeOAObjectProperty -Array -Properties @(
            (New-PodeOAStringProperty -Name 'Name' -Required),
            (New-PodeOAStringProperty -Name 'SwitchName'),
            (New-PodeOAStringProperty -Name 'Type' -Required),
            (New-PodeOAStringProperty -Name 'MacAddress' -Required),
            (New-PodeOAStringProperty -Name 'Status' -Required)
        ))
    }
    $route | Add-PodeOAResponse -StatusCode 404 -Description 'VM not found' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }
    $route | Add-PodeOAResponse -StatusCode 500 -Description 'Failed to list network adapters' -ContentSchemas @{
        'application/json' = 'ErrorSchema'
    }

}
