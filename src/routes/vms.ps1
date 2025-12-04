function global:Add-HvoVmRoutes {

    #
    # GET /vms
    #
    Add-PodeRoute -Method Get -Path '/vms' -ScriptBlock {
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
    }
    #
    # GET /vms/:name
    #
    Add-PodeRoute -Method Get -Path '/vms/:name' -ScriptBlock {
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
    }

    #
    # POST /vms
    #

    Add-PodeRoute -Method Post -Path '/vms' -ScriptBlock {
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
    }

    #
    # PUT /vms/:name
    #

    Add-PodeRoute -Method Put -Path '/vms/:name' -ScriptBlock {
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
            # If no changes were needed → idempotent behavior
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
    }



    #
    # DELETE /vms/:name
    #
    Add-PodeRoute -Method Delete -Path '/vms/:name' -ScriptBlock {
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
    }


    #
    # POST /vms/:name/start
    #
    Add-PodeRoute -Method Post -Path '/vms/:name/start' -ScriptBlock {
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
    }


    #
    # POST /vms/:name/stop
    #
    Add-PodeRoute -Method Post -Path '/vms/:name/stop' -ScriptBlock {
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
                # Extraire le message sans le préfixe
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
    }


    #
    # POST /vms/:name/restart
    #
    Add-PodeRoute -Method Post -Path '/vms/:name/restart' -ScriptBlock {
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
            
            # Détecter les erreurs liées au service d'intégration d'arrêt
            if ($errorMessage -match 'SHUTDOWN_SERVICE_NOT_AVAILABLE|SHUTDOWN_SERVICE_NOT_ENABLED') {
                # Extraire le message sans le préfixe
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
    }


    #
    # POST /vms/:name/suspend
    #
    Add-PodeRoute -Method Post -Path '/vms/:name/suspend' -ScriptBlock {
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
    }


    #
    # POST /vms/:name/resume
    #
    Add-PodeRoute -Method Post -Path '/vms/:name/resume' -ScriptBlock {
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
    }

}
