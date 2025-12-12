# Prerequisites check and installation script
# This script checks if the Pode module is installed and installs it if necessary

param(
    [switch]$SkipInstall,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Test-PodeInstalled {
    <#
    .SYNOPSIS
    Checks if the Pode module is installed.

    .DESCRIPTION
    Checks for the presence of the Pode module in available PowerShell modules.

    .OUTPUTS
    [bool] True if Pode is installed, False otherwise.
    #>

    try {
        $podeModule = Get-Module -ListAvailable -Name 'Pode' -ErrorAction SilentlyContinue
        return $null -ne $podeModule
    }
    catch {
        return $false
    }
}

function Get-PodeVersion {
    <#
    .SYNOPSIS
    Retrieves the installed version of Pode.

    .OUTPUTS
    [string] Pode version or $null if not installed.
    #>

    try {
        $podeModule = Get-Module -ListAvailable -Name 'Pode' -ErrorAction SilentlyContinue
        if ($null -ne $podeModule) {
            return $podeModule.Version.ToString()
        }
        return $null
    }
    catch {
        return $null
    }
}

function Install-PodeModule {
    <#
    .SYNOPSIS
    Installs the Pode module from PowerShell Gallery.

    .DESCRIPTION
    Installs the Pode module using Install-Module from PowerShell Gallery.
    Handles errors and displays informative messages.
    #>

    Write-Host "Installing Pode module..." -ForegroundColor Cyan

    try {
        # Check if PowerShellGet is available
        $psGetModule = Get-Module -ListAvailable -Name 'PowerShellGet'
        if ($null -eq $psGetModule) {
            Write-Host "PowerShellGet is not available. Installing..." -ForegroundColor Yellow
            Install-Module -Name 'PowerShellGet' -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        }

        # Install Pode
        $installParams = @{
            Name          = 'Pode'
            Repository    = 'PSGallery'
            Scope         = 'CurrentUser'
            Force         = $Force
            AllowClobber  = $true
            ErrorAction   = 'Stop'
        }

        Install-Module @installParams

        Write-Host "Pode module installed successfully." -ForegroundColor Green

        # Verify installation
        $installedVersion = Get-PodeVersion
        if ($null -ne $installedVersion) {
            Write-Host "Installed version: $installedVersion" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "Error installing Pode: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Ensure you have the necessary permissions and that PowerShell Gallery is accessible." -ForegroundColor Yellow
        throw
    }
}

# Main script
try {
    Write-Host "=== Prerequisites Check ===" -ForegroundColor Cyan
    Write-Host ""

    # Check if Pode is installed
    $isPodeInstalled = Test-PodeInstalled

    if ($isPodeInstalled) {
        $podeVersion = Get-PodeVersion
        Write-Host "✓ Pode module is installed" -ForegroundColor Green
        if ($null -ne $podeVersion) {
            Write-Host "  Version: $podeVersion" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "All prerequisites are satisfied." -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "✗ Pode module is not installed" -ForegroundColor Red
        Write-Host ""

        if ($SkipInstall) {
            Write-Host "Option -SkipInstall enabled. Installation skipped." -ForegroundColor Yellow
            Write-Host "To install Pode manually, run:" -ForegroundColor Yellow
            Write-Host "  Install-Module -Name Pode -Scope CurrentUser" -ForegroundColor Gray
            exit 1
        }

        # Ask for confirmation if not in silent mode
        if (-not $Force) {
            Write-Host "The Pode module is required to run the server." -ForegroundColor Yellow
            $confirmation = Read-Host "Do you want to install Pode now? (Y/N)"
            if ($confirmation -notmatch '^[OoYy]') {
                Write-Host "Installation cancelled." -ForegroundColor Yellow
                exit 1
            }
        }

        # Install Pode
        Install-PodeModule

        Write-Host ""
        Write-Host "=== Check completed ===" -ForegroundColor Green
        Write-Host "All prerequisites are now satisfied." -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Host ""
    Write-Host "=== Error during check ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
