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
        throw
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

        throw "VM is in an invalid state for starting: $vmState"
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }

        Write-Host "Start-HvoVm error: $($_ | Out-String)" -ForegroundColor Red
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
                # Vérifier la présence et l'activation du service d'intégration d'arrêt
                $shutdownService = Get-VMIntegrationService -VMName $Name -Name "Shutdown" -ErrorAction SilentlyContinue
                
                if (-not $shutdownService) {
                    throw "SHUTDOWN_SERVICE_NOT_AVAILABLE: Le service d'intégration d'arrêt (Shutdown) n'est pas disponible pour la VM '$Name'. Utilisez le paramètre 'force' pour un arrêt forcé."
                }
                
                if (-not $shutdownService.Enabled) {
                    throw "SHUTDOWN_SERVICE_NOT_ENABLED: Le service d'intégration d'arrêt (Shutdown) n'est pas activé pour la VM '$Name'. Utilisez le paramètre 'force' pour un arrêt forcé."
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

        Write-Host "Stop-HvoVm error: $($_ | Out-String)" -ForegroundColor Red
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
            # Idempotence : si la VM est arrêtée, la démarrer
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

        Write-Host "Restart-HvoVm error: $($_ | Out-String)" -ForegroundColor Red
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

        Write-Host "Suspend-HvoVm error: $($_ | Out-String)" -ForegroundColor Red
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

        throw "VM is in an invalid state for resuming: $vmState"
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'not found|does not exist|Cannot find') {
            return $null
        }

        Write-Host "Resume-HvoVm error: $($_ | Out-String)" -ForegroundColor Red
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

        Write-Host "Remove-HvoVm error: $($_ | Out-String)" -ForegroundColor Red
        throw
    }
}

Export-ModuleMember -Function *
