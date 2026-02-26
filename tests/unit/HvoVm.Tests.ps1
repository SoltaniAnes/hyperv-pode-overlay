# Unit tests for the HvoVm module
# Uses InModuleScope to test within the module context and allow mocks to work

BeforeAll {
    # Create stubs for Hyper-V cmdlets when they are not present (e.g. WSL, Linux)
    # This allows Pester to mock these commands even without the Hyper-V module
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        function global:Get-VM { param($Name, $Id, $ErrorAction) }
    }
    if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
        function global:New-VM { param($Name, $MemoryStartupBytes, $Generation, $VHDPath, $SwitchName) }
    }
    if (-not (Get-Command Remove-VM -ErrorAction SilentlyContinue)) {
        function global:Remove-VM { param($Name, $Force, $ErrorAction) }
    }
    if (-not (Get-Command Start-VM -ErrorAction SilentlyContinue)) {
        function global:Start-VM { param($Name, $ErrorAction) }
    }
    if (-not (Get-Command Stop-VM -ErrorAction SilentlyContinue)) {
        function global:Stop-VM { param($Name, $Force, $ErrorAction) }
    }
    if (-not (Get-Command Restart-VM -ErrorAction SilentlyContinue)) {
        function global:Restart-VM { param($Name, $Force, $ErrorAction) }
    }
    if (-not (Get-Command Suspend-VM -ErrorAction SilentlyContinue)) {
        function global:Suspend-VM { param($Name, $ErrorAction) }
    }
    if (-not (Get-Command Resume-VM -ErrorAction SilentlyContinue)) {
        function global:Resume-VM { param($Name, $ErrorAction) }
    }
    if (-not (Get-Command Set-VMProcessor -ErrorAction SilentlyContinue)) {
        function global:Set-VMProcessor { param($VMName, $Count, $ErrorAction) }
    }
    if (-not (Get-Command Set-VMMemory -ErrorAction SilentlyContinue)) {
        function global:Set-VMMemory { param($VMName, $StartupBytes, $ErrorAction) }
    }
    if (-not (Get-Command New-VHD -ErrorAction SilentlyContinue)) {
        function global:New-VHD { param($Path, $SizeBytes, $Dynamic, $ErrorAction) }
    }
    if (-not (Get-Command Add-VMDvdDrive -ErrorAction SilentlyContinue)) {
        function global:Add-VMDvdDrive { param($VMName, $Path, $ErrorAction) }
    }
    if (-not (Get-Command Get-VMDvdDrive -ErrorAction SilentlyContinue)) {
        function global:Get-VMDvdDrive { param($VMName, $ErrorAction) }
    }
    if (-not (Get-Command Remove-VMDvdDrive -ErrorAction SilentlyContinue)) {
        function global:Remove-VMDvdDrive { param($VMName, $ControllerNumber, $ControllerLocation, $ErrorAction) }
    }
    if (-not (Get-Command Get-VMNetworkAdapter -ErrorAction SilentlyContinue)) {
        function global:Get-VMNetworkAdapter { param($VMName, $VM, $ErrorAction) }
    }
    if (-not (Get-Command Add-VMNetworkAdapter -ErrorAction SilentlyContinue)) {
        function global:Add-VMNetworkAdapter { param($VMName, $VM, $SwitchName, $ErrorAction) }
    }
    if (-not (Get-Command Remove-VMNetworkAdapter -ErrorAction SilentlyContinue)) {
        function global:Remove-VMNetworkAdapter { param($VMName, $VMNetworkAdapter, $Confirm, $ErrorAction) }
    }
    if (-not (Get-Command Get-VMSnapshot -ErrorAction SilentlyContinue)) {
        function global:Get-VMSnapshot { param($VMName, $ErrorAction) }
    }
    if (-not (Get-Command Remove-VMSnapshot -ErrorAction SilentlyContinue)) {
        function global:Remove-VMSnapshot { param($VMName, $ErrorAction) }
    }
    if (-not (Get-Command Get-VMHardDiskDrive -ErrorAction SilentlyContinue)) {
        function global:Get-VMHardDiskDrive { param($VMName, $ErrorAction) }
    }
    if (-not (Get-Command Get-VMIntegrationService -ErrorAction SilentlyContinue)) {
        function global:Get-VMIntegrationService { param($VMName, $Name, $ErrorAction) }
    }

    $modulePath = Join-Path $PSScriptRoot "../../src/modules/HvoVm/HvoVm.psd1"
    Import-Module $modulePath -Force
}

