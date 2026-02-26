function New-HvoSwitch {
    param(
        [string] $Name,
        [ValidateSet('Internal', 'External', 'Private')] [string] $Type,
        [string] $NetAdapterName,
        [string] $Notes
    )

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

    if ($Notes) {
        Set-VMSwitch -Name $Name -Notes $Notes | Out-Null
    }

    $idValue = if ($sw.Id) { $sw.Id.ToString() } else { $null }
    return @{
        Name = $sw.Name
        Id   = $idValue
    }
}

function Set-HvoSwitch {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [string] $Notes
    )

    try {
        try { $guid = [guid]$Id } catch { return @{ Updated = $false; Error = "Switch not found" } }
        $sw = Get-VMSwitch -Id $guid -ErrorAction SilentlyContinue
        if (-not $sw) {
            return @{
                Updated = $false
                Error   = "Switch not found"
            }
        }

        $swName = $sw.Name

        if ($PSBoundParameters.ContainsKey("Notes")) {
            Set-VMSwitch -Name $swName -Notes $Notes -ErrorAction Stop
        }

        return @{
            Updated = $true
            Name    = $swName
            Id      = $sw.Id.ToString()
        }
    }
    catch {
        throw $_
    }
}


function Get-HvoSwitch {
    param(
        [Parameter(Mandatory)]
        [string] $Id
    )

    try { $guid = [guid]$Id } catch { return $null }
    $sw = Get-VMSwitch -Id $guid -ErrorAction SilentlyContinue
    if (-not $sw) {
        return $null
    }

    return [PSCustomObject]@{
        Id         = $sw.Id.ToString()
        Name       = $sw.Name
        SwitchType = $sw.SwitchType.ToString()
        Notes      = $sw.Notes
    }
}

function Get-HvoSwitchByName {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $switches = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name }
    if (-not $switches) {
        return @()
    }
    if ($switches -isnot [Array]) {
        $switches = @($switches)
    }
    return $switches | ForEach-Object {
        [PSCustomObject]@{
            Id         = $_.Id.ToString()
            Name       = $_.Name
            SwitchType = $_.SwitchType.ToString()
            Notes      = $_.Notes
        }
    }
}

function Get-HvoSwitches {
    $switches = Get-VMSwitch -ErrorAction SilentlyContinue
    return $switches | ForEach-Object {
        [PSCustomObject]@{
            Id         = $_.Id.ToString()
            Name       = $_.Name
            SwitchType = $_.SwitchType.ToString()
            Notes      = $_.Notes
        }
    }
}

function Remove-HvoSwitch {
    param(
        [Parameter(Mandatory)] [string] $Id
    )

    try { $guid = [guid]$Id } catch { return $false }
    $sw = Get-VMSwitch -Id $guid -ErrorAction SilentlyContinue
    if (-not $sw) {
        return $false
    }

    try {
        Remove-VMSwitch -Name $sw.Name -Force -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

Export-ModuleMember -Function *
