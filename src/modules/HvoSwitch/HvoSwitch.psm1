function New-HvoSwitch {
    param(
        [string] $Name,
        [ValidateSet('Internal', 'External', 'Private')] [string] $Type,
        [string] $NetAdapterName,
        [string] $Notes
    )

    $existing = Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        return @{
            Exists = $true
            Name   = $existing.Name
        }
    }

    switch ($Type) {
        'Internal' {
            $sw = New-VMSwitch -Name $Name -SwitchType Internal
        }
        'Private' {
            $sw = New-VMSwitch -Name $Name -SwitchType Private
        }
        'External' {
            if (-not $NetAdapterName) {
                throw "External switch requires -NetAdapterName"
            }

            $sw = New-VMSwitch -Name $Name -NetAdapterName $NetAdapterName -AllowManagementOS $true
        }
    }

    # Apply notes if provided
    if ($Notes) {
        Set-VMSwitch -Name $Name -Notes $Notes | Out-Null
    }

    return @{
        Exists = $false
        Name   = $sw.Name
    }
}

function Set-HvoSwitch {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string] $Notes
    )

    try {
        $sw = Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue
        if (-not $sw) {
            return @{
                Updated = $false
                Error   = "Switch not found"
            }
        }

        #
        # Update "Notes" only (the only safe modifiable property)
        #
        if ($PSBoundParameters.ContainsKey("Notes")) {
            Set-VMSwitch -Name $Name -Notes $Notes -ErrorAction Stop
        }

        return @{
            Updated = $true
            Name    = $Name
        }
    }
    catch {
        throw $_
    }
}


function Get-HvoSwitch {
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    return Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue
}

function Get-HvoSwitches {
    Get-VMSwitch | Select-Object Name, SwitchType, Notes
}

function Remove-HvoSwitch {
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    $sw = Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue
    if (-not $sw) {
        return $false
    }

    try {
        Remove-VMSwitch -Name $Name -Force -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

Export-ModuleMember -Function *
