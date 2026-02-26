# Unit tests for the HvoSwitch module
# Uses InModuleScope to test within the module context and allow mocks to work

BeforeAll {
    # Create stubs for Hyper-V cmdlets when they are not present (e.g. WSL, Linux)
    # This allows Pester to mock these commands even without the Hyper-V module
    if (-not (Get-Command Get-VMSwitch -ErrorAction SilentlyContinue)) {
        function global:Get-VMSwitch { param($Name, $Id, $ErrorAction) }
    }
    if (-not (Get-Command New-VMSwitch -ErrorAction SilentlyContinue)) {
        function global:New-VMSwitch { param($Name, $SwitchType, $NetAdapterName, $AllowManagementOS) }
    }
    if (-not (Get-Command Set-VMSwitch -ErrorAction SilentlyContinue)) {
        function global:Set-VMSwitch { param($Name, $Notes, $ErrorAction) }
    }
    if (-not (Get-Command Remove-VMSwitch -ErrorAction SilentlyContinue)) {
        function global:Remove-VMSwitch { param($Name, $Force, $ErrorAction) }
    }

    $modulePath = Join-Path $PSScriptRoot "../../src/modules/HvoSwitch/HvoSwitch.psd1"
    Import-Module $modulePath -Force
}

InModuleScope HvoSwitch {
    $script:testSwitchGuid = [guid]'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'

    Describe "New-HvoSwitch" {
        Context "When creating a new switch" {
            It "Should create an Internal type switch and return Name and Id" {
                $switchName = "new-internal-switch"
                $mockSwitch = [PSCustomObject]@{ Name = $switchName; Id = $script:testSwitchGuid }

                Mock New-VMSwitch -ParameterFilter {
                    $Name -eq $switchName -and $SwitchType -eq "Internal"
                } -MockWith { return $mockSwitch }

                $result = New-HvoSwitch -Name $switchName -Type "Internal"

                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be $switchName
                $result.Id | Should -Be $script:testSwitchGuid.ToString()
                Should -Invoke New-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $switchName -and $SwitchType -eq "Internal"
                }
            }

            It "Should create a Private type switch" {
                $switchName = "new-private-switch"
                $mockSwitch = [PSCustomObject]@{ Name = $switchName; Id = $script:testSwitchGuid }
                Mock New-VMSwitch -ParameterFilter { $Name -eq $switchName -and $SwitchType -eq "Private" } -MockWith { return $mockSwitch }
                $result = New-HvoSwitch -Name $switchName -Type "Private"
                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be $switchName
                $result.Id | Should -Not -BeNullOrEmpty
                Should -Invoke New-VMSwitch -Exactly -Times 1 -ParameterFilter { $Name -eq $switchName -and $SwitchType -eq "Private" }
            }

            It "Should create an External type switch with NetAdapterName" {
                $switchName = "new-external-switch"
                $netAdapterName = "Ethernet"
                $mockSwitch = [PSCustomObject]@{ Name = $switchName; Id = $script:testSwitchGuid }
                Mock New-VMSwitch -ParameterFilter {
                    $Name -eq $switchName -and $NetAdapterName -eq $netAdapterName -and $AllowManagementOS -eq $true
                } -MockWith { return $mockSwitch }
                $result = New-HvoSwitch -Name $switchName -Type "External" -NetAdapterName $netAdapterName
                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be $switchName
                Should -Invoke New-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $switchName -and $NetAdapterName -eq $netAdapterName -and $AllowManagementOS -eq $true
                }
            }

            It "Should throw an exception if External is created without NetAdapterName" {
                { New-HvoSwitch -Name "external-switch-no-adapter" -Type "External" } | Should -Throw "External switch requires -NetAdapterName"
            }

            It "Should apply notes if provided" {
                $switchName = "switch-with-notes"
                $notes = "Test switch notes"
                $mockSwitch = [PSCustomObject]@{ Name = $switchName; Id = $script:testSwitchGuid }
                Mock New-VMSwitch -MockWith { return $mockSwitch }
                Mock Set-VMSwitch -MockWith { }
                $result = New-HvoSwitch -Name $switchName -Type "Internal" -Notes $notes
                $result | Should -Not -BeNullOrEmpty
                Should -Invoke Set-VMSwitch -Exactly -Times 1 -ParameterFilter { $Name -eq $switchName -and $Notes -eq $notes }
            }
        }
    }

    Describe "Get-HvoSwitch" {
        Context "When the switch exists" {
            It "Should return the switch with Id" {
                $switchId = $script:testSwitchGuid
                $mockSwitch = [PSCustomObject]@{
                    Id = $switchId
                    Name = "test-switch"
                    SwitchType = "Internal"
                    Notes = "notes"
                }
                $mockSwitch.SwitchType | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return "Internal" } -Force

                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $mockSwitch }

                $result = Get-HvoSwitch -Id $switchId.ToString()

                $result | Should -Not -BeNullOrEmpty
                $result.Id | Should -Be $switchId.ToString()
                $result.Name | Should -Be "test-switch"
                Should -Invoke Get-VMSwitch -Exactly -Times 1 -ParameterFilter { $Id -eq $switchId }
            }
        }

        Context "When the switch does not exist" {
            It "Should return null" {
                $switchId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $null }
                $result = Get-HvoSwitch -Id $switchId.ToString()
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Describe "Get-HvoSwitchByName" {
        It "Should return an empty array when no switch matches" {
            Mock Get-VMSwitch -MockWith { return @() }
            $result = Get-HvoSwitchByName -Name "no-such-switch"
            if ($null -eq $result) { $result = @() }
            $result.Count | Should -Be 0
        }

        It "Should return switches matching the name" {
            $guid = [guid]::NewGuid()
            $mockSwitch = [PSCustomObject]@{ Id = $guid; Name = "lan"; SwitchType = "Internal"; Notes = $null }
            $mockSwitch.SwitchType | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return "Internal" } -Force
            Mock Get-VMSwitch -MockWith { return $mockSwitch }
            $result = Get-HvoSwitchByName -Name "lan"
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
            $result[0].Id | Should -Be $guid.ToString()
            $result[0].Name | Should -Be "lan"
        }
    }

    Describe "Get-HvoSwitches" {
        It "Should return the list of all switches with Id" {
            $guid1 = [guid]::NewGuid()
            $guid2 = [guid]::NewGuid()
            $mockSwitches = @(
                [PSCustomObject]@{ Id = $guid1; Name = "switch1"; SwitchType = "Internal"; Notes = "Notes 1" },
                [PSCustomObject]@{ Id = $guid2; Name = "switch2"; SwitchType = "External"; Notes = "Notes 2" }
            )
            $mockSwitches[0].SwitchType | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return "Internal" } -Force
            $mockSwitches[1].SwitchType | Add-Member -MemberType ScriptMethod -Name "ToString" -Value { return "External" } -Force

            Mock Get-VMSwitch -MockWith { return $mockSwitches }

            $result = Get-HvoSwitches

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].Id | Should -Be $guid1.ToString()
            $result[0].Name | Should -Be "switch1"
            $result[1].Id | Should -Be $guid2.ToString()
            $result[1].Name | Should -Be "switch2"
            Should -Invoke Get-VMSwitch -Exactly -Times 1
        }

        It "Should return an empty array if there are no switches" {
            Mock Get-VMSwitch -MockWith { return @() }
            $result = Get-HvoSwitches
            if ($null -eq $result) { $result = @() }
            $result.Count | Should -Be 0
        }
    }

    Describe "Set-HvoSwitch" {
        Context "When the switch does not exist" {
            It "Should return Updated = false with an error" {
                $switchId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $null }
                Mock Set-VMSwitch -MockWith { }
                $result = Set-HvoSwitch -Id $switchId.ToString() -Notes "New notes"
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Error | Should -Be "Switch not found"
                Should -Not -Invoke Set-VMSwitch
            }
        }

        Context "When the switch exists" {
            It "Should update notes" {
                $switchId = $script:testSwitchGuid
                $newNotes = "Updated notes"
                $mockSwitch = [PSCustomObject]@{ Id = $switchId; Name = "existing-switch" }
                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $mockSwitch }
                Mock Set-VMSwitch -MockWith { }
                $result = Set-HvoSwitch -Id $switchId.ToString() -Notes $newNotes
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                $result.Name | Should -Be "existing-switch"
                Should -Invoke Set-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq "existing-switch" -and $Notes -eq $newNotes
                }
            }

            It "Should return Updated = true even without modification if the switch exists" {
                $switchId = $script:testSwitchGuid
                $mockSwitch = [PSCustomObject]@{ Id = $switchId; Name = "existing-switch" }
                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $mockSwitch }
                Mock Set-VMSwitch -MockWith { }
                $result = Set-HvoSwitch -Id $switchId.ToString()
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                $result.Name | Should -Be "existing-switch"
                Should -Not -Invoke Set-VMSwitch
            }
        }

        Context "When an error occurs" {
            It "Should propagate the exception" {
                $switchId = $script:testSwitchGuid
                $mockSwitch = [PSCustomObject]@{ Id = $switchId; Name = "switch-with-error" }
                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $mockSwitch }
                Mock Set-VMSwitch -MockWith { throw "Test error" }
                { Set-HvoSwitch -Id $switchId.ToString() -Notes "Test" } | Should -Throw
            }
        }
    }

    Describe "Remove-HvoSwitch" {
        Context "When the switch does not exist" {
            It "Should return false" {
                $switchId = [guid]'00000000-0000-0000-0000-000000000001'
                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $null }
                Mock Remove-VMSwitch -MockWith { }
                $result = Remove-HvoSwitch -Id $switchId.ToString()
                $result | Should -Be $false
                Should -Not -Invoke Remove-VMSwitch
            }
        }

        Context "When the switch exists" {
            It "Should remove the switch" {
                $switchId = $script:testSwitchGuid
                $mockSwitch = [PSCustomObject]@{ Id = $switchId; Name = "existing-switch" }
                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $mockSwitch }
                Mock Remove-VMSwitch -MockWith { }
                $result = Remove-HvoSwitch -Id $switchId.ToString()
                $result | Should -Be $true
                Should -Invoke Remove-VMSwitch -Exactly -Times 1 -ParameterFilter { $Name -eq "existing-switch" }
            }

            It "Should return false if deletion fails" {
                $switchId = $script:testSwitchGuid
                $mockSwitch = [PSCustomObject]@{ Id = $switchId; Name = "switch-with-error" }
                Mock Get-VMSwitch -ParameterFilter { $Id -eq $switchId } -MockWith { return $mockSwitch }
                Mock Remove-VMSwitch -MockWith { throw "Cannot remove switch" }
                $result = Remove-HvoSwitch -Id $switchId.ToString()
                $result | Should -Be $false
            }
        }
    }
}
