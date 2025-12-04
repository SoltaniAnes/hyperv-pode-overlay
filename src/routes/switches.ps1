function global:Add-HvoSwitchRoutes {

    #
    # GET /switches
    #
    Add-PodeRoute -Method Get -Path '/switches' -ScriptBlock {
        try {
            Write-PodeJsonResponse -Value (Get-HvoSwitches)
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to list switches"
                detail = $_.Exception.Message
            }
        }
    }


    #
    # GET /switches/:name
    #
    Add-PodeRoute -Method Get -Path '/switches/:name' -ScriptBlock {
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
    }


    #
    # POST /switches
    #
    Add-PodeRoute -Method Post -Path '/switches' -ScriptBlock {
        try {
            $b = Get-HvoJsonBody

            if (-not $b) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            $result = New-HvoSwitch `
                -Name $b.name `
                -Type $b.type `
                -NetAdapterName $b.netAdapterName`
                -Notes  $b.notes

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
    }

    #
    # PUT /switches/:name
    #
    Add-PodeRoute -Method Put -Path '/switches/:name' -ScriptBlock {
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
    }



    #
    # DELETE /switches/:name
    #
    Add-PodeRoute -Method Delete -Path '/switches/:name' -ScriptBlock {
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
    }

}
