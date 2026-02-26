function New-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [int]    $MemoryMB,
        [Parameter(Mandatory)] [int]    $Vcpu,
        [Parameter(Mandatory)] [string] $DiskPath,
        [Parameter(Mandatory)] [int]    $DiskGB,
        [Parameter(Mandatory)] [string] $SwitchName,
        [string] $IsoPath
    )
   try{
    if (-not (Test-Path $DiskPath)) {
            New-Item -ItemType Directory -Path $DiskPath -Force | Out-Null
        }

        $vhdPath = Join-Path $DiskPath "$Name.vhdx"

        if (-not (Test-Path $vhdPath)) {
            New-VHD -Path $vhdPath -SizeBytes ($DiskGB * 1GB) -Dynamic -ErrorAction Stop | Out-Null
        }

        $vm = New-VM -Name $Name `
            -MemoryStartupBytes ($MemoryMB * 1MB) `
            -Generation 2 `
            -VHDPath $vhdPath `
            -SwitchName $SwitchName `
            -ErrorAction Stop

        Set-VMProcessor -VMName $vm.Name -Count $Vcpu -ErrorAction Stop

        if ($IsoPath) {
            if (-not (Test-Path $IsoPath)) {
                throw "ISO path '$IsoPath' not found"
            }

            Add-VMDvdDrive -VMName $vm.Name -Path $IsoPath -ErrorAction Stop | Out-Null
        }

        $idValue = if ($vm.Id) { $vm.Id.ToString() } else { $null }
        return @{
            Name = $vm.Name
            Id   = $idValue
        }
    }
    catch {
        throw $_
 }
}
<#
function Set-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [int] $MemoryMB,
        [int] $Vcpu,
        [string] $SwitchName,
        [string] $IsoPath
    )

    try {
        try { $guid = [guid]$Id } catch { return @{ Updated = $false; Error = "VM not found" } }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue
        if (-not $vm) {
            return @{ Updated = $false; Error = "VM not found" }
        }

        $vmName = $vm.Name

        if ($vm.State -ne "Off") {
            return @{
                Updated = $false
                Error   = "VM must be Off to update"
                State   = $vm.State.ToString()
            }
        }

        $changed = $false

        #
        # MEMORY — update only if different
        #
        if ($PSBoundParameters.ContainsKey("MemoryMB")) {
            $currentMB = [math]::Round($vm.MemoryStartup / 1MB)
            if ($currentMB -ne $MemoryMB) {
                Set-VMMemory -VMName $vmName -StartupBytes ($MemoryMB * 1MB) -ErrorAction Stop
                $changed = $true
            }
        }

        #
        # vCPU — update only if different
        #
        if ($PSBoundParameters.ContainsKey("Vcpu")) {
            if ($vm.ProcessorCount -ne $Vcpu) {
                Set-VMProcessor -VMName $vmName -Count $Vcpu -ErrorAction Stop
                $changed = $true
            }
        }

        #
        # SWITCH — update only if different
        #
        if ($PSBoundParameters.ContainsKey("SwitchName")) {
            $currentNics = Get-VMNetworkAdapter -VMName $vmName -ErrorAction SilentlyContinue
            # Get-VMNetworkAdapter returns an array, take the first adapter
            $currentSwitch = $null
            if ($currentNics) {
                $firstNic = if ($currentNics -is [Array]) { $currentNics[0] } else { $currentNics }
                if ($firstNic) {
                    $currentSwitch = $firstNic.SwitchName
                }
            }

            if ($currentSwitch -ne $SwitchName) {
                Get-VMNetworkAdapter -VMName $vmName |
                    Remove-VMNetworkAdapter -Confirm:$false -ErrorAction Stop

                Add-VMNetworkAdapter -VMName $vmName -SwitchName $SwitchName -ErrorAction Stop
                $changed = $true
            }
        }

        #
        # ISO — update only if different
        #
        if ($PSBoundParameters.ContainsKey("IsoPath")) {

            if (-not (Test-Path $IsoPath)) {
                return @{ Updated = $false; Error = "ISO file not found"; Path = $IsoPath }
            }

            $currentIso = (Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue)?.Path

            if ($currentIso -ne $IsoPath) {
                Get-VMDvdDrive -VMName $vmName | Remove-VMDvdDrive -ErrorAction Stop
                Add-VMDvdDrive -VMName $vmName -Path $IsoPath -ErrorAction Stop
                $changed = $true
            }
        }

        #
        # No changes? → return idempotent response
        #
        if (-not $changed) {
            return @{
                Updated   = $false
                Unchanged = $true
                Name      = $vmName
                Id        = $vm.Id.ToString()
            }
        }

        return @{
            Updated = $true
            Name    = $vmName
            Id      = $vm.Id.ToString()
        }
    }
    catch {
        throw $_
    }
}

#>

# WIP: GUID-based refactor
# Resource identification is migrating from Name to Id (GUID).
# This section is part of the canonical Id-based API transition.



function Set-HvoVm {
    param(
        [Parameter(Mandatory)] [Guid] $Id,

        [int] $MemoryMB,
        [int] $Vcpu,

        # Declarative networking: optional on update
        [array] $NetworkAdapters,

        [string] $IsoPath
    )

    try {
        $vm = Get-VM -Id $Id -ErrorAction SilentlyContinue
        if (-not $vm) {
            return @{ Updated = $false; Error = "VM not found"; Id = "$Id" }
        }

        if ($vm.State -ne "Off") {
            return @{
                Updated = $false
                Error   = "VM must be Off to update"
                State   = $vm.State.ToString()
                Id      = "$Id"
            }
        }

        $changed = $false

        #
        # MEMORY — update only if different
        #
        if ($PSBoundParameters.ContainsKey("MemoryMB")) {
            $currentMB = [math]::Round($vm.MemoryStartup / 1MB)
            if ($currentMB -ne $MemoryMB) {
                Set-VMMemory -VMName $vm.Name -StartupBytes ($MemoryMB * 1MB) -ErrorAction Stop
                $changed = $true
            }
        }

        #
        # vCPU — update only if different
        #
        if ($PSBoundParameters.ContainsKey("Vcpu")) {
            if ($vm.ProcessorCount -ne $Vcpu) {
                Set-VMProcessor -VMName $vm.Name -Count $Vcpu -ErrorAction Stop
                $changed = $true
            }
        }

        #
        # NETWORK ADAPTERS — reconcile if provided (authoritative)
        #
        if ($PSBoundParameters.ContainsKey("NetworkAdapters")) {

            # Normalize/validate desired adapters
            $desired = @{}
            foreach ($a in $NetworkAdapters) {
                if (-not $a.name -or -not $a.switchName) {
                    throw "Each networkAdapters item must contain 'name' and 'switchName'"
                }

                $n = [string]$a.name
                $s = [string]$a.switchName

                if ($desired.ContainsKey($n)) {
                    throw "Duplicate network adapter name in request: '$n'"
                }

                $desired[$n] = $s
            }

            # Current adapters indexed by Name
            $currentList = @(Get-VMNetworkAdapter -VMName $vm.Name -ErrorAction Stop)
            $current = @{}
            foreach ($c in $currentList) {
                $current[$c.Name] = $c
            }

            # Remove adapters not desired
            foreach ($name in @($current.Keys)) {
                if (-not $desired.ContainsKey($name)) {
                    Remove-VMNetworkAdapter -VMNetworkAdapter $current[$name] -Confirm:$false -ErrorAction Stop
                    $changed = $true
                }
            }

            # Add or reconnect desired adapters
            foreach ($name in $desired.Keys) {
                $targetSwitch = $desired[$name]

                if (-not $current.ContainsKey($name)) {
                    Add-VMNetworkAdapter -VMName $vm.Name -Name $name -SwitchName $targetSwitch -ErrorAction Stop
                    $changed = $true
                    continue
                }

                $cur = $current[$name]
                if ($cur.SwitchName -ne $targetSwitch) {
                    Connect-VMNetworkAdapter -VMNetworkAdapter $cur -SwitchName $targetSwitch -ErrorAction Stop
                    $changed = $true
                }
            }
        }

        #
        # ISO — update only if different
        #
        if ($PSBoundParameters.ContainsKey("IsoPath")) {

            if (-not (Test-Path $IsoPath)) {
                return @{ Updated = $false; Error = "ISO file not found"; Path = $IsoPath; Id = "$Id" }
            }

            $currentIso = (Get-VMDvdDrive -VMName $vm.Name -ErrorAction SilentlyContinue)?.Path

            if ($currentIso -ne $IsoPath) {
                Get-VMDvdDrive -VMName $vm.Name | Remove-VMDvdDrive -ErrorAction Stop
                Add-VMDvdDrive -VMName $vm.Name -Path $IsoPath -ErrorAction Stop
                $changed = $true
            }
        }

        if (-not $changed) {
            return @{
                Updated   = $false
                Unchanged = $true
                Id        = "$Id"
                Name      = $vm.Name
            }
        }

        return @{
            Updated = $true
            Id      = "$Id"
            Name    = $vm.Name
        }
    }
    catch {
        throw
    }
}





function Get-HvoVm {
    param(
        [Parameter(Mandatory)]
        [string] $Id
    )

    try { $guid = [guid]$Id } catch { return $null }
    $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue
    if (-not $vm) {
        return $null
    }

    $idValue = if ($vm.Id) { $vm.Id.ToString() } else { $null }
    return [PSCustomObject]@{
        Id              = $idValue
        Name            = $vm.Name
        State           = $vm.State.ToString()
        CPUUsage        = $vm.CPUUsage
        MemoryAssigned  = $vm.MemoryAssigned
        Uptime          = $vm.Uptime.ToString()
    }
}

# WIP: GUID-based refactor
# Resource identification is migrating from Name to Id (GUID).
# This section is part of the canonical Id-based API transition.


function Get-HvoVmByName {
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    $vms = @(Get-VM -Name $Name -ErrorAction SilentlyContinue)

    if (-not $vms -or $vms.Count -eq 0) {
        return @()
    }

    return $vms | ForEach-Object {
        [PSCustomObject]@{
            Id             = $_.Id.Guid
            Name           = $_.Name
            State          = $_.State.ToString()
            CPUUsage       = $_.CPUUsage
            MemoryAssigned = $_.MemoryAssigned
            Uptime         = $_.Uptime.ToString()
        }
    }
}



function Get-HvoVms {
    $vms = Get-VM -ErrorAction SilentlyContinue
    return $vms | ForEach-Object {
        $idValue = if ($_.Id) { $_.Id.ToString() } else { $null }
        [PSCustomObject]@{
            Id              = $idValue
            Name            = $_.Name
            State           = $_.State.ToString()
            CPUUsage        = $_.CPUUsage
            MemoryAssigned  = $_.MemoryAssigned
            Uptime          = $_.Uptime.ToString()
        }
    }
}

function Get-HvoVmByName {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $vms = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name }
    if (-not $vms) {
        return @()
    }
    if ($vms -isnot [Array]) {
        $vms = @($vms)
    }
    return $vms | ForEach-Object {
        $idValue = if ($_.Id) { $_.Id.ToString() } else { $null }
        [PSCustomObject]@{
            Id              = $idValue
            Name            = $_.Name
            State           = $_.State.ToString()
            CPUUsage        = $_.CPUUsage
            MemoryAssigned  = $_.MemoryAssigned
            Uptime          = $_.Uptime.ToString()
        }
    }
}

function Start-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Id
    )
    try {
        try { $guid = [guid]$Id } catch { return $null }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmName = $vm.Name
        $vmState = $vm.State.ToString()

        if ($vmState -eq "Running") {
            return @{
                Started = $false
                AlreadyRunning = $true
                Name = $vmName
            }
        }

        if ($vmState -eq "Off") {
            Start-VM -Name $vmName -ErrorAction Stop
            return @{
                Started = $true
                AlreadyRunning = $false
                Name = $vmName
            }
        }

        if ($vmState -eq "Paused") {
            Resume-VM -Name $vmName -ErrorAction Stop
            return @{
                Started = $true
                Resumed = $true
                Name = $vmName
            }
        }

        if ($vmState -eq "Saved") {
            Start-VM -Name $vmName -ErrorAction Stop
            return @{
                Started = $true
                Resumed = $false
                Name = $vmName
            }
        }

        throw "VM is in an invalid state for starting: $vmState. If the VM is in a transitional state (e.g., Starting, Stopping), please wait. For other states, use the appropriate endpoint (e.g., Resume for Paused)."
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }

        # Propagate the exception without display - the caller will handle the error
        throw
    }
}

function Stop-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [switch] $Force
    )
    try {
        try { $guid = [guid]$Id } catch { return $null }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmName = $vm.Name
        $vmState = $vm.State.ToString()

        if ($vmState -eq "Off") {
            return @{
                Stopped = $false
                AlreadyStopped = $true
                Name = $vmName
            }
        }

        if ($vmState -eq "Running") {
            if ($Force) {
                Stop-VM -Name $vmName -Force -ErrorAction Stop
            }
            else {
                # Check the presence and activation of the shutdown integration service
                $shutdownService = Get-VMIntegrationService -VMName $vmName -Name "Shutdown" -ErrorAction SilentlyContinue

                if (-not $shutdownService) {
                    throw "SHUTDOWN_SERVICE_NOT_AVAILABLE: The shutdown integration service is not available for VM '$vmName'. Use the 'force' parameter for a forced shutdown."
                }

                if (-not $shutdownService.Enabled) {
                    throw "SHUTDOWN_SERVICE_NOT_ENABLED: The shutdown integration service is not enabled for VM '$vmName'. Use the 'force' parameter for a forced shutdown."
                }

                Stop-VM -Name $vmName -ErrorAction Stop
            }
            return @{
                Stopped = $true
                AlreadyStopped = $false
                Name = $vmName
            }
        }

        throw "VM is in an invalid state for stopping: $vmState"
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }

        # Propagate the exception without display - the caller will handle the error
        throw
    }
}

function Restart-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [switch] $Force
    )
    try {
        try { $guid = [guid]$Id } catch { return $null }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmName = $vm.Name
        $vmState = $vm.State.ToString()

        if ($vmState -eq "Off") {
            # Idempotence: if the VM is stopped, start it
            Start-VM -Name $vmName -ErrorAction Stop
            return @{
                Restarted = $true
                Name = $vmName
            }
        }

        if ($vmState -eq "Running") {
            if ($Force) {
                Restart-VM -Name $vmName -Force -ErrorAction Stop
            }
            else {
                # Check the presence and activation of the shutdown integration service
                $shutdownService = Get-VMIntegrationService -VMName $vmName -Name "Shutdown" -ErrorAction SilentlyContinue

                if (-not $shutdownService) {
                    throw "SHUTDOWN_SERVICE_NOT_AVAILABLE: The shutdown integration service is not available for VM '$vmName'. Use the 'force' parameter for a forced restart."
                }

                if (-not $shutdownService.Enabled) {
                    throw "SHUTDOWN_SERVICE_NOT_ENABLED: The shutdown integration service is not enabled for VM '$vmName'. Use the 'force' parameter for a forced restart."
                }

                Restart-VM -Name $vmName -ErrorAction Stop
            }
            return @{
                Restarted = $true
                Name = $vmName
            }
        }

        throw "VM is in an invalid state for restarting: $vmState"
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }

        # Propagate the exception without display - the caller will handle the error
        throw
    }
}

function Suspend-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Id
    )
    try {
        try { $guid = [guid]$Id } catch { return $null }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmName = $vm.Name
        $vmState = $vm.State.ToString()

        if ($vmState -eq "Paused") {
            return @{
                Suspended = $false
                AlreadySuspended = $true
                Name = $vmName
            }
        }

        if ($vmState -eq "Running") {
            Suspend-VM -Name $vmName -ErrorAction Stop
            return @{
                Suspended = $true
                AlreadySuspended = $false
                Name = $vmName
            }
        }

        throw "VM is in an invalid state for suspending: $vmState"
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }

        # Propagate the exception without display - the caller will handle the error
        throw
    }
}

function Resume-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Id
    )
    try {
        try { $guid = [guid]$Id } catch { return $null }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmName = $vm.Name
        $vmState = $vm.State.ToString()

        if ($vmState -eq "Running") {
            return @{
                Resumed = $false
                AlreadyRunning = $true
                Name = $vmName
            }
        }

        if ($vmState -eq "Paused") {
            Resume-VM -Name $vmName -ErrorAction Stop
            return @{
                Resumed = $true
                AlreadyRunning = $false
                Name = $vmName
            }
        }

        if ($vmState -eq "Off") {
            throw "Cannot resume VM '$vmName' because it is stopped (Off). Resume is only applicable to paused VMs. To start a stopped VM, use Start-VM."
        }
        throw "VM is in an invalid state for resuming: $vmState"
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }

        # Propagate the exception without display - the caller will handle the error
        throw
    }
}


function Remove-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [bool] $RemoveDisks
    )
    try {
        try { $guid = [guid]$Id } catch { return $false }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue

        if (-not $vm) { return $false }

        $vmName = $vm.Name

        if ($vm.State -in @("Running", "Paused")) {
            Stop-VM -Name $vmName -Force -ErrorAction Stop
        }

        $snaps = Get-VMSnapshot -VMName $vmName -ErrorAction SilentlyContinue
        if ($snaps) {
            Remove-VMSnapshot -VMName $vmName -ErrorAction Stop
        }

        $dvdDrives = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue
        foreach ($dvd in $dvdDrives) {
            Remove-VMDvdDrive -VMName $vmName `
                -ControllerNumber $dvd.ControllerNumber `
                -ControllerLocation $dvd.ControllerLocation -ErrorAction Stop
        }

        $diskPaths = @()
        if ($RemoveDisks) {
            $diskPaths = (Get-VMHardDiskDrive -VMName $vmName -ErrorAction SilentlyContinue).Path
        }

        Remove-VM -Name $vmName -Force -ErrorAction Stop

        foreach ($d in $diskPaths) {
            if (Test-Path $d) {
                Remove-Item $d -Force -ErrorAction Stop
            }
        }

        return $true
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $false
        }

        # Propagate the exception without display - the caller will handle the error
        throw
    }
}

function Get-HvoVmNetworkAdapters {
    param(
        [Parameter(Mandatory)] [string] $Id
    )

    try {
        try { $guid = [guid]$Id } catch { return $null }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue
        if (-not $vm) {
            return $null
        }

        $adapters = Get-VMNetworkAdapter -VM $vm -ErrorAction SilentlyContinue
        if (-not $adapters) {
            return @()
        }

        # Handle both single adapter and array of adapters
        if ($adapters -isnot [Array]) {
            $adapters = @($adapters)
        }

        return $adapters | ForEach-Object {
            $type = if ($_.IsLegacy) { "Legacy" } else { "Synthetic" }
            # Expose stable adapter id: .Id if present (Hyper-V), else .InstanceId
            $adapterId = if ($_.Id) { $_.Id.ToString() } elseif ($_.InstanceId) { $_.InstanceId.ToString() } else { $null }

            [PSCustomObject]@{
                Id         = $adapterId
                Name       = $_.Name
                SwitchName = $_.SwitchName
                Type       = $type
                MacAddress = $_.MacAddress
                Status     = if ($null -ne $_.Status) { $_.Status.ToString() } else { $null }
            }
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }

        # Propagate the exception without display - the caller will handle the error
        throw
    }
}

function Add-HvoVmNetworkAdapter {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $SwitchName
    )

    try {
        try { $guid = [guid]$Id } catch { return $null }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue
        if (-not $vm) {
            return $null
        }

        $newAdapter = Add-VMNetworkAdapter -VM $vm -SwitchName $SwitchName -ErrorAction Stop
        if (-not $newAdapter) {
            return $null
        }
        $adapterId = if ($newAdapter.Id) { $newAdapter.Id.ToString() } elseif ($newAdapter.InstanceId) { $newAdapter.InstanceId.ToString() } else { $null }
        return @{
            Id   = $adapterId
            Name = $newAdapter.Name
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }
        throw
    }
}

function Remove-HvoVmNetworkAdapter {
    param(
        [Parameter(Mandatory)] [string] $VMId,
        [Parameter(Mandatory)] [string] $AdapterId
    )

    try {
        try { $guid = [guid]$VMId } catch { return $false }
        $vm = Get-VM -Id $guid -ErrorAction SilentlyContinue
        if (-not $vm) {
            return $false
        }

        $adapters = Get-VMNetworkAdapter -VM $vm -ErrorAction SilentlyContinue
        if (-not $adapters) {
            return $false
        }
        if ($adapters -isnot [Array]) {
            $adapters = @($adapters)
        }

        $adapter = $adapters | Where-Object {
            $aid = if ($_.Id) { $_.Id.ToString() } elseif ($_.InstanceId) { $_.InstanceId.ToString() } else { $null }
            $aid -eq $AdapterId
        } | Select-Object -First 1

        if (-not $adapter) {
            return $false
        }

        Remove-VMNetworkAdapter -VMNetworkAdapter $adapter -ErrorAction Stop
        return $true
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $false
        }
        throw
    }
}

Export-ModuleMember -Function *
