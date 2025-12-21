# Unit tests for the HvoVm module
# Uses InModuleScope to test within the module context and allow mocks to work

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "../../src/modules/HvoVm/HvoVm.psd1"
    Import-Module $modulePath -Force
}

InModuleScope HvoVm {
    Describe "New-HvoVm" {
        Context "When the VM already exists" {
            It "Should return an object with Exists = true" {
                # Arrange
                $vmName = "test-vm-existing"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock New-VM -MockWith { }

                # Act
                $result = New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath "C:\VMs" -DiskGB 20 -SwitchName "test-switch"

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Exists | Should -Be $true
                $result.Name | Should -Be $vmName
                Should -Invoke Get-VM -Exactly -Times 1 -ParameterFilter { $Name -eq $vmName }
                Should -Not -Invoke New-VM
            }
        }

        Context "When the VM does not exist" {
            It "Should create a new VM with the provided parameters" {
                # Arrange
                $vmName = "test-vm-new"
                $diskPath = "C:\TestVMs"
                $vhdPath = Join-Path $diskPath "$vmName.vhdx"
                $switchName = "test-switch"

                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                }

                Mock Get-VM -MockWith { return $null }
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
                $result.Exists | Should -Be $false
                $result.Name | Should -Be $vmName
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

            It "Should create the disk directory if it does not exist" {
                # Arrange
                $vmName = "test-vm-new"
                $diskPath = "C:\TestVMs"

                Mock Get-VM -MockWith { return $null }
                Mock Test-Path -ParameterFilter { $Path -eq $diskPath } -MockWith { return $false }
                Mock New-Item -MockWith { return [PSCustomObject]@{ FullName = $diskPath } }
                Mock Test-Path -ParameterFilter { $Path -like "*.vhdx" } -MockWith { return $false }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = "test.vhdx" } }
                Mock New-VM -MockWith { return [PSCustomObject]@{ Name = $vmName } }
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
                $diskPath = "C:\TestVMs"
                $vhdPath = Join-Path $diskPath "$vmName.vhdx"

                Mock Get-VM -MockWith { return $null }
                Mock Test-Path -ParameterFilter { $Path -eq $diskPath } -MockWith { return $true }
                Mock Test-Path -ParameterFilter { $Path -eq $vhdPath } -MockWith { return $false }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = $vhdPath } }
                Mock New-VM -MockWith { return [PSCustomObject]@{ Name = $vmName } }
                Mock Set-VMProcessor -MockWith { }

                # Act
                New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath $diskPath -DiskGB 20 -SwitchName "test-switch" | Out-Null

                # Assert
                Should -Invoke New-VHD -Exactly -Times 1 -ParameterFilter {
                    $Path -eq $vhdPath -and $SizeBytes -eq (20 * 1GB) -and $Dynamic -eq $true
                }
            }

            It "Should add a DVD drive if IsoPath is provided" {
                # Arrange
                $vmName = "test-vm-new"
                $isoPath = "C:\ISOs\test.iso"

                Mock Get-VM -MockWith { return $null }
                Mock Test-Path -ParameterFilter { $Path -ne $isoPath } -MockWith { return $true }
                Mock Test-Path -ParameterFilter { $Path -eq $isoPath } -MockWith { return $true }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = "test.vhdx" } }
                Mock New-VM -MockWith { return [PSCustomObject]@{ Name = $vmName } }
                Mock Set-VMProcessor -MockWith { }
                Mock Add-VMDvdDrive -MockWith { }

                # Act
                New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath "C:\VMs" -DiskGB 20 -SwitchName "test-switch" -IsoPath $isoPath | Out-Null

                # Assert
                Should -Invoke Add-VMDvdDrive -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and $Path -eq $isoPath
                }
            }

            It "Should throw an exception if IsoPath does not exist" {
                # Arrange
                $vmName = "test-vm-new"
                $isoPath = "C:\ISOs\nonexistent.iso"

                Mock Get-VM -MockWith { return $null }
                Mock Test-Path -ParameterFilter { $Path -ne $isoPath } -MockWith { return $true }
                Mock Test-Path -ParameterFilter { $Path -eq $isoPath } -MockWith { return $false }
                Mock New-VHD -MockWith { return [PSCustomObject]@{ Path = "test.vhdx" } }
                Mock New-VM -MockWith { return [PSCustomObject]@{ Name = $vmName } }
                Mock Set-VMProcessor -MockWith { }

                # Act & Assert
                { New-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -DiskPath "C:\VMs" -DiskGB 20 -SwitchName "test-switch" -IsoPath $isoPath } | Should -Throw
            }
        }
    }

    Describe "Get-HvoVm" {
        Context "When the VM exists" {
            It "Should return the VM details" {
                # Arrange
                $vmName = "test-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                    CPUUsage = 50
                    MemoryAssigned = 1GB
                    Uptime = New-TimeSpan -Days 1
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }

                # Act
                $result = Get-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be $vmName
                $result.State | Should -Be "Running"
                $result.CPUUsage | Should -Be 50
                $result.MemoryAssigned | Should -Be 1GB
                Should -Invoke Get-VM -Exactly -Times 1 -ParameterFilter { $Name -eq $vmName }
            }
        }

        Context "When the VM does not exist" {
            It "Should return null" {
                # Arrange
                $vmName = "non-existent-vm"

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $null }

                # Act
                $result = Get-HvoVm -Name $vmName

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Describe "Get-HvoVms" {
        It "Should return the list of all VMs" {
            # Arrange
                $vm1 = [PSCustomObject]@{
                    Name = "vm1"
                    State = "Running"
                    CPUUsage = 30
                    MemoryAssigned = 512MB
                    Uptime = New-TimeSpan -Hours 2
                }
                $vm1 | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                $vm2 = [PSCustomObject]@{
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
            $result[0].Name | Should -Be "vm1"
            $result[1].Name | Should -Be "vm2"
            Should -Invoke Get-VM -Exactly -Times 1
        }

        It "Should return an empty array if there are no VMs" {
            # Arrange
            Mock Get-VM -MockWith { return @() }

            # Act
            $result = Get-HvoVms

            # Assert
            # ForEach-Object on an empty array returns $null, so we accept both cases
            if ($null -eq $result) {
                $result = @()
            }
            $result.Count | Should -Be 0
        }
    }

    Describe "Set-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return Updated = false with an error" {
                # Arrange
                $vmName = "non-existent-vm"

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $null }

                # Act
                $result = Set-HvoVm -Name $vmName -MemoryMB 2048

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Error | Should -Be "VM not found"
            }
        }

        Context "When the VM is not stopped" {
            It "Should return Updated = false with an error" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }

                # Act
                $result = Set-HvoVm -Name $vmName -MemoryMB 2048

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Error | Should -Be "VM must be Off to update"
                $result.State | Should -Be "Running"
            }
        }

        Context "When the VM is stopped" {
            It "Should update memory if different" {
                # Arrange
                $vmName = "stopped-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = [Microsoft.HyperV.PowerShell.VMState]::Off
                    MemoryStartup = 1GB
                    ProcessorCount = 2
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $null }
                Mock Set-VMMemory -MockWith { }

                # Act
                $result = Set-HvoVm -Name $vmName -MemoryMB 2048

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                Should -Invoke Set-VMMemory -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and $StartupBytes -eq (2048 * 1MB)
                }
            }

            It "Should update the number of vCPUs if different" {
                # Arrange
                $vmName = "stopped-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = [Microsoft.HyperV.PowerShell.VMState]::Off
                    MemoryStartup = 1GB
                    ProcessorCount = 2
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $null }
                Mock Set-VMProcessor -MockWith { }

                # Act
                $result = Set-HvoVm -Name $vmName -Vcpu 4

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                Should -Invoke Set-VMProcessor -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and $Count -eq 4
                }
            }

            It "Should return Unchanged = true if no changes are needed" {
                # Arrange
                $vmName = "stopped-vm"
                # Use exactly 1024MB to avoid precision issues
                $memoryBytes = 1024 * 1MB
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                    MemoryStartup = $memoryBytes
                    ProcessorCount = 2
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                $mockNic = [PSCustomObject]@{
                    SwitchName = "existing-switch"
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                # Get-VMNetworkAdapter can return a single object or an array
                # The code uses $currentNic?.SwitchName which works on a single object
                # For this test, we simulate a single object (not an array) so the code works
                Mock Get-VMNetworkAdapter -MockWith { return $mockNic }
                Mock Get-VMDvdDrive -MockWith { return $null }
                Mock Set-VMMemory -MockWith { }
                Mock Set-VMProcessor -MockWith { }
                Mock Remove-VMNetworkAdapter -MockWith { }
                Mock Add-VMNetworkAdapter -MockWith { }
                Mock Remove-VMDvdDrive -MockWith { }
                Mock Add-VMDvdDrive -MockWith { }

                # Act
                $result = Set-HvoVm -Name $vmName -MemoryMB 1024 -Vcpu 2 -SwitchName "existing-switch"

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Unchanged | Should -Be $true
                # Verify that no modifications were made
                Should -Not -Invoke Set-VMMemory
                Should -Not -Invoke Set-VMProcessor
                Should -Not -Invoke Remove-VMNetworkAdapter
                Should -Not -Invoke Add-VMNetworkAdapter
            }

            It "Should update the switch if different" {
                # Arrange
                $vmName = "stopped-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = [Microsoft.HyperV.PowerShell.VMState]::Off
                    MemoryStartup = 1GB
                    ProcessorCount = 2
                }

                $mockNic = [PSCustomObject]@{
                    SwitchName = "old-switch"
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $mockNic }
                Mock Get-VMDvdDrive -MockWith { return $null }
                Mock Remove-VMNetworkAdapter -MockWith { }
                Mock Add-VMNetworkAdapter -MockWith { }

                # Act
                $result = Set-HvoVm -Name $vmName -SwitchName "new-switch"

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                Should -Invoke Remove-VMNetworkAdapter -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName
                }
                Should -Invoke Add-VMNetworkAdapter -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and $SwitchName -eq "new-switch"
                }
            }

            It "Should return an error if ISO file does not exist" {
                # Arrange
                $vmName = "stopped-vm"
                $isoPath = "C:\ISOs\nonexistent.iso"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = [Microsoft.HyperV.PowerShell.VMState]::Off
                    MemoryStartup = 1GB
                    ProcessorCount = 2
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMNetworkAdapter -MockWith { return $null }
                Mock Test-Path -ParameterFilter { $Path -eq $isoPath } -MockWith { return $false }

                # Act
                $result = Set-HvoVm -Name $vmName -IsoPath $isoPath

                # Assert
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
                # Arrange
                $vmName = "non-existent-vm"

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $null }

                # Act
                $result = Start-HvoVm -Name $vmName

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is already running" {
            It "Should return AlreadyRunning = true" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { }

                # Act
                $result = Start-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Started | Should -Be $false
                $result.AlreadyRunning | Should -Be $true
                Should -Not -Invoke Start-VM
            }
        }

        Context "When the VM is stopped" {
            It "Should start the VM" {
                # Arrange
                $vmName = "stopped-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { }

                # Act
                $result = Start-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Started | Should -Be $true
                $result.AlreadyRunning | Should -Be $false
                Should -Invoke Start-VM -Exactly -Times 1 -ParameterFilter { $Name -eq $vmName }
            }
        }

        Context "When the VM is paused" {
            It "Should resume the VM" {
                # Arrange
                $vmName = "paused-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Paused"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Resume-VM -MockWith { }

                # Act
                $result = Start-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Started | Should -Be $true
                $result.Resumed | Should -Be $true
                Should -Invoke Resume-VM -Exactly -Times 1 -ParameterFilter { $Name -eq $vmName }
            }
        }

        Context "When the VM is saved" {
            It "Should start the VM from saved state" {
                # Arrange
                $vmName = "saved-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Saved"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { }

                # Act
                $result = Start-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Started | Should -Be $true
                $result.Resumed | Should -Be $false
                Should -Invoke Start-VM -Exactly -Times 1 -ParameterFilter { $Name -eq $vmName }
            }
        }

        Context "When the VM is in an invalid state" {
            It "Should throw an exception for invalid state" {
                # Arrange
                $vmName = "invalid-state-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Starting"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }

                # Act & Assert
                { Start-HvoVm -Name $vmName } | Should -Throw "*invalid state for starting*"
            }
        }

        Context "When an exception occurs" {
            It "Should propagate exceptions that are not 'not found' errors" {
                # Arrange
                $vmName = "vm-with-error"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { throw "Access denied" }

                # Act & Assert
                { Start-HvoVm -Name $vmName } | Should -Throw "Access denied"
            }
        }
    }

    Describe "Stop-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                # Arrange
                $vmName = "non-existent-vm"

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $null }

                # Act
                $result = Stop-HvoVm -Name $vmName

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is already stopped" {
            It "Should return AlreadyStopped = true" {
                # Arrange
                $vmName = "stopped-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Stop-VM -MockWith { }

                # Act
                $result = Stop-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Stopped | Should -Be $false
                $result.AlreadyStopped | Should -Be $true
                Should -Not -Invoke Stop-VM
            }
        }

        Context "When the VM is running" {
            It "Should stop the VM with force if the Force parameter is used" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Stop-VM -MockWith { }

                # Act
                $result = Stop-HvoVm -Name $vmName -Force

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Stopped | Should -Be $true
                Should -Invoke Stop-VM -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $vmName -and $Force -eq $true
                }
            }

            It "Should stop the VM gracefully when shutdown service is available and enabled" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                $mockShutdownService = [PSCustomObject]@{
                    Name = "Shutdown"
                    Enabled = $true
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq $vmName -and $Name -eq "Shutdown" } -MockWith { return $mockShutdownService }
                Mock Stop-VM -MockWith { }

                # Act
                $result = Stop-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Stopped | Should -Be $true
                Should -Invoke Get-VMIntegrationService -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and $Name -eq "Shutdown"
                }
                Should -Invoke Stop-VM -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $vmName -and -not $PSBoundParameters.ContainsKey('Force')
                }
            }

            It "Should throw an exception when shutdown service is not available" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq $vmName -and $Name -eq "Shutdown" } -MockWith { return $null }
                Mock Stop-VM -MockWith { }

                # Act & Assert
                { Stop-HvoVm -Name $vmName } | Should -Throw "*SHUTDOWN_SERVICE_NOT_AVAILABLE*"
                Should -Not -Invoke Stop-VM
            }

            It "Should throw an exception when shutdown service is not enabled" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                $mockShutdownService = [PSCustomObject]@{
                    Name = "Shutdown"
                    Enabled = $false
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq $vmName -and $Name -eq "Shutdown" } -MockWith { return $mockShutdownService }
                Mock Stop-VM -MockWith { }

                # Act & Assert
                { Stop-HvoVm -Name $vmName } | Should -Throw "*SHUTDOWN_SERVICE_NOT_ENABLED*"
                Should -Not -Invoke Stop-VM
            }
        }
    }

    Describe "Restart-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                # Arrange
                $vmName = "non-existent-vm"

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $null }

                # Act
                $result = Restart-HvoVm -Name $vmName

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is stopped" {
            It "Should start the VM (idempotence)" {
                # Arrange
                $vmName = "stopped-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Start-VM -MockWith { }

                # Act
                $result = Restart-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Restarted | Should -Be $true
                Should -Invoke Start-VM -Exactly -Times 1 -ParameterFilter { $Name -eq $vmName }
            }
        }

        Context "When the VM is running" {
            It "Should restart the VM with force if the Force parameter is used" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Restart-VM -MockWith { }

                # Act
                $result = Restart-HvoVm -Name $vmName -Force

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Restarted | Should -Be $true
                Should -Invoke Restart-VM -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $vmName -and $Force -eq $true
                }
            }

            It "Should restart the VM gracefully when shutdown service is available and enabled" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                $mockShutdownService = [PSCustomObject]@{
                    Name = "Shutdown"
                    Enabled = $true
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq $vmName -and $Name -eq "Shutdown" } -MockWith { return $mockShutdownService }
                Mock Restart-VM -MockWith { }

                # Act
                $result = Restart-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Restarted | Should -Be $true
                Should -Invoke Get-VMIntegrationService -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and $Name -eq "Shutdown"
                }
                Should -Invoke Restart-VM -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $vmName -and -not $PSBoundParameters.ContainsKey('Force')
                }
            }

            It "Should throw an exception when shutdown service is not available" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq $vmName -and $Name -eq "Shutdown" } -MockWith { return $null }
                Mock Restart-VM -MockWith { }

                # Act & Assert
                { Restart-HvoVm -Name $vmName } | Should -Throw "*SHUTDOWN_SERVICE_NOT_AVAILABLE*"
                Should -Not -Invoke Restart-VM
            }

            It "Should throw an exception when shutdown service is not enabled" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                $mockShutdownService = [PSCustomObject]@{
                    Name = "Shutdown"
                    Enabled = $false
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMIntegrationService -ParameterFilter { $VMName -eq $vmName -and $Name -eq "Shutdown" } -MockWith { return $mockShutdownService }
                Mock Restart-VM -MockWith { }

                # Act & Assert
                { Restart-HvoVm -Name $vmName } | Should -Throw "*SHUTDOWN_SERVICE_NOT_ENABLED*"
                Should -Not -Invoke Restart-VM
            }
        }
    }

    Describe "Suspend-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                # Arrange
                $vmName = "non-existent-vm"

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $null }

                # Act
                $result = Suspend-HvoVm -Name $vmName

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is already paused" {
            It "Should return AlreadySuspended = true" {
                # Arrange
                $vmName = "paused-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Paused"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Suspend-VM -MockWith { }

                # Act
                $result = Suspend-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Suspended | Should -Be $false
                $result.AlreadySuspended | Should -Be $true
                Should -Not -Invoke Suspend-VM
            }
        }

        Context "When the VM is running" {
            It "Should suspend the VM" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Suspend-VM -MockWith { }

                # Act
                $result = Suspend-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Suspended | Should -Be $true
                $result.AlreadySuspended | Should -Be $false
                Should -Invoke Suspend-VM -Exactly -Times 1 -ParameterFilter { $Name -eq $vmName }
            }
        }

        Context "When the VM is in an invalid state" {
            It "Should throw an exception for invalid state" {
                # Arrange
                $vmName = "invalid-state-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }

                # Act & Assert
                { Suspend-HvoVm -Name $vmName } | Should -Throw "*invalid state for suspending*"
            }
        }

        Context "When an exception occurs" {
            It "Should propagate exceptions that are not 'not found' errors" {
                # Arrange
                $vmName = "vm-with-error"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Suspend-VM -MockWith { throw "Access denied" }

                # Act & Assert
                { Suspend-HvoVm -Name $vmName } | Should -Throw "Access denied"
            }
        }
    }

    Describe "Resume-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return null" {
                # Arrange
                $vmName = "non-existent-vm"

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $null }

                # Act
                $result = Resume-HvoVm -Name $vmName

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When the VM is already running" {
            It "Should return AlreadyRunning = true" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Resume-VM -MockWith { }

                # Act
                $result = Resume-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Resumed | Should -Be $false
                $result.AlreadyRunning | Should -Be $true
                Should -Not -Invoke Resume-VM
            }
        }

        Context "When the VM is paused" {
            It "Should resume the VM" {
                # Arrange
                $vmName = "paused-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Paused"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Resume-VM -MockWith { }

                # Act
                $result = Resume-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Resumed | Should -Be $true
                $result.AlreadyRunning | Should -Be $false
                Should -Invoke Resume-VM -Exactly -Times 1 -ParameterFilter { $Name -eq $vmName }
            }
        }

        Context "When the VM is stopped" {
            It "Should throw an exception" {
                # Arrange
                $vmName = "stopped-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }

                # Act & Assert
                { Resume-HvoVm -Name $vmName } | Should -Throw
            }
        }
    }

    Describe "Remove-HvoVm" {
        Context "When the VM does not exist" {
            It "Should return false" {
                # Arrange
                $vmName = "non-existent-vm"

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $null }
                Mock Remove-VM -MockWith { }

                # Act
                $result = Remove-HvoVm -Name $vmName

                # Assert
                $result | Should -Be $false
                Should -Not -Invoke Remove-VM
            }
        }

        Context "When the VM exists" {
            It "Should stop the VM if it is running before deletion" {
                # Arrange
                $vmName = "running-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Stop-VM -MockWith { }
                Mock Get-VMSnapshot -MockWith { return $null }
                Mock Get-VMDvdDrive -MockWith { return @() }
                Mock Get-VMHardDiskDrive -MockWith { return @() }
                Mock Remove-VM -MockWith { }

                # Act
                $result = Remove-HvoVm -Name $vmName

                # Assert
                $result | Should -Be $true
                Should -Invoke Stop-VM -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $vmName -and $Force -eq $true
                }
                Should -Invoke Remove-VM -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $vmName -and $Force -eq $true
                }
            }

            It "Should remove snapshots before deletion" {
                # Arrange
                $vmName = "vm-with-snapshots"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockSnapshots = @(
                    [PSCustomObject]@{ Name = "snapshot1" },
                    [PSCustomObject]@{ Name = "snapshot2" }
                )

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMSnapshot -MockWith { return $mockSnapshots }
                Mock Remove-VMSnapshot -MockWith { }
                Mock Get-VMDvdDrive -MockWith { return @() }
                Mock Get-VMHardDiskDrive -MockWith { return @() }
                Mock Remove-VM -MockWith { }

                # Act
                $result = Remove-HvoVm -Name $vmName

                # Assert
                $result | Should -Be $true
                Should -Invoke Remove-VMSnapshot -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName
                }
            }

            It "Should remove disks if RemoveDisks is true" {
                # Arrange
                $vmName = "vm-with-disks"
                $diskPath = "C:\VMs\vm-with-disks.vhdx"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockDisk = [PSCustomObject]@{
                    Path = $diskPath
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMSnapshot -MockWith { return $null }
                Mock Get-VMDvdDrive -MockWith { return @() }
                Mock Get-VMHardDiskDrive -MockWith { return @($mockDisk) }
                Mock Test-Path -ParameterFilter { $Path -eq $diskPath } -MockWith { return $true }
                Mock Remove-Item -MockWith { }
                Mock Remove-VM -MockWith { }

                # Act
                $result = Remove-HvoVm -Name $vmName -RemoveDisks $true

                # Assert
                $result | Should -Be $true
                Should -Invoke Remove-Item -Exactly -Times 1 -ParameterFilter {
                    $Path -eq $diskPath -and $Force -eq $true
                }
            }

            It "Should remove DVD drives before deletion" {
                # Arrange
                $vmName = "vm-with-dvd"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force
                $mockDvdDrive = [PSCustomObject]@{
                    ControllerNumber = 0
                    ControllerLocation = 0
                }

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMSnapshot -MockWith { return $null }
                Mock Get-VMDvdDrive -MockWith { return @($mockDvdDrive) }
                Mock Remove-VMDvdDrive -MockWith { }
                Mock Get-VMHardDiskDrive -MockWith { return @() }
                Mock Remove-VM -MockWith { }

                # Act
                $result = Remove-HvoVm -Name $vmName

                # Assert
                $result | Should -Be $true
                Should -Invoke Remove-VMDvdDrive -Exactly -Times 1 -ParameterFilter {
                    $VMName -eq $vmName -and
                    $ControllerNumber -eq 0 -and
                    $ControllerLocation -eq 0
                }
            }

            It "Should handle exceptions that are not 'not found' errors" {
                # Arrange
                $vmName = "vm-with-error"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Off"
                }
                $mockVm | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return $this.State } -Force

                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }
                Mock Get-VMSnapshot -MockWith { return $null }
                Mock Get-VMDvdDrive -MockWith { return @() }
                Mock Get-VMHardDiskDrive -MockWith { return @() }
                Mock Remove-VM -MockWith { throw "Access denied" }

                # Act & Assert
                { Remove-HvoVm -Name $vmName } | Should -Throw "Access denied"
            }
        }
    }
}
