# Unit tests for the HvoSwitch module
# Uses InModuleScope to test within the module context and allow mocks to work

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "../../src/modules/HvoSwitch/HvoSwitch.psd1"
    Import-Module $modulePath -Force
}

InModuleScope HvoSwitch {
    Describe "New-HvoSwitch" {
        Context "When the switch already exists" {
            It "Should return an object with Exists = true" {
                # Arrange
                $switchName = "existing-switch"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $mockSwitch }
                Mock New-VMSwitch -MockWith { }

                # Act
                $result = New-HvoSwitch -Name $switchName -Type "Internal"

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Exists | Should -Be $true
                $result.Name | Should -Be $switchName
                Should -Invoke Get-VMSwitch -Exactly -Times 1 -ParameterFilter { $Name -eq $switchName }
                Should -Not -Invoke New-VMSwitch
            }
        }

        Context "When the switch does not exist" {
            It "Should create an Internal type switch" {
                # Arrange
                $switchName = "new-internal-switch"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $null }
                Mock New-VMSwitch -ParameterFilter {
                    $Name -eq $switchName -and $SwitchType -eq "Internal"
                } -MockWith { return $mockSwitch }

                # Act
                $result = New-HvoSwitch -Name $switchName -Type "Internal"

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Exists | Should -Be $false
                $result.Name | Should -Be $switchName
                Should -Invoke New-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $switchName -and $SwitchType -eq "Internal"
                }
            }

            It "Should create a Private type switch" {
                # Arrange
                $switchName = "new-private-switch"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $null }
                Mock New-VMSwitch -ParameterFilter {
                    $Name -eq $switchName -and $SwitchType -eq "Private"
                } -MockWith { return $mockSwitch }

                # Act
                $result = New-HvoSwitch -Name $switchName -Type "Private"

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Exists | Should -Be $false
                $result.Name | Should -Be $switchName
                Should -Invoke New-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $switchName -and $SwitchType -eq "Private"
                }
            }

            It "Should create an External type switch with NetAdapterName" {
                # Arrange
                $switchName = "new-external-switch"
                $netAdapterName = "Ethernet"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $null }
                Mock New-VMSwitch -ParameterFilter {
                    $Name -eq $switchName -and
                    $NetAdapterName -eq $netAdapterName -and
                    $AllowManagementOS -eq $true
                } -MockWith { return $mockSwitch }

                # Act
                $result = New-HvoSwitch -Name $switchName -Type "External" -NetAdapterName $netAdapterName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Exists | Should -Be $false
                $result.Name | Should -Be $switchName
                Should -Invoke New-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $switchName -and
                    $NetAdapterName -eq $netAdapterName -and
                    $AllowManagementOS -eq $true
                }
            }

            It "Should throw an exception if External is created without NetAdapterName" {
                # Arrange
                $switchName = "external-switch-no-adapter"

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $null }

                # Act & Assert
                { New-HvoSwitch -Name $switchName -Type "External" } | Should -Throw "External switch requires -NetAdapterName"
            }

            It "Should apply notes if provided" {
                # Arrange
                $switchName = "switch-with-notes"
                $notes = "Test switch notes"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $null }
                Mock New-VMSwitch -MockWith { return $mockSwitch }
                Mock Set-VMSwitch -MockWith { }

                # Act
                $result = New-HvoSwitch -Name $switchName -Type "Internal" -Notes $notes

                # Assert
                $result | Should -Not -BeNullOrEmpty
                Should -Invoke Set-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $switchName -and $Notes -eq $notes
                }
            }
        }
    }

    Describe "Get-HvoSwitch" {
        Context "When the switch exists" {
            It "Should return the switch" {
                # Arrange
                $switchName = "test-switch"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                    SwitchType = "Internal"
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $mockSwitch }

                # Act
                $result = Get-HvoSwitch -Name $switchName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be $switchName
                Should -Invoke Get-VMSwitch -Exactly -Times 1 -ParameterFilter { $Name -eq $switchName }
            }
        }

        Context "When the switch does not exist" {
            It "Should return null" {
                # Arrange
                $switchName = "non-existent-switch"

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $null }

                # Act
                $result = Get-HvoSwitch -Name $switchName

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }
    }

    Describe "Get-HvoSwitches" {
        It "Should return the list of all switches" {
            # Arrange
            $mockSwitches = @(
                [PSCustomObject]@{
                    Name = "switch1"
                    SwitchType = "Internal"
                    Notes = "Notes 1"
                },
                [PSCustomObject]@{
                    Name = "switch2"
                    SwitchType = "External"
                    Notes = "Notes 2"
                }
            )

            Mock Get-VMSwitch -MockWith { return $mockSwitches }

            # Act
            $result = Get-HvoSwitches

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].Name | Should -Be "switch1"
            $result[1].Name | Should -Be "switch2"
            Should -Invoke Get-VMSwitch -Exactly -Times 1
        }

        It "Should return an empty array if there are no switches" {
            # Arrange
            Mock Get-VMSwitch -MockWith { return @() }

            # Act
            $result = Get-HvoSwitches

            # Assert
            # Select-Object on an empty array may return $null, so we accept both cases
            if ($null -eq $result) {
                $result = @()
            }
            $result.Count | Should -Be 0
        }
    }

    Describe "Set-HvoSwitch" {
        Context "When the switch does not exist" {
            It "Should return Updated = false with an error" {
                # Arrange
                $switchName = "non-existent-switch"

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $null }
                Mock Set-VMSwitch -MockWith { }

                # Act
                $result = Set-HvoSwitch -Name $switchName -Notes "New notes"

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $false
                $result.Error | Should -Be "Switch not found"
                Should -Not -Invoke Set-VMSwitch
            }
        }

        Context "When the switch exists" {
            It "Should update notes" {
                # Arrange
                $switchName = "existing-switch"
                $newNotes = "Updated notes"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $mockSwitch }
                Mock Set-VMSwitch -MockWith { }

                # Act
                $result = Set-HvoSwitch -Name $switchName -Notes $newNotes

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                $result.Name | Should -Be $switchName
                Should -Invoke Set-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $switchName -and $Notes -eq $newNotes
                }
            }

            It "Should return Updated = true even without modification if the switch exists" {
                # Arrange
                $switchName = "existing-switch"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $mockSwitch }
                Mock Set-VMSwitch -MockWith { }

                # Act
                $result = Set-HvoSwitch -Name $switchName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Updated | Should -Be $true
                $result.Name | Should -Be $switchName
                Should -Not -Invoke Set-VMSwitch
            }
        }

        Context "When an error occurs" {
            It "Should propagate the exception" {
                # Arrange
                $switchName = "switch-with-error"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $mockSwitch }
                Mock Set-VMSwitch -MockWith { throw "Test error" }

                # Act & Assert
                { Set-HvoSwitch -Name $switchName -Notes "Test" } | Should -Throw
            }
        }
    }

    Describe "Remove-HvoSwitch" {
        Context "When the switch does not exist" {
            It "Should return false" {
                # Arrange
                $switchName = "non-existent-switch"

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $null }
                Mock Remove-VMSwitch -MockWith { }

                # Act
                $result = Remove-HvoSwitch -Name $switchName

                # Assert
                $result | Should -Be $false
                Should -Not -Invoke Remove-VMSwitch
            }
        }

        Context "When the switch exists" {
            It "Should remove the switch" {
                # Arrange
                $switchName = "existing-switch"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $mockSwitch }
                Mock Remove-VMSwitch -MockWith { }

                # Act
                $result = Remove-HvoSwitch -Name $switchName

                # Assert
                $result | Should -Be $true
                Should -Invoke Remove-VMSwitch -Exactly -Times 1 -ParameterFilter {
                    $Name -eq $switchName -and $Force -eq $true
                }
            }

            It "Should return false if deletion fails" {
                # Arrange
                $switchName = "switch-with-error"
                $mockSwitch = [PSCustomObject]@{
                    Name = $switchName
                }

                Mock Get-VMSwitch -ParameterFilter { $Name -eq $switchName } -MockWith { return $mockSwitch }
                Mock Remove-VMSwitch -MockWith { throw "Cannot remove switch" }

                # Act
                $result = Remove-HvoSwitch -Name $switchName

                # Assert
                $result | Should -Be $false
            }
        }
    }
}
