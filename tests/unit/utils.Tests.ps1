# Unit tests for the utils module
# Uses InModuleScope to test within the module context

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "../../src/utils.psm1"
    Import-Module $modulePath -Force
}

InModuleScope utils {
    Describe "Get-HvoJsonBody" {
        Context "When WebEvent.Data exists" {
            It "Should return WebEvent.Data directly" {
                # Arrange
                $mockData = @{
                    Name = "test"
                    Value = 123
                }

                # Simulate WebEvent via a script variable in the module scope
                $script:WebEvent = [PSCustomObject]@{
                    Data = $mockData
                }

                # Act
                $result = Get-HvoJsonBody

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result | Should -Be $mockData
            }
        }

        Context "When WebEvent.Data does not exist but Request.Body exists" {
            It "Should parse JSON from Request.Body" {
                # Arrange
                $jsonString = '{"Name":"test","Value":123}'
                $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonString)

                $mockRequest = [PSCustomObject]@{
                    Body = $jsonBytes
                }

                $script:WebEvent = [PSCustomObject]@{
                    Data = $null
                    Request = $mockRequest
                }

                # Act
                $result = Get-HvoJsonBody

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be "test"
                $result.Value | Should -Be 123
            }
        }

        Context "When neither WebEvent.Data nor Request.Body exist" {
            It "Should return null" {
                # Arrange
                $script:WebEvent = [PSCustomObject]@{
                    Data = $null
                    Request = [PSCustomObject]@{
                        Body = $null
                    }
                }

                # Act
                $result = Get-HvoJsonBody

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When Request.Body contains invalid JSON" {
            It "Should return null without throwing an exception" {
                # Arrange
                $invalidJson = "not valid json"
                $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($invalidJson)

                $mockRequest = [PSCustomObject]@{
                    Body = $jsonBytes
                }

                $script:WebEvent = [PSCustomObject]@{
                    Data = $null
                    Request = $mockRequest
                }

                # Act
                $result = Get-HvoJsonBody

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }

        Context "When Request.Body is empty" {
            It "Should return null" {
                # Arrange
                $emptyBytes = [System.Text.Encoding]::UTF8.GetBytes("")

                $mockRequest = [PSCustomObject]@{
                    Body = $emptyBytes
                }

                $script:WebEvent = [PSCustomObject]@{
                    Data = $null
                    Request = $mockRequest
                }

                # Act
                $result = Get-HvoJsonBody

                # Assert
                $result | Should -BeNullOrEmpty
            }
        }
    }
}
