# Tests

This directory contains unit tests for the project.

## Structure

```text
tests/
├── unit/                  # Unit tests for PowerShell modules
│   ├── HvoVm.Tests.ps1
│   ├── HvoSwitch.Tests.ps1
│   └── utils.Tests.ps1
├── run-tests.ps1          # Test execution script
└── analyze-coverage.ps1   # Coverage analysis script
```

## Prerequisites

- PowerShell 7
- Pester module (version 5.x recommended)

Install Pester:

```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
```

## Running Tests

### All unit tests

```powershell
.\tests\run-tests.ps1
```

### Unit tests only

```powershell
Invoke-Pester -Path tests/unit/
```

### With code coverage

```powershell
.\tests\run-tests.ps1 -Coverage
```

After running tests with coverage, analyze the results:

```powershell
.\tests\analyze-coverage.ps1
```

Or using Pester directly:

```powershell
$config = New-PesterConfiguration
$config.Run.Path = 'tests/unit/'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(
    'src/modules/**/*.psm1',
    'src/utils.psm1'
)
$config.CodeCoverage.OutputFormat = 'CoverageGutters'
Invoke-Pester -Configuration $config
```

## Tested Functions

### HvoVm Module

- `New-HvoVm` - Create a new virtual machine
- `Get-HvoVm` - Get a single VM by name
- `Get-HvoVms` - Get all VMs
- `Set-HvoVm` - Update VM configuration (memory, vCPU, switch, ISO)
- `Start-HvoVm` - Start a VM
- `Stop-HvoVm` - Stop a VM
- `Restart-HvoVm` - Restart a VM
- `Suspend-HvoVm` - Suspend a VM
- `Resume-HvoVm` - Resume a suspended VM
- `Remove-HvoVm` - Remove a VM

### HvoSwitch Module

- `New-HvoSwitch` - Create a new virtual switch
- `Get-HvoSwitch` - Get a single switch by name
- `Get-HvoSwitches` - Get all switches
- `Set-HvoSwitch` - Update switch configuration (notes)
- `Remove-HvoSwitch` - Remove a switch

### Utils Module

- `Get-HvoJsonBody` - Parse JSON from WebEvent request body

## Writing Tests

### Pester Test Structure

```powershell
Describe "Get-HvoVm" {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot "../../src/modules/HvoVm/HvoVm.psd1"
        Import-Module $modulePath -Force
    }

    InModuleScope HvoVm {
        Context "When the VM exists" {
            It "Should return the VM details" {
                # Arrange
                $vmName = "test-vm"
                $mockVm = [PSCustomObject]@{
                    Name = $vmName
                    State = "Running"
                }
                Mock Get-VM -ParameterFilter { $Name -eq $vmName } -MockWith { return $mockVm }

                # Act
                $result = Get-HvoVm -Name $vmName

                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be $vmName
            }
        }
    }
}
```

## Code Coverage

### Current Coverage Status

Run the coverage analysis script to see detailed coverage:

```powershell
.\tests\analyze-coverage.ps1
```

Current coverage (as of last test run):

- **Overall**: 93.9% (279/297 instructions)
- **HvoSwitch module**: 100% (38/38 instructions)
- **HvoVm module**: 92.8% (233/251 instructions)
- **Utils module**: 100% (8/8 instructions)

### Coverage by Function Type

**Critical functions** (VM lifecycle):

- `New-HvoVm`: 100%
- `Start-HvoVm`: 96.8%
- `Remove-HvoVm`: 95.8%
- `Suspend-HvoVm`: 94.7%
- `Stop-HvoVm`: 92.3%
- `Restart-HvoVm`: 92%
- `Resume-HvoVm`: 90.5%

**Business logic modules**: 96.4% average (HvoVm + HvoSwitch)

**Utility code**: 100%

### Coverage Goals

Target coverage levels:

- **Critical code** (VM creation/deletion, lifecycle actions): > 90% (currently 94.6%) ✓
- **Business logic** (HvoVm, HvoSwitch modules): > 80% (currently 96.4%) ✓
- **Utility code**: > 60% (currently 100%) ✓
- **Overall**: > 75% (currently 93.9%) ✓

## CI/CD

Tests are automatically executed in GitHub Actions on each Pull Request.
