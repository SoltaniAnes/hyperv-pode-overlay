# Automatic OpenAPI file generation script
# This script retrieves OpenAPI specifications from the Pode server
# and saves them to the /docs/ folder

param(
    [int]$Port = 8080,
    [string]$ListenAddress = 'localhost',
    [int]$TimeoutSeconds = 30,
    [switch]$ForceRestart
)

$ErrorActionPreference = 'Stop'

# Determine project root path (one level above src/scripts/)
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ServerScript = Join-Path $ProjectRoot 'src' 'server.ps1'
$DocsDir = Join-Path $ProjectRoot 'docs'
$OpenApiJsonPath = Join-Path $DocsDir 'openapi.json'
$OpenApiYamlPath = Join-Path $DocsDir 'openapi.yaml'

# OpenAPI endpoint URLs
$BaseUrl = "http://${ListenAddress}:${Port}"
$OpenApiJsonUrl = "${BaseUrl}/openapi.json"
$OpenApiYamlUrl = "${BaseUrl}/openapi.yaml"
$HealthUrl = "${BaseUrl}/health"

# Variable to track if the server was started by this script
$ServerStartedByScript = $false
$ServerJob = $null

# Detect if running in non-interactive mode (e.g., via pre-commit)
# Check for NonInteractive flag in command line arguments
$commandLineArgs = [Environment]::GetCommandLineArgs()
$IsNonInteractive = $commandLineArgs -contains '-NonInteractive' -or
                    $commandLineArgs -contains '-NoProfile'

# Wrapper function for Write-Host that disables colors in non-interactive mode
function Write-Message {
    param(
        [string]$Message,
        [string]$ForegroundColor = 'White',
        [switch]$NoNewline
    )

    if ($IsNonInteractive) {
        # In non-interactive mode, write directly to console output without colors
        # to avoid ANSI sequences that can cause character overlap issues in terminals
        # Use [Console]::Out to avoid polluting the pipeline
        if ($NoNewline) {
            [Console]::Out.Write($Message)
        } else {
            [Console]::Out.WriteLine($Message)
        }
    } else {
        # In interactive mode, use Write-Host with colors
        if ($NoNewline) {
            Write-Host $Message -ForegroundColor $ForegroundColor -NoNewline
        } else {
            Write-Host $Message -ForegroundColor $ForegroundColor
        }
    }
}