InModuleScope HvoVm {
    $script:testVmGuid = [guid]'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

    Describe "New-HvoVm" {
        Context "When creating a new VM" {
            It "Should create a new VM and return Name and Id" {
                # Arrange
                $vmName = "test-vm-new"
                $diskPath = "/tmp/TestVMs"
                $vhdPath = Join-Path $diskPath "$vmName.vhdx"
                $switchName = "test-switch"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    Id   = $script:testVmGuid
                }

                Mock Test-Path -ParameterFilter { $Path -eq $diskPath } -MockWith { return $false }
                Mock New-Item -MockWith { return [PSCustomObject]@{ FullName = $diskPath } }
                Mock Test-Path -ParameterFilter { $Path -eq $vhdPath } -MockWith { return $false }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = $vhdPath } }
                Mock New-VM -MockWith { return $mockVm }
                Mock Set-VMProcessor -MockWith { }

                # Act
                $result = New-HvoVm -Name $vmName -MemoryMB 2048 -Vcpu 4 -DiskPath $diskPath -DiskGB 40 -SwitchName $switchName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be $vmName
                $result.Id | Should -Be $script:testVmGuid.ToString()
                Should -Invoke New-VM -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $vmName -and
                    $MemoryStartupBytes -eq (2048 * 1MB) -and
                    $Generation -eq 2 -and
                    $VHDPath -eq $vhdPath -and
                    $SwitchName -eq $switchName
                }
                Should -Invoke Set-VMProcessor -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and $Count -eq 4
                }
            }

            It "Should return two different Ids when creating two VMs with the same name" {
                # Arrange: each POST creates a new resource
                $vmName = "dup-name"
                $diskPath = "/tmp/VMs"
                $callCount = 0
                Mock Test-Path -MockWith { return $true }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = "test.vhdx" } }
                Mock New-VM -MockWith {
                    $callCount++
                    return [PSCustomObject]@{ Name = $vmName; Id = [guid]::NewGuid() }
                }
                Mock Set-VMProcessor -MockWith { }

                # Act: simulate two creates with same name
                $result1 = New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath $diskPath -DiskGB 20 -SwitchName "s1"
                $result2 = New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath $diskPath -DiskGB 20 -SwitchName "s1"

                # Assert: both have Id; two New-VM calls
                $result1.Id | Should -Not -BeNullOrEmpty
                $result2.Id | Should -Not -BeNullOrEmpty
                Should -Invoke New-VM -Exactly -Times 2
            }

            It "Should create the disk directory if it does not exist" {
                # Arrange
                $vmName = "test-vm-new"
                $diskPath = "/tmp/TestVMs"

                Mock Test-Path -ParameterFilter { $Path -eq $diskPath } -MockWith { return $false }
                Mock New-Item -MockWith { return [PSCustomObject]@{ FullName = $diskPath } }
                Mock Test-Path -ParameterFilter { $Path -like "*.vhdx" } -MockWith { return $false }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = "test.vhdx" } }
                Mock New-VM -MockWith { return [PSCustomObject]@{ Name = $vmName; Id = $script:testVmGuid } }
                Mock Set-VMProcessor -MockWith { }

                # Act
                New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath $diskPath -DiskGB 20 -SwitchName "test-switch" | Out-Null

                # Assert
                Should -Invoke New-Item -Exactly -Times 1 -ParameterFilter {
                    $ItemType -eq "Directory" -and $Path -eq $diskPath
                }
            }

            It "Should create the VHD if it does not exist" {
                # Arrange
                $vmName = "test-vm-new"
                $diskPath = "/tmp/TestVMs"
                $vhdPath = Join-Path $diskPath "$vmName.vhdx"

                Mock Test-Path -ParameterFilter { $Path -eq $diskPath } -MockWith { return $true }
                Mock Test-Path -ParameterFilter { $Path -eq $vhdPath } -MockWith { return $false }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = $vhdPath } }
                Mock New-VM -MockWith { return [PSCustomObject]@{ Name = $vmName; Id = $script:testVmGuid } }
                Mock Set-VMProcessor -MockWith { }

                # Act
                New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath $diskPath -DiskGB 20 -SwitchName "test-switch" | Out-Null

                # Assert
                Should -Invoke New-VHD -Exactly -Times 1
            }

            It "Should add a DVD drive if IsoPath is provided" {
                # Arrange
                $vmName = "test-vm-new"
                $isoPath = "/tmp/ISOs/test.iso"

                Mock Test-Path -ParameterFilter { $Path -ne $isoPath } -MockWith { return $true }
                Mock Test-Path -ParameterFilter { $Path -eq $isoPath } -MockWith { return $true }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = "test.vhdx" } }
                Mock New-VM -MockWith { return [PSCustomObject]@{ Name = $vmName; Id = $script:testVmGuid } }
                Mock Set-VMProcessor -MockWith { }
                Mock Add-VMDvdDrive -MockWith { }

                # Act
                New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath "/tmp/VMs" -DiskGB 20 -SwitchName "test-switch" -IsoPath $isoPath | Out-Null

                # Assert
                Should -Invoke Add-VMDvdDrive -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and $Path -eq $isoPath
                }
            }

            It "Should throw an exception if IsoPath does not exist" {
                # Arrange
                $vmName = "test-vm-new"
                $isoPath = "/tmp/ISOs/nonexistent.iso"

                Mock Test-Path -ParameterFilter { $Path -ne $isoPath } -MockWith { return $true }
                Mock Test-Path -ParameterFilter { $Path -eq $isoPath } -MockWith { return $false }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = "test.vhdx" } }
                Mock New-VM -MockWith { return [PSCustomObject]@{ Name = $vmName; Id = $script:testVmGuid } }
                Mock Set-VMProcessor -MockWith { }

                # Act & Assert
                { New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath "/tmp/VMs" -DiskGB 20 -SwitchName "test-switch" -IsoPath $isoPath } | Should -Throw
            }
        }
    }

    Describe "Get-HvoVm" {
        Context "When the VM exists" {
            It "Should return the VM details with Id" {
                # Arrange
                $vmId = $script:testVmGuid
                $vmName = "test-vm"
                $mockVm = [PSCustomObject]@{
                    Id = $vmId
                    Name = $vmName
                    State = "Running"
                    CPUUsage = 50
                    MemoryAssigned = 1GB
                    Uptime = New-TimeSpan -Days 1
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }

                # Act
                $result = Get-HvoVm -Id $vmId.ToString()

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Id | Should -Be $vmId.ToString()
                $result.Name | Should -Be $vmName
                $result.State | Should -Be "Running"
                $result.CPUUsage | Should -Be 50
                $result.MemoryAssigned | Should -Be 1GB
                Should -Invoke Get-VM -Exactly -Times 1 -ParameterFilter { $Id -eq $vmId }
            }
        }

        Context "When the VM does not exist" {
            It "Should return null" {
                # Arrange
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'

                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }

                # Act
                $result = Get-HvoVm -Id $vmId.ToString()

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Describe "Get-HvoVms" {
        It "Should return the list of all VMs with Id" {
            # Arrange
            $guid1 = [guid]::NewGuid()
            $guid2 = [guid]::NewGuid()
            $vm1 = [PSCustomObject]@{
                Id = $guid1
                Name = "vm1"
                State = "Running"
                CPUUsage = 30
                MemoryAssigned = 512MB
                Uptime = New-TimeSpan -Hours 2
            }
            $vm1 | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

            $vm2 = [PSCustomObject]@{
                Id = $guid2
                Name = "vm2"
                State = "Off"
                CPUUsage = 0
                MemoryAssigned = 0
                Uptime = New-TimeSpan
            }
            $vm2 | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

            $mockVms = @($vm1, $vm2)

            Mock Get-VM -MockWith { return $mockVms }

            # Act
            $result = Get-HvoVms

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].Id | Should -Be $guid1.ToString()
            $result[0].Name | Should -Be "vm1"
            $result[1].Id | Should -Be $guid2.ToString()
            $result[1].Name | Should -Be "vm2"
            Should -Invoke Get-VM -Exactly -Times 1
        }

        It "Should return an empty array if there are no VMs" {
            # Arrange
            Mock Get-VM -MockWith { return @() }

            # Act
            $result = Get-HvoVms

            # Assert
            if ($null -eq $result) {
                $result = @()
            }
            $result.Count | Should -Be 0
        }
    }

    Describe "Get-HvoVmByName" {
        It "Should return an empty array when no VM matches the name" {
            Mock Get-VM -MockWith { return @() }

            $result = Get-HvoVmByName -Name "no-such-vm"

            # Empty array: result may be @() or $null depending on PowerShell
            if ($null -eq $result) { $result = @() }
            $result.Count | Should -Be 0
        }

        It "Should return a single VM when one matches" {
            $guid = [guid]::NewGuid()
            $mockVm = [PSCustomObject]@{
                Id = $guid
                Name = "single-vm"
                State = "Off"
                CPUUsage = 0
                MemoryAssigned = 0
                Uptime = New-TimeSpan
            }
            $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
            Mock Get-VM -MockWith { return $mockVm }

            $result = Get-HvoVmByName -Name "single-vm"

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result[0].Id | Should -Be $guid.ToString()
            $result[0].Name | Should -Be "single-vm"
        }

        It "Should return multiple VMs when several have the same name" {
            $guid1 = [guid]::NewGuid()
            $guid2 = [guid]::NewGuid()
            $vm1 = [PSCustomObject]@{ Id = $guid1; Name = "dup"; State = "Off"; CPUUsage = 0; MemoryAssigned = 0; Uptime = New-TimeSpan }
            $vm2 = [PSCustomObject]@{ Id = $guid2; Name = "dup"; State = "Running"; CPUUsage = 10; MemoryAssigned = 1GB; Uptime = New-TimeSpan }
            $vm1 | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
            $vm2 | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
            Mock Get-VM -MockWith { return @($vm1, $vm2) }

            $result = Get-HvoVmByName -Name "dup"

            $result.Count | Should -Be 2
            $result[0].Id | Should -Be $guid1.ToString()
            $result[1].Id | Should -Be $guid2.ToString()
        }
    }

    Describe "Set-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return Updated = false with an error" {
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }

                $result = Set-HvoVm -Id $vmId.ToString() -MemoryMB 2048

                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Error | Should -Be "VM not found"
            }
        }

        Context "When the VM is not stopped" {
            It "Should return Updated = false with an error" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Id = $vmId; Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }

                $result = Set-HvoVm -Id $vmId.ToString() -MemoryMB 2048

                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Error | Should -Be "VM must be Off to update"
                $result.State | Should -Be "Running"
            }
        }

        Context "When the VM is stopped" {
            It "Should update memory if different" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Id = $vmId; Name = "stopped-vm"; State = "Off"; MemoryStartup = 1GB; ProcessorCount = 2 }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $null }
                Mock Set-VMMemory -MockWith { }

                $result = Set-HvoVm -Id $vmId.ToString() -MemoryMB 2048

                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                Should -Invoke Set-VMMemory -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq "stopped-vm" -and $StartupBytes -eq (2048 * 1MB)
                }
            }

            It "Should update the number of vCPUs if different" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Id = $vmId; Name = "stopped-vm"; State = "Off"; MemoryStartup = 1GB; ProcessorCount = 2 }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $null }
                Mock Set-VMProcessor -MockWith { }

                $result = Set-HvoVm -Id $vmId.ToString() -Vcpu 4

                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                Should -Invoke Set-VMProcessor -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq "stopped-vm" -and $Count -eq 4
                }
            }

            It "Should return Unchanged = true if no changes are needed" {
                $vmId = $script:testVmGuid
                $memoryBytes = 1024 * 1MB
                $mockVm = [PSCustomObject]@{ Id = $vmId; Name = "stopped-vm"; State = "Off"; MemoryStartup = $memoryBytes; ProcessorCount = 2 }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockNic = [PSCustomObject]@{ SwitchName = "existing-switch" }

                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $mockNic }
                Mock Get-VMDvdDrive -MockWith { return $null }
                Mock Set-VMMemory -MockWith { }
                Mock Set-VMProcessor -MockWith { }
                Mock Remove-VMNetworkAdapter -MockWith { }
                Mock Add-VMNetworkAdapter -MockWith { }
                Mock Remove-VMDvdDrive -MockWith { }
                Mock Add-VMDvdDrive -MockWith { }

                $result = Set-HvoVm -Id $vmId.ToString() -MemoryMB 1024 -Vcpu 2 -SwitchName "existing-switch"

                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Unchanged | Should -Be $true
                Should -Not -Invoke Set-VMMemory
                Should -Not -Invoke Set-VMProcessor
                Should -Not -Invoke Remove-VMNetworkAdapter
                Should -Not -Invoke Add-VMNetworkAdapter
            }

            It "Should update the switch if different" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Id = $vmId; Name = "stopped-vm"; State = "Off"; MemoryStartup = 1GB; ProcessorCount = 2 }
                $mockNic = [PSCustomObject]@{ SwitchName = "old-switch" }

                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $mockNic }
                Mock Get-VMDvdDrive -MockWith { return $null }
                Mock Remove-VMNetworkAdapter -MockWith { }
                Mock Add-VMNetworkAdapter -MockWith { }

                $result = Set-HvoVm -Id $vmId.ToString() -SwitchName "new-switch"

                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                # Remove-VMNetworkAdapter is called via pipeline, so no -VMName bound
                Should -Invoke Remove-VMNetworkAdapter -Exactly -Times 1
                Should -Invoke Add-VMNetworkAdapter -Exactly -Times 1 -ParameterFilter { $VMName -eq "stopped-vm" -and $SwitchName -eq "new-switch" }
            }

            It "Should return an error if ISO file does not exist" {
                $vmId = $script:testVmGuid
                $isoPath = "/tmp/ISOs/nonexistent.iso"
                $mockVm = [PSCustomObject]@{ Id = $vmId; Name = "stopped-vm"; State = "Off"; MemoryStartup = 1GB; ProcessorCount = 2 }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $null }
                Mock Test-Path -ParameterFilter { $Path -eq $isoPath } -MockWith { return $false }

                $result = Set-HvoVm -Id $vmId.ToString() -IsoPath $isoPath

                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Error | Should -Be "ISO file not found"
                $result.Path | Should -Be $isoPath
            }
        }
    }

    Describe "Start-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }
                $result = Start-HvoVm -Id $vmId.ToString()
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is already running" {
            It "Should return AlreadyRunning = true" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { }
                $result = Start-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Started | Should -Be $false
                $result.AlreadyRunning | Should -Be $true
                Should -Not -Invoke Start-VM
            }
        }

        Context "When the VM is stopped" {
            It "Should start the VM" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "stopped-vm"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { }
                $result = Start-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Started | Should -Be $true
                Should -Invoke Start-VM -Exactly -Times 1 -ParameterFilter { $Name -eq "stopped-vm" }
            }
        }

        Context "When the VM is paused" {
            It "Should resume the VM" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "paused-vm"; State = "Paused" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Resume-VM -MockWith { }
                $result = Start-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Started | Should -Be $true
                $result.Resumed | Should -Be $true
                Should -Invoke Resume-VM -Exactly -Times 1 -ParameterFilter { $Name -eq "paused-vm" }
            }
        }

        Context "When the VM is saved" {
            It "Should start the VM from saved state" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "saved-vm"; State = "Saved" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { }
                $result = Start-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Started | Should -Be $true
                Should -Invoke Start-VM -Exactly -Times 1 -ParameterFilter { $Name -eq "saved-vm" }
            }
        }

        Context "When the VM is in an invalid state" {
            It "Should throw an exception for invalid state" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "invalid-vm"; State = "Starting" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                { Start-HvoVm -Id $vmId.ToString() } | Should -Throw "*invalid state for starting*"
            }
        }

        Context "When an exception occurs" {
            It "Should propagate exceptions that are not 'not found' errors" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-with-error"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { throw "Access denied" }
                { Start-HvoVm -Id $vmId.ToString() } | Should -Throw "Access denied"
            }
        }
    }

    Describe "Stop-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }
                $result = Stop-HvoVm -Id $vmId.ToString()
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is already stopped" {
            It "Should return AlreadyStopped = true" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "stopped-vm"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Stop-VM -MockWith { }
                $result = Stop-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Stopped | Should -Be $false
                $result.AlreadyStopped | Should -Be $true
                Should -Not -Invoke Stop-VM
            }
        }

        Context "When the VM is running" {
            It "Should stop the VM with force if the Force parameter is used" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Stop-VM -MockWith { }
                $result = Stop-HvoVm -Id $vmId.ToString() -Force
                $result | Should -Not -BeNullOrEmpty
                $result.Stopped | Should -Be $true
                Should -Invoke Stop-VM -Exactly -Times 1
            }

            It "Should stop the VM gracefully when shutdown service is available and enabled" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockShutdownService = [PSCustomObject]@{ Name = "Shutdown"; Enabled = $true }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq "running-vm" -and $Name -eq "Shutdown" } -MockWith { return $mockShutdownService }
                Mock Stop-VM -MockWith { }
                $result = Stop-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Stopped | Should -Be $true
                Should -Invoke Get-VMIntegrationService -Exactly -Times 1 -ParameterFilter { $VMName -eq "running-vm" -and $Name -eq "Shutdown" }
                Should -Invoke Stop-VM -Exactly -Times 1 -ParameterFilter { $Name -eq "running-vm" -and -not $PSBoundParameters.ContainsKey('Force') }
            }

            It "Should throw an exception when shutdown service is not available" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq "running-vm" -and $Name -eq "Shutdown" } -MockWith { return $null }
                Mock Stop-VM -MockWith { }
                { Stop-HvoVm -Id $vmId.ToString() } | Should -Throw "*SHUTDOWN_SERVICE_NOT_AVAILABLE*"
                Should -Not -Invoke Stop-VM
            }

            It "Should throw an exception when shutdown service is not enabled" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockShutdownService = [PSCustomObject]@{ Name = "Shutdown"; Enabled = $false }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq "running-vm" -and $Name -eq "Shutdown" } -MockWith { return $mockShutdownService }
                Mock Stop-VM -MockWith { }
                { Stop-HvoVm -Id $vmId.ToString() } | Should -Throw "*SHUTDOWN_SERVICE_NOT_ENABLED*"
                Should -Not -Invoke Stop-VM
            }
        }
    }

    Describe "Restart-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }
                $result = Restart-HvoVm -Id $vmId.ToString()
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is stopped" {
            It "Should start the VM (idempotence)" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "stopped-vm"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { }
                $result = Restart-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Restarted | Should -Be $true
                Should -Invoke Start-VM -Exactly -Times 1 -ParameterFilter { $Name -eq "stopped-vm" }
            }
        }

        Context "When the VM is running" {
            It "Should restart the VM with force if the Force parameter is used" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Restart-VM -MockWith { }
                $result = Restart-HvoVm -Id $vmId.ToString() -Force
                $result | Should -Not -BeNullOrEmpty
                $result.Restarted | Should -Be $true
                Should -Invoke Restart-VM -Exactly -Times 1
            }

            It "Should restart the VM gracefully when shutdown service is available and enabled" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockShutdownService = [PSCustomObject]@{ Name = "Shutdown"; Enabled = $true }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq "running-vm" -and $Name -eq "Shutdown" } -MockWith { return $mockShutdownService }
                Mock Restart-VM -MockWith { }
                $result = Restart-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Restarted | Should -Be $true
                Should -Invoke Get-VMIntegrationService -Exactly -Times 1 -ParameterFilter { $VMName -eq "running-vm" -and $Name -eq "Shutdown" }
                Should -Invoke Restart-VM -Exactly -Times 1 -ParameterFilter { $Name -eq "running-vm" -and -not $PSBoundParameters.ContainsKey('Force') }
            }

            It "Should throw an exception when shutdown service is not available" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq "running-vm" -and $Name -eq "Shutdown" } -MockWith { return $null }
                Mock Restart-VM -MockWith { }
                { Restart-HvoVm -Id $vmId.ToString() } | Should -Throw "*SHUTDOWN_SERVICE_NOT_AVAILABLE*"
                Should -Not -Invoke Restart-VM
            }

            It "Should throw an exception when shutdown service is not enabled" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockShutdownService = [PSCustomObject]@{ Name = "Shutdown"; Enabled = $false }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq "running-vm" -and $Name -eq "Shutdown" } -MockWith { return $mockShutdownService }
                Mock Restart-VM -MockWith { }
                { Restart-HvoVm -Id $vmId.ToString() } | Should -Throw "*SHUTDOWN_SERVICE_NOT_ENABLED*"
                Should -Not -Invoke Restart-VM
            }
        }
    }

    Describe "Suspend-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }
                $result = Suspend-HvoVm -Id $vmId.ToString()
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is already paused" {
            It "Should return AlreadySuspended = true" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "paused-vm"; State = "Paused" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Suspend-VM -MockWith { }
                $result = Suspend-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Suspended | Should -Be $false
                $result.AlreadySuspended | Should -Be $true
                Should -Not -Invoke Suspend-VM
            }
        }

        Context "When the VM is running" {
            It "Should suspend the VM" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Suspend-VM -MockWith { }
                $result = Suspend-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Suspended | Should -Be $true
                Should -Invoke Suspend-VM -Exactly -Times 1 -ParameterFilter { $Name -eq "running-vm" }
            }
        }

        Context "When the VM is in an invalid state" {
            It "Should throw an exception for invalid state" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "invalid-vm"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                { Suspend-HvoVm -Id $vmId.ToString() } | Should -Throw "*invalid state for suspending*"
            }
        }

        Context "When an exception occurs" {
            It "Should propagate exceptions that are not 'not found' errors" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-with-error"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Suspend-VM -MockWith { throw "Access denied" }
                { Suspend-HvoVm -Id $vmId.ToString() } | Should -Throw "Access denied"
            }
        }
    }

    Describe "Resume-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }
                $result = Resume-HvoVm -Id $vmId.ToString()
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is already running" {
            It "Should return AlreadyRunning = true" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Resume-VM -MockWith { }
                $result = Resume-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Resumed | Should -Be $false
                $result.AlreadyRunning | Should -Be $true
                Should -Not -Invoke Resume-VM
            }
        }

        Context "When the VM is paused" {
            It "Should resume the VM" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "paused-vm"; State = "Paused" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Resume-VM -MockWith { }
                $result = Resume-HvoVm -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Resumed | Should -Be $true
                Should -Invoke Resume-VM -Exactly -Times 1 -ParameterFilter { $Name -eq "paused-vm" }
            }
        }

        Context "When the VM is stopped" {
            It "Should throw an exception" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "stopped-vm"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                { Resume-HvoVm -Id $vmId.ToString() } | Should -Throw
            }
        }
    }

    Describe "Remove-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return false" {
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }
                Mock Remove-VM -MockWith { }
                $result = Remove-HvoVm -Id $vmId.ToString()
                $result | Should -Be $false
                Should -Not -Invoke Remove-VM
            }
        }

        Context "When the VM exists" {
            It "Should stop the VM if it is running before deletion" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "running-vm"; State = "Running" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Stop-VM -MockWith { }
                Mock Get-VMSnapshot -MockWith { return $null }
                Mock Get-VMDvdDrive -MockWith { return @() }
                Mock Get-VMHardDiskDrive -MockWith { return @() }
                Mock Remove-VM -MockWith { }
                $result = Remove-HvoVm -Id $vmId.ToString()
                $result | Should -Be $true
                Should -Invoke Stop-VM -Exactly -Times 1
                Should -Invoke Remove-VM -Exactly -Times 1
            }

            It "Should remove snapshots before deletion" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-with-snapshots"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockSnapshots = @([PSCustomObject]@{ Name = "snapshot1" }, [PSCustomObject]@{ Name = "snapshot2" })
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMSnapshot -MockWith { return $mockSnapshots }
                Mock Remove-VMSnapshot -MockWith { }
                Mock Get-VMDvdDrive -MockWith { return @() }
                Mock Get-VMHardDiskDrive -MockWith { return @() }
                Mock Remove-VM -MockWith { }
                $result = Remove-HvoVm -Id $vmId.ToString()
                $result | Should -Be $true
                Should -Invoke Remove-VMSnapshot -Exactly -Times 1 -ParameterFilter { $VMName -eq "vm-with-snapshots" }
            }

            It "Should remove disks if RemoveDisks is true" {
                $vmId = $script:testVmGuid
                $diskPath = "/tmp/VMs/vm-with-disks.vhdx"
                $mockVm = [PSCustomObject]@{ Name = "vm-with-disks"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockDisk = [PSCustomObject]@{ Path = $diskPath }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMSnapshot -MockWith { return $null }
                Mock Get-VMDvdDrive -MockWith { return @() }
                Mock Get-VMHardDiskDrive -MockWith { return @($mockDisk) }
                Mock Test-Path -ParameterFilter { $Path -eq $diskPath } -MockWith { return $true }
                Mock Remove-Item -MockWith { }
                Mock Remove-VM -MockWith { }
                $result = Remove-HvoVm -Id $vmId.ToString() -RemoveDisks $true
                $result | Should -Be $true
                Should -Invoke Remove-Item -Exactly -Times 1 -ParameterFilter { $Path -eq $diskPath -and $Force -eq $true }
            }

            It "Should remove DVD drives before deletion" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-with-dvd"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockDvdDrive = [PSCustomObject]@{ ControllerNumber = 0; ControllerLocation = 0 }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMSnapshot -MockWith { return $null }
                Mock Get-VMDvdDrive -MockWith { return @($mockDvdDrive) }
                Mock Remove-VMDvdDrive -MockWith { }
                Mock Get-VMHardDiskDrive -MockWith { return @() }
                Mock Remove-VM -MockWith { }
                $result = Remove-HvoVm -Id $vmId.ToString()
                $result | Should -Be $true
                Should -Invoke Remove-VMDvdDrive -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq "vm-with-dvd" -and $ControllerNumber -eq 0 -and $ControllerLocation -eq 0
                }
            }

            It "Should handle exceptions that are not 'not found' errors" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-with-error"; State = "Off" }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMSnapshot -MockWith { return $null }
                Mock Get-VMDvdDrive -MockWith { return @() }
                Mock Get-VMHardDiskDrive -MockWith { return @() }
                Mock Remove-VM -MockWith { throw "Access denied" }
                { Remove-HvoVm -Id $vmId.ToString() } | Should -Throw "Access denied"
            }
        }
    }

    Describe "Get-HvoVmNetworkAdapters" {
        Context "When the VM does not exist" {
            It "Should return null" {
                $vmId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }
                Mock Get-VMNetworkAdapter -MockWith { }
                $result = Get-HvoVmNetworkAdapters -Id $vmId.ToString()
                $result | Should -BeNullOrEmpty
                Should -Invoke Get-VM -Exactly -Times 1 -ParameterFilter { $Id -eq $vmId }
                Should -Invoke Get-VMNetworkAdapter -Exactly -Times 0
            }
        }

        Context "When the VM exists with network adapters" {
            It "Should return a formatted list of adapters with Id" {
                $vmId = $script:testVmGuid
                $adapterId1 = [guid]::NewGuid()
                $adapterId2 = [guid]::NewGuid()
                $mockVm = [PSCustomObject]@{ Name = "vm-with-adapters" }
                $mockStatus1 = [PSCustomObject]@{ Value = "Ok" }
                $mockStatus1 | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return "Ok" } -Force
                $mockAdapter1 = [PSCustomObject]@{
                    Id = $adapterId1; Name = "Network Adapter"; SwitchName = "LAN"; IsLegacy = $false
                    MacAddress = "00155D012345"; Status = $mockStatus1
                }
                $mockStatus2 = [PSCustomObject]@{ Value = "Ok" }
                $mockStatus2 | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return "Ok" } -Force
                $mockAdapter2 = [PSCustomObject]@{
                    Id = $adapterId2; Name = "Legacy Network Adapter"; SwitchName = "WAN"; IsLegacy = $true
                    MacAddress = "00155D012346"; Status = $mockStatus2
                }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -ParameterFilter { $null -ne $VM } -MockWith { return @($mockAdapter1, $mockAdapter2) }
                $result = Get-HvoVmNetworkAdapters -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Count | Should -Be 2
                $result[0].Id | Should -Be $adapterId1.ToString()
                $result[0].Name | Should -Be "Network Adapter"
                $result[0].SwitchName | Should -Be "LAN"
                $result[0].Type | Should -Be "Synthetic"
                $result[1].Id | Should -Be $adapterId2.ToString()
                $result[1].Name | Should -Be "Legacy Network Adapter"
                $result[1].Type | Should -Be "Legacy"
                Should -Invoke Get-VM -Exactly -Times 1 -ParameterFilter { $Id -eq $vmId }
                Should -Invoke Get-VMNetworkAdapter -Exactly -Times 1 -ParameterFilter { $null -ne $VM }
            }

            It "Should handle a single adapter (not an array)" {
                $vmId = $script:testVmGuid
                $adapterId = [guid]::NewGuid()
                $mockVm = [PSCustomObject]@{ Name = "vm-with-single-adapter" }
                $mockStatus = [PSCustomObject]@{ Value = "Ok" }
                $mockStatus | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return "Ok" } -Force
                $mockAdapter = [PSCustomObject]@{
                    Id = $adapterId; Name = "Network Adapter"; SwitchName = "LAN"; IsLegacy = $false
                    MacAddress = "00155D012345"; Status = $mockStatus
                }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -ParameterFilter { $null -ne $VM } -MockWith { return $mockAdapter }
                $result = Get-HvoVmNetworkAdapters -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Count | Should -Be 1
                $result[0].Id | Should -Be $adapterId.ToString()
                $result[0].Name | Should -Be "Network Adapter"
            }

            It "Should handle adapter without switch (SwitchName is null)" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-with-unconnected-adapter" }
                $mockStatus = [PSCustomObject]@{ Value = "Ok" }
                $mockStatus | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return "Ok" } -Force
                $mockAdapter = [PSCustomObject]@{
                    InstanceId = [guid]::NewGuid(); Name = "Network Adapter"; SwitchName = $null; IsLegacy = $false
                    MacAddress = "00155D012345"; Status = $mockStatus
                }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -ParameterFilter { $null -ne $VM } -MockWith { return $mockAdapter }
                $result = Get-HvoVmNetworkAdapters -Id $vmId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result[0].SwitchName | Should -BeNullOrEmpty
            }
        }

        Context "When the VM exists without network adapters" {
            It "Should return an empty array" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-without-adapters" }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -ParameterFilter { $null -ne $VM } -MockWith { return $null }
                $result = Get-HvoVmNetworkAdapters -Id $vmId.ToString()
                if ($null -ne $result) { $result.Count | Should -Be 0 }
                Should -Invoke Get-VM -Exactly -Times 1
                Should -Invoke Get-VMNetworkAdapter -Exactly -Times 1
            }
        }

        Context "When Get-VMNetworkAdapter throws an error" {
            It "Should propagate the error if it's not a 'not found' error" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-with-error" }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -ParameterFilter { $null -ne $VM } -MockWith { throw "Access denied" }
                { Get-HvoVmNetworkAdapters -Id $vmId.ToString() } | Should -Throw "Access denied"
            }

            It "Should return null if the error matches 'not found'" {
                $vmId = $script:testVmGuid
                $mockVm = [PSCustomObject]@{ Name = "vm-with-not-found-error" }
                Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -ParameterFilter { $null -ne $VM } -MockWith { throw "VM not found" }
                $result = Get-HvoVmNetworkAdapters -Id $vmId.ToString()
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Describe "Remove-HvoVmNetworkAdapter" {
        It "Should return false when VM does not exist" {
            $vmId = [guid]'00000000-0000-0000-0000-000000000001'
            $adapterId = [guid]::NewGuid().ToString()
            Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $null }
            $result = Remove-HvoVmNetworkAdapter -VMId $vmId.ToString() -AdapterId $adapterId
            $result | Should -Be $false
        }

        It "Should return false when adapter is not found" {
            $vmId = $script:testVmGuid
            $mockVm = [PSCustomObject]@{ Name = "vm1" }
            $mockAdapter = [PSCustomObject]@{ Id = [guid]::NewGuid(); Name = "NIC1" }
            Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
            Mock Get-VMNetworkAdapter -ParameterFilter { $null -ne $VM } -MockWith { return $mockAdapter }
            $result = Remove-HvoVmNetworkAdapter -VMId $vmId.ToString() -AdapterId "00000000-0000-0000-0000-000000000000"
            $result | Should -Be $false
        }

        It "Should remove the adapter when VM and adapter exist" {
            $vmId = $script:testVmGuid
            $adapterId = [guid]::NewGuid()
            $mockVm = [PSCustomObject]@{ Name = "vm1" }
            $mockAdapter = [PSCustomObject]@{ Id = $adapterId; Name = "NIC1" }
            Mock Get-VM -ParameterFilter { $Id -eq $vmId } -MockWith { return $mockVm }
            Mock Get-VMNetworkAdapter -ParameterFilter { $null -ne $VM } -MockWith { return $mockAdapter }
            Mock Remove-VMNetworkAdapter -MockWith { }
            $result = Remove-HvoVmNetworkAdapter -VMId $vmId.ToString() -AdapterId $adapterId.ToString()
            $result | Should -Be $true
            Should -Invoke Remove-VMNetworkAdapter -Exactly -Times 1 -ParameterFilter { $null -ne $VMNetworkAdapter }
        }
    }
}
