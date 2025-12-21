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

     # If VM already exists → idempotent result
    $existing = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        return @{
            Exists = $true
            Name   = $existing.Name
        }
    }

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

        Set-VMProcessor -VMName $Name -Count $Vcpu -ErrorAction Stop

        if ($IsoPath) {
            if (-not (Test-Path $IsoPath)) {
                throw "ISO path '$IsoPath' not found"
            }

            Add-VMDvdDrive -VMName $Name -Path $IsoPath -ErrorAction Stop | Out-Null
        }

         return @{
        Exists = $false
        Name   = $vm.Name
        }
    }
    catch {
        throw $_
 }
}

function Set-HvoVm {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [int] $MemoryMB,
        [int] $Vcpu,
        [string] $SwitchName,
        [string] $IsoPath
    )

    try {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
        if (-not $vm) {
            return @{ Updated = $false; Error = "VM not found" }
        }

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
                Set-VMMemory -VMName $Name -StartupBytes ($MemoryMB * 1MB) -ErrorAction Stop
                $changed = $true
            }
        }

        #
        # vCPU — update only if different
        #
        if ($PSBoundParameters.ContainsKey("Vcpu")) {
            if ($vm.ProcessorCount -ne $Vcpu) {
                Set-VMProcessor -VMName $Name -Count $Vcpu -ErrorAction Stop
                $changed = $true
            }
        }

        #
        # SWITCH — update only if different
        #
        if ($PSBoundParameters.ContainsKey("SwitchName")) {
            $currentNics = Get-VMNetworkAdapter -VMName $Name -ErrorAction SilentlyContinue
            # Get-VMNetworkAdapter returns an array, take the first adapter
            $currentSwitch = $null
            if ($currentNics) {
                $firstNic = if ($currentNics -is [Array]) { $currentNics[0] } else { $currentNics }
                if ($firstNic) {
                    $currentSwitch = $firstNic.SwitchName
                }
            }

            if ($currentSwitch -ne $SwitchName) {
                Get-VMNetworkAdapter -VMName $Name |
                    Remove-VMNetworkAdapter -Confirm:$false -ErrorAction Stop

                Add-VMNetworkAdapter -VMName $Name -SwitchName $SwitchName -ErrorAction Stop
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

            $currentIso = (Get-VMDvdDrive -VMName $Name -ErrorAction SilentlyContinue)?.Path

            if ($currentIso -ne $IsoPath) {
                Get-VMDvdDrive -VMName $Name | Remove-VMDvdDrive -ErrorAction Stop
                Add-VMDvdDrive -VMName $Name -Path $IsoPath -ErrorAction Stop
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
                Name      = $Name
            }
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



function Get-HvoVm {
    param([string]$Name)

    $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
    if (-not $vm) {
        return $null }

    return [PSCustomObject]@{
        Name            = $vm.Name
        State           = $vm.State.ToString()
        CPUUsage        = $vm.CPUUsage
        MemoryAssigned  = $vm.MemoryAssigned
        Uptime          = $vm.Uptime.ToString()
    }
}

function Get-HvoVms {
    $vms = Get-VM -ErrorAction SilentlyContinue
    return $vms | ForEach-Object {
        [PSCustomObject]@{
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
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmState = $vm.State.ToString()

        if ($vmState -eq "Running") {
            return @{
                Started = $false
                AlreadyRunning = $true
                Name = $vm.Name
            }
        }

        if ($vmState -eq "Off") {
            Start-VM -Name $Name -ErrorAction Stop
            return @{
                Started = $true
                AlreadyRunning = $false
                Name = $vm.Name
            }
        }

        if ($vmState -eq "Paused") {
            Resume-VM -Name $Name -ErrorAction Stop
            return @{
                Started = $true
                Resumed = $true
                Name = $vm.Name
            }
        }

        if ($vmState -eq "Saved") {
            Start-VM -Name $Name -ErrorAction Stop
            return @{
                Started = $true
                Resumed = $false
                Name = $vm.Name
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
        [Parameter(Mandatory)] [string] $Name,
        [switch] $Force
    )
    try {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmState = $vm.State.ToString()

        if ($vmState -eq "Off") {
            return @{
                Stopped = $false
                AlreadyStopped = $true
                Name = $vm.Name
            }
        }

        if ($vmState -eq "Running") {
            if ($Force) {
                Stop-VM -Name $Name -Force -ErrorAction Stop
            }
            else {
                # Check the presence and activation of the shutdown integration service
                $shutdownService = Get-VMIntegrationService -VMName $Name -Name "Shutdown" -ErrorAction SilentlyContinue

                if (-not $shutdownService) {
                    throw "SHUTDOWN_SERVICE_NOT_AVAILABLE: The shutdown integration service is not available for VM '$Name'. Use the 'force' parameter for a forced shutdown."
                }

                if (-not $shutdownService.Enabled) {
                    throw "SHUTDOWN_SERVICE_NOT_ENABLED: The shutdown integration service is not enabled for VM '$Name'. Use the 'force' parameter for a forced shutdown."
                }

                Stop-VM -Name $Name -ErrorAction Stop
            }
            return @{
                Stopped = $true
                AlreadyStopped = $false
                Name = $vm.Name
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
        [Parameter(Mandatory)] [string] $Name,
        [switch] $Force
    )
    try {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmState = $vm.State.ToString()

        if ($vmState -eq "Off") {
            # Idempotence: if the VM is stopped, start it
            Start-VM -Name $Name -ErrorAction Stop
            return @{
                Restarted = $true
                Name = $vm.Name
            }
        }

        if ($vmState -eq "Running") {
            if ($Force) {
                Restart-VM -Name $Name -Force -ErrorAction Stop
            }
            else {
                # Check the presence and activation of the shutdown integration service
                $shutdownService = Get-VMIntegrationService -VMName $Name -Name "Shutdown" -ErrorAction SilentlyContinue

                if (-not $shutdownService) {
                    throw "SHUTDOWN_SERVICE_NOT_AVAILABLE: The shutdown integration service is not available for VM '$Name'. Use the 'force' parameter for a forced restart."
                }

                if (-not $shutdownService.Enabled) {
                    throw "SHUTDOWN_SERVICE_NOT_ENABLED: The shutdown integration service is not enabled for VM '$Name'. Use the 'force' parameter for a forced restart."
                }

                Restart-VM -Name $Name -ErrorAction Stop
            }
            return @{
                Restarted = $true
                Name = $vm.Name
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
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmState = $vm.State.ToString()

        if ($vmState -eq "Paused") {
            return @{
                Suspended = $false
                AlreadySuspended = $true
                Name = $vm.Name
            }
        }

        if ($vmState -eq "Running") {
            Suspend-VM -Name $Name -ErrorAction Stop
            return @{
                Suspended = $true
                AlreadySuspended = $false
                Name = $vm.Name
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
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

        if (-not $vm) {
            return $null
        }

        $vmState = $vm.State.ToString()

        if ($vmState -eq "Running") {
            return @{
                Resumed = $false
                AlreadyRunning = $true
                Name = $vm.Name
            }
        }

        if ($vmState -eq "Paused") {
            Resume-VM -Name $Name -ErrorAction Stop
            return @{
                Resumed = $true
                AlreadyRunning = $false
                Name = $vm.Name
            }
        }

        if ($vmState -eq "Off") {
            throw "Cannot resume VM '$Name' because it is stopped (Off). Resume is only applicable to paused VMs. To start a stopped VM, use Start-VM."
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
        [Parameter(Mandatory)] [string] $Name,
        [bool] $RemoveDisks
    )
    try {

        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

        if (-not $vm) { return $false }


        if ($vm.State -in @("Running", "Paused")) {
            Stop-VM -Name $Name -Force -ErrorAction Stop
        }

        $snaps = Get-VMSnapshot -VMName $Name -ErrorAction SilentlyContinue
        if ($snaps) {
            Remove-VMSnapshot -VMName $Name -ErrorAction Stop
        }

        $dvdDrives = Get-VMDvdDrive -VMName $Name -ErrorAction SilentlyContinue
        foreach ($dvd in $dvdDrives) {
            Remove-VMDvdDrive -VMName $Name `
                -ControllerNumber $dvd.ControllerNumber `
                -ControllerLocation $dvd.ControllerLocation -ErrorAction Stop
        }

        $diskPaths = @()
        if ($RemoveDisks) {
            $diskPaths = (Get-VMHardDiskDrive -VMName $Name -ErrorAction SilentlyContinue).Path
        }

        Remove-VM -Name $Name -Force -ErrorAction Stop

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

Export-ModuleMember -Function *