function Test-ServerRunning {
    param([string]$Url)

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Wait-ForServer {
    param(
        [string]$Url,
        [int]$MaxWaitSeconds = 30,
        [System.Management.Automation.Job]$Job = $null
    )

    $startTime = Get-Date
    $elapsed = 0

    Write-Message "Waiting for server to be ready..." -ForegroundColor Yellow

    while ($elapsed -lt $MaxWaitSeconds) {
        # Check job state if provided
        if ($null -ne $Job) {
            $jobInfo = Get-Job -Id $Job.Id -ErrorAction SilentlyContinue
            if ($null -ne $jobInfo) {
                $jobState = $jobInfo.State
                if ($jobState -eq 'Failed') {
                    Write-Message ""
                    Write-Message "Server failed in job:" -ForegroundColor Red

                    # Display job errors
                    $jobErrors = $jobInfo.Error
                    if ($jobErrors) {
                        Write-Message "Captured exceptions:" -ForegroundColor Yellow
                        foreach ($jobError in $jobErrors) {
                            Write-Message "  Message: $($jobError.Exception.Message)" -ForegroundColor Red
                            Write-Message "  Type: $($jobError.Exception.GetType().FullName)" -ForegroundColor Gray
                            if ($jobError.Exception.InnerException) {
                                Write-Message "  InnerException: $($jobError.Exception.InnerException.Message)" -ForegroundColor Gray
                            }
                        }
                    }

                    # Retrieve output
                    $jobOutput = Receive-Job -Job $Job -ErrorAction SilentlyContinue
                    if ($jobOutput) {
                        Write-Message ""
                        Write-Message "Server output:" -ForegroundColor Yellow
                        $jobOutput | ForEach-Object {
                            Write-Message "  $_" -ForegroundColor Gray
                        }
                    }

                    return $false
                }
            }
        }

        if (Test-ServerRunning -Url $Url) {
            Write-Message "Server ready!" -ForegroundColor Green
            return $true
        }

        Start-Sleep -Seconds 1
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        Write-Message "  Waiting... (${elapsed}s/${MaxWaitSeconds}s)" -ForegroundColor Gray
    }

    # If timeout is reached, display job logs for debugging
    if ($null -ne $Job) {
        $jobOutput = Receive-Job -Job $Job -ErrorAction SilentlyContinue
        if ($jobOutput) {
            Write-Message ""
            Write-Message "Server output (last lines):" -ForegroundColor Yellow
            $jobOutput | Select-Object -Last 10 | ForEach-Object {
                Write-Message "  $_" -ForegroundColor Gray
            }
        }
    }

    return $false
}

function Start-TemporaryServer {
    Write-Message "Starting Pode server temporarily..." -ForegroundColor Cyan

    # Start server in background as a PowerShell job
    $ServerJob = Start-Job -ScriptBlock {
        param($ServerScriptPath)

        # Redirect errors to output to capture them
        $ErrorActionPreference = 'Continue'

        try {
            Set-Location (Split-Path -Parent $ServerScriptPath)
            & $ServerScriptPath 2>&1
        }
        catch {
            Write-Error "Error in job: $($_.Exception.Message)"
            Write-Error $_.ScriptStackTrace
            $errorDetails = $_.Exception | Format-List -Force | Out-String
            Write-Output $errorDetails
            throw
        }
    } -ArgumentList $ServerScript

    if ($null -eq $ServerJob) {
        throw "Unable to start server"
    }

    Write-Message "Server started (Job ID: $($ServerJob.Id))" -ForegroundColor Green

    # Wait a bit to see if the job fails immediately
    Start-Sleep -Seconds 2

    # Check job state
    $jobInfo = Get-Job -Id $ServerJob.Id
    $jobState = $jobInfo.State

    if ($jobState -eq 'Failed') {
        Write-Message "Error starting server:" -ForegroundColor Red

        # Retrieve job errors
        $jobErrors = $jobInfo.Error
        if ($jobErrors) {
            Write-Message ""
            Write-Message "Captured exceptions:" -ForegroundColor Yellow
            foreach ($jobError in $jobErrors) {
                Write-Message "  Message: $($jobError.Exception.Message)" -ForegroundColor Red
                Write-Message "  Type: $($jobError.Exception.GetType().FullName)" -ForegroundColor Gray
                if ($jobError.Exception.InnerException) {
                    Write-Message "  InnerException: $($jobError.Exception.InnerException.Message)" -ForegroundColor Gray
                }
                if ($jobError.ScriptStackTrace) {
                    Write-Message "  StackTrace: $($jobError.ScriptStackTrace)" -ForegroundColor Gray
                }
            }
        }

        # Retrieve standard output and errors
        $jobOutput = Receive-Job -Job $ServerJob -ErrorAction SilentlyContinue -ErrorVariable jobReceiveErrors
        if ($jobOutput) {
            Write-Message ""
            Write-Message "Server output:" -ForegroundColor Yellow
            $jobOutput | ForEach-Object {
                Write-Message "  $_" -ForegroundColor Gray
            }
        }

        # Display receive errors if present
        if ($jobReceiveErrors) {
            Write-Message ""
            Write-Message "Errors receiving logs:" -ForegroundColor Yellow
            $jobReceiveErrors | ForEach-Object {
                Write-Message "  $_" -ForegroundColor Gray
            }
        }

        Remove-Job -Job $ServerJob -Force -ErrorAction SilentlyContinue
        throw "Server could not start. Check the logs above."
    }

    return $ServerJob
}

function Stop-TemporaryServer {
    param(
        [System.Management.Automation.Job]$Job
    )

    if ($null -ne $Job -and $Job -is [System.Management.Automation.Job]) {
        Write-Message "Stopping temporary server..." -ForegroundColor Cyan
        Stop-Job -Job $Job -ErrorAction SilentlyContinue
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
        Write-Message "Server stopped" -ForegroundColor Green
    }
}

function Convert-JsonToYaml {
    <#
    .SYNOPSIS
    Convertit un objet JSON en format YAML.

    .DESCRIPTION
    Convertit un objet PowerShell (désérialisé depuis JSON) en format YAML.
    Utilise une conversion récursive simple.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$JsonObject,

        [int]$IndentLevel = 0
    )

    $indent = '  ' * $IndentLevel
    $result = @()

    if ($null -eq $JsonObject) {
        return 'null'
    }

    $type = $JsonObject.GetType()

    if ($type.Name -eq 'PSCustomObject' -or $type.Name -eq 'Hashtable') {
        $properties = if ($JsonObject -is [hashtable]) {
            $JsonObject.Keys | Sort-Object
        } else {
            $JsonObject.PSObject.Properties.Name | Sort-Object
        }

        foreach ($prop in $properties) {
            $value = if ($JsonObject -is [hashtable]) {
                $JsonObject[$prop]
            } else {
                $JsonObject.$prop
            }

            $yamlValue = Convert-JsonToYaml -JsonObject $value -IndentLevel ($IndentLevel + 1)

            if ($yamlValue -match "`n" -or ($yamlValue -is [array])) {
                $result += "$indent$prop`:"
                $result += $yamlValue
            } else {
                $result += "$indent$prop`: $yamlValue"
            }
        }
    }
    elseif ($JsonObject -is [array]) {
        foreach ($item in $JsonObject) {
            $yamlValue = Convert-JsonToYaml -JsonObject $item -IndentLevel $IndentLevel
            if ($yamlValue -match "`n") {
                $result += "$indent-"
                $result += ($yamlValue -split "`n" | ForEach-Object { "  $_" })
            } else {
                $result += "$indent- $yamlValue"
            }
        }
    }
    elseif ($JsonObject -is [string]) {
        # Échapper les chaînes si nécessaire
        if ($JsonObject -match '[:|>|#|\[|\]|{|}|&|\*|!|%|@|`|''|"|\n|\r') {
            return "'$($JsonObject -replace "'", "''")'"
        }
        return $JsonObject
    }
    elseif ($JsonObject -is [bool]) {
        return $JsonObject.ToString().ToLower()
    }
    else {
        return $JsonObject.ToString()
    }

    # Joindre les lignes et supprimer les espaces en fin de ligne
    $yamlContent = $result -join "`n"
    # Supprimer les espaces en fin de ligne (trailing whitespace)
    $yamlContent = ($yamlContent -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n"
    return $yamlContent
}

function Get-OpenApiFile {
    param(
        [string]$Url,
        [string]$OutputPath
    )

    Write-Message "Retrieving $Url..." -ForegroundColor Cyan

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop

        # Create destination directory if it doesn't exist
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            Write-Message "Directory created: $outputDir" -ForegroundColor Gray
        }

        # Convertir le contenu en chaîne si c'est un tableau d'octets
        if ($response.Content -is [byte[]]) {
            $content = [System.Text.Encoding]::UTF8.GetString($response.Content)
        } else {
            $content = $response.Content.ToString()
        }

        # Si c'est un fichier YAML et que le contenu semble être du JSON ou mal formaté, convertir depuis JSON
        if ($OutputPath -like '*.yaml' -or $OutputPath -like '*.yml') {
            # Vérifier si le contenu est du JSON (commence par { ou [)
            if ($content.TrimStart() -match '^[\s]*[{\[]') {
                Write-Message "Converting JSON to YAML..." -ForegroundColor Yellow
                try {
                    $jsonObject = $content | ConvertFrom-Json
                    $content = Convert-JsonToYaml -JsonObject $jsonObject
                }
                catch {
                    Write-Message "Warning: Failed to convert JSON to YAML, saving as-is: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            # Vérifier si le contenu semble être des codes ASCII (commence par des nombres)
            elseif ($content -match '^\d+\s+\d+') {
                Write-Message "Detected ASCII codes, converting from JSON instead..." -ForegroundColor Yellow
                # Récupérer le JSON et convertir
                $jsonUrl = $Url -replace '\.yaml$', '.json' -replace '\.yml$', '.json'
                try {
                    $jsonResponse = Invoke-WebRequest -Uri $jsonUrl -Method Get -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
                    $jsonObject = $jsonResponse.Content | ConvertFrom-Json
                    $content = Convert-JsonToYaml -JsonObject $jsonObject
                }
                catch {
                    Write-Message "Error: Could not retrieve JSON for conversion: $($_.Exception.Message)" -ForegroundColor Red
                    return $false
                }
            }
        }

        # Supprimer les espaces en fin de ligne (trailing whitespace)
        $content = ($content -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n"

        # Ajouter une ligne vide à la fin si elle n'existe pas déjà
        if (-not $content.EndsWith("`n")) {
            $content += "`n"
        }

        # Save file with UTF-8 encoding
        [System.IO.File]::WriteAllText($OutputPath, $content, [System.Text.Encoding]::UTF8)

        Write-Message "File saved: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Message "Error retrieving $Url : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main script
try {
    Write-Message "=== OpenAPI File Generation ===" -ForegroundColor Cyan
    Write-Message "Project directory: $ProjectRoot" -ForegroundColor Gray
    Write-Message "Documentation directory: $DocsDir" -ForegroundColor Gray
    Write-Message ""

    # Check if server is already running
    $serverRunning = Test-ServerRunning -Url $HealthUrl

    if ($serverRunning -and -not $ForceRestart) {
        Write-Message "Server is already running on $BaseUrl" -ForegroundColor Green
    }
    else {
        if ($ForceRestart -and $serverRunning) {
            Write-Message "Forcing server restart..." -ForegroundColor Yellow
            # Note: Cannot stop a Pode server already running from outside
            # Assume it will be restarted manually or managed by another process
        }

        # Start server temporarily
        $ServerJob = Start-TemporaryServer
        $ServerStartedByScript = $true

        # Wait for server to be ready
        if (-not (Wait-ForServer -Url $HealthUrl -MaxWaitSeconds $TimeoutSeconds -Job $ServerJob)) {
            throw "Server did not respond within timeout ($TimeoutSeconds seconds)"
        }
    }

    # Retrieve OpenAPI files
    Write-Message ""
    $jsonSuccess = Get-OpenApiFile -Url $OpenApiJsonUrl -OutputPath $OpenApiJsonPath
    $yamlSuccess = Get-OpenApiFile -Url $OpenApiYamlUrl -OutputPath $OpenApiYamlPath

    if (-not $jsonSuccess -or -not $yamlSuccess) {
        throw "Failed to retrieve OpenAPI files"
    }

    Write-Message ""
    Write-Message "=== Generation completed successfully ===" -ForegroundColor Green
    Write-Message "Generated files:" -ForegroundColor Green
    Write-Message "  - $OpenApiJsonPath" -ForegroundColor Gray
    Write-Message "  - $OpenApiYamlPath" -ForegroundColor Gray
}
catch {
    Write-Message ""
    Write-Message "=== Error during generation ===" -ForegroundColor Red
    Write-Message $_.Exception.Message -ForegroundColor Red

    # Display job logs if available
    if ($null -ne $ServerJob) {
        $jobInfo = Get-Job -Id $ServerJob.Id -ErrorAction SilentlyContinue
        if ($null -ne $jobInfo) {
            Write-Message ""
            Write-Message "Job state: $($jobInfo.State)" -ForegroundColor Yellow

            # Display job errors
            $jobErrors = $jobInfo.Error
            if ($jobErrors) {
                Write-Message ""
                Write-Message "Captured exceptions:" -ForegroundColor Yellow
                foreach ($jobError in $jobErrors) {
                    Write-Message "  Message: $($jobError.Exception.Message)" -ForegroundColor Red
                    Write-Message "  Type: $($jobError.Exception.GetType().FullName)" -ForegroundColor Gray
                    if ($jobError.Exception.InnerException) {
                        Write-Message "  InnerException: $($jobError.Exception.InnerException.Message)" -ForegroundColor Gray
                    }
                    if ($jobError.ScriptStackTrace) {
                        Write-Message "  StackTrace: $($jobError.ScriptStackTrace)" -ForegroundColor Gray
                    }
                }
            }

            # Retrieve output
            $jobOutput = Receive-Job -Job $ServerJob -ErrorAction SilentlyContinue
            if ($jobOutput) {
                Write-Message ""
                Write-Message "Server logs:" -ForegroundColor Yellow
                $jobOutput | ForEach-Object {
                    Write-Message "  $_" -ForegroundColor Gray
                }
            }
        }
    }

    exit 1
}
finally {
    # Cleanup: stop server if we started it
    if ($ServerStartedByScript) {
        Write-Message ""
        Stop-TemporaryServer -Job $ServerJob
    }
}
