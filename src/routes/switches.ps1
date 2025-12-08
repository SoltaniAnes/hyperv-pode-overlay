function global:Add-HvoSwitchRoutes {

    # @openapi
    # path: /switches
    # method: GET
    # summary: List all virtual switches
    # description: Returns the complete list of virtual switches
    # tags: [Switches]
    # responses:
    #   200:
    #     description: List of switches
    #     content:
    #       application/json:
    #         schema:
    #           type: array
    #           items:
    #             $ref: '#/components/schemas/Switch'
    #   500:
    #     $ref: '#/components/responses/Error'
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

    # @openapi
    # path: /switches/{name}
    # method: GET
    # summary: Get switch details
    # description: Returns detailed information for a specific virtual switch
    # tags: [Switches]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Switch name
    # responses:
    #   200:
    #     description: Switch details
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Switch'
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   500:
    #     $ref: '#/components/responses/Error'
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

    # @openapi
    # path: /switches
    # method: POST
    # summary: Create a new virtual switch
    # description: Creates a virtual switch (Internal, Private or External). Idempotent operation. If the switch already exists, returns 200 instead of 201.
    # tags: [Switches]
    # requestBody:
    #   required: true
    #   content:
    #     application/json:
    #       schema:
    #         $ref: '#/components/schemas/SwitchCreateRequest'
    # responses:
    #   201:
    #     description: Switch created
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             created:
    #               type: string
    #   200:
    #     description: Switch already exists
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             exists:
    #               type: string
    #   400:
    #     $ref: '#/components/responses/BadRequest'
    #   500:
    #     $ref: '#/components/responses/Error'
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
    }

    # @openapi
    # path: /switches/{name}
    # method: PUT
    # summary: Update a virtual switch
    # description: Updates switch notes. Only the notes field is modifiable. Idempotent operation.
    # tags: [Switches]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Switch name
    # requestBody:
    #   required: true
    #   content:
    #     application/json:
    #       schema:
    #         $ref: '#/components/schemas/SwitchUpdateRequest'
    # responses:
    #   200:
    #     description: Switch updated
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             updated:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   400:
    #     $ref: '#/components/responses/BadRequest'
    #   500:
    #     $ref: '#/components/responses/Error'
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

    # @openapi
    # path: /switches/{name}
    # method: DELETE
    # summary: Delete a virtual switch
    # description: Deletes a virtual switch. Idempotent operation.
    # tags: [Switches]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Switch name
    # responses:
    #   200:
    #     description: Switch deleted
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             deleted:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   500:
    #     $ref: '#/components/responses/Error'
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
