# src/modules/HvoOpenApi/HvoOpenApi.psm1

function Get-HvoOpenApiSpec {
    param(
        [string]$RoutesPath = "$PSScriptRoot/../routes",
        [string]$BaseUrl = "http://localhost:8080",
        [switch]$Quiet
    )

    $spec = @{
        openapi = "3.0.3"
        info = @{
            title = "Hyper-V API Overlay"
            description = "REST API layer on top of Microsoft Hyper-V using PowerShell and Pode"
            version = "1.0.0"
        }
        servers = @(
            @{
                url = $BaseUrl
                description = "Hyper-V Host API Server"
            }
        )
        paths = @{}
        components = @{
            schemas = @{}
            responses = @{}
        }
    }

    # Add base schemas and responses
    Add-HvoOpenApiSchemas -Spec $spec
    Add-HvoOpenApiResponses -Spec $spec

    # Parse route files
    # Normalize path
    try {
        if ([System.IO.Path]::IsPathRooted($RoutesPath)) {
            $routesPathResolved = [System.IO.Path]::GetFullPath($RoutesPath)
        } else {
            $routesPathResolved = Resolve-Path $RoutesPath -ErrorAction Stop
            $routesPathResolved = $routesPathResolved.Path
        }
        
        # Check that the path exists
        if (-not (Test-Path $routesPathResolved)) {
            Write-Warning "Routes path does not exist: $routesPathResolved (original: $RoutesPath)"
            return $spec
        }
        
        # Check that it's a directory
        if (-not (Test-Path $routesPathResolved -PathType Container)) {
            Write-Warning "Routes path is not a directory: $routesPathResolved"
            return $spec
        }
    }
    catch {
        Write-Warning "Failed to resolve routes path: $RoutesPath - $($_.Exception.Message)"
        return $spec
    }

    $routeFiles = Get-ChildItem -Path $routesPathResolved -Filter "*.ps1" -ErrorAction SilentlyContinue
    
    if (-not $routeFiles) {
        if (-not $Quiet) {
            Write-Warning "No route files found in: $routesPathResolved"
        }
        return $spec
    }
    
    if (-not $Quiet) {
        Write-Host "Processing $($routeFiles.Count) route file(s) from: $routesPathResolved" -ForegroundColor Cyan
    }
    
    foreach ($file in $routeFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                # Count @openapi occurrences in the file
                $openapiCount = ([regex]::Matches($content, '@openapi')).Count
                if (-not $Quiet) {
                    Write-Host "  File: $($file.Name) - @openapi markers: $openapiCount" -ForegroundColor Gray
                }
                
                $routes = Get-HvoOpenApiRoutes -Content $content -FilePath $file.FullName -Quiet:$Quiet
                
                if ($routes.Count -eq 0) {
                    if (-not $Quiet) {
                        Write-Warning "  No routes parsed from: $($file.Name) (found $openapiCount @openapi markers)"
                    }
                } else {
                    if (-not $Quiet) {
                        Write-Host "  Found $($routes.Count) route(s) in $($file.Name)" -ForegroundColor Green
                    }
                }
                
                foreach ($route in $routes) {
                    $path = $route.path
                    $method = $route.method.ToLower()
                    
                    if ($path -and $method) {
                        if (-not $spec.paths[$path]) {
                            $spec.paths[$path] = @{}
                        }
                        
                        # Normalize tags to ensure they are always arrays
                        if ($route.spec -and $route.spec.ContainsKey('tags')) {
                            $tagsValue = $route.spec['tags']
                            if ($tagsValue -isnot [array]) {
                                # Convert to array if not already an array
                                $route.spec['tags'] = @($tagsValue)
                            }
                        }
                        
                        $spec.paths[$path][$method] = $route.spec
                    } else {
                        Write-Warning "Route missing path or method in file: $($file.Name) - path: $($route.path), method: $($route.method)"
                    }
                }
            }
        }
        catch {
            Write-Warning "Error parsing route file $($file.FullName): $($_.Exception.Message)"
        }
    }

    return $spec
}

function Get-HvoOpenApiRoutes {
    param(
        [string]$Content,
        [string]$FilePath,
        [switch]$Quiet
    )

    $routes = @()
    $lines = $Content -split "`r?`n"
    $i = 0
    
    while ($i -lt $lines.Length) {
        # Search for @openapi marker (simplified pattern)
        $line = $lines[$i]
        if ($line -match '@openapi') {
            if (-not $Quiet) {
                Write-Host "    Found @openapi at line $($i+1) in $([System.IO.Path]::GetFileName($FilePath))" -ForegroundColor Yellow
            }
            $route = @{
                path = $null
                method = $null
                spec = @{}
            }
            
            $i++
            $commentBlock = @()
            
            # Collect comment block while preserving relative indentation
            $baseIndent = $null
            while ($i -lt $lines.Length -and ($lines[$i] -match '^\s*#' -or $lines[$i].Trim() -eq '')) {
                if ($lines[$i] -match '^\s*#\s*(.+)') {
                    $fullLine = $lines[$i]
                    $commentContent = $matches[1]
                    # Preserve relative indentation after #
                    $hashPos = $fullLine.IndexOf('#')
                    $afterHash = $fullLine.Substring($hashPos + 1)
                    # Count spaces after #
                    $spacesAfterHash = 0
                    while ($spacesAfterHash -lt $afterHash.Length -and $afterHash[$spacesAfterHash] -eq ' ') {
                        $spacesAfterHash++
                    }
                    # If this is the first non-empty line, it's the base indentation
                    if ($null -eq $baseIndent -and $commentContent.Trim()) {
                        $baseIndent = $spacesAfterHash
                    }
                    # Build line with preserved relative indentation
                    if ($null -ne $baseIndent -and $spacesAfterHash -gt $baseIndent) {
                        $relativeIndent = $spacesAfterHash - $baseIndent
                        $commentLine = (' ' * $relativeIndent) + $commentContent.TrimStart()
                    } else {
                        $commentLine = $commentContent.TrimStart()
                    }
                    if ($commentLine) {
                        $commentBlock += $commentLine
                    }
                }
                $i++
            }
            
            # Parse YAML comments (with protection against hangs)
            if ($commentBlock.Count -gt 0) {
                try {
                    $yamlContent = $commentBlock -join "`n"
                    if (-not $Quiet) {
                        Write-Host "    Parsing YAML block ($($commentBlock.Count) lines)..." -ForegroundColor Gray
                    }
                    
                    # Limit YAML size to avoid hangs
                    if ($commentBlock.Count -gt 100) {
                        if (-not $Quiet) {
                            Write-Warning "    YAML block too large ($($commentBlock.Count) lines), skipping"
                        }
                        $route.spec = @{}
                    } else {
                        $route.spec = Convert-HvoOpenApiYaml -YamlContent $yamlContent
                        if (-not $Quiet) {
                            Write-Host "    YAML parsed successfully" -ForegroundColor Gray
                        }
                        
                        # Fix parsed structure (extract responses, convert required, etc.)
                        $route.spec = Repair-HvoOpenApiSpecStructure -Spec $route.spec
                    }
                    
                    # Extract path and method from parsed spec (priority)
                    # Check first at root level
                    if ($route.spec -and $route.spec.ContainsKey('path')) {
                        $route.path = $route.spec['path']
                        $route.spec.Remove('path')
                    }
                    if ($route.spec -and $route.spec.ContainsKey('method')) {
                        $route.method = $route.spec['method']
                        $route.spec.Remove('method')
                    }
                    
                    # Debug: display what was parsed
                    if (-not $route.path -or -not $route.method) {
                        if (-not $Quiet) {
                            Write-Host "    Warning: Missing path or method after parsing. Path: $($route.path), Method: $($route.method)" -ForegroundColor Yellow
                            if ($route.spec) {
                                Write-Host "    Parsed spec keys: $($route.spec.Keys -join ', ')" -ForegroundColor Yellow
                            }
                        }
                    }
                }
                catch {
                    if (-not $Quiet) {
                        Write-Host "    Error parsing YAML: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    $route.spec = @{}
                }
            }
            
            # If path or method are missing, search in Add-PodeRoute (fallback)
            if (-not $route.path -or -not $route.method) {
                if (-not $Quiet) {
                    Write-Host "    Searching for Add-PodeRoute..." -ForegroundColor Gray
                }
                $maxSearchLines = 50  # Limit to avoid infinite loops
                $searchCount = 0
                $foundRoute = $false
                while ($i -lt $lines.Length -and $searchCount -lt $maxSearchLines -and -not $foundRoute) {
                    # More flexible pattern to match Add-PodeRoute
                    if ($lines[$i] -match "Add-PodeRoute\s+-Method\s+(\w+)\s+-Path\s+['""]([^'""]+)['""]") {
                        if (-not $route.method) {
                            $route.method = $matches[1]
                        }
                        if (-not $route.path) {
                            $route.path = $matches[2] -replace ':(\w+)', '{$1}'  # Convert :name to {name}
                        }
                        if (-not $Quiet) {
                            Write-Host "    Found Add-PodeRoute: $($route.method) $($route.path)" -ForegroundColor Green
                        }
                        $foundRoute = $true
                        break
                    }
                    # Also check if we encounter another @openapi (end of this block)
                    if ($lines[$i] -match '@openapi') {
                        break
                    }
                    $i++
                    $searchCount++
                }
                if (-not $foundRoute -and -not $Quiet) {
                    Write-Host "    Add-PodeRoute not found within $maxSearchLines lines" -ForegroundColor Yellow
                }
            }
            
            if ($route.path -and $route.method) {
                if (-not $Quiet) {
                    Write-Host "    Adding route: $($route.method) $($route.path)" -ForegroundColor Green
                }
                $routes += $route
            } else {
                if (-not $Quiet) {
                    Write-Host "    Skipping route: missing path or method" -ForegroundColor Red
                }
            }
        }
        $i++
    }
    
    return $routes
}

function Convert-HvoOpenApiYaml {
    param([string]$YamlContent)
    
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($YamlContent)) {
        return $result
    }
    
    try {
        $lines = $YamlContent -split "`r?`n"
        $stack = @()
        $current = $result
        $currentIsArray = $false
        $maxLines = 500
        $lineCount = 0
        
        # First pass: detect keys that should be arrays
        # Store the key name and its relative indentation
        $arrayKeys = @{}
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }
            
            $indent = $line.Length - $line.TrimStart().Length
            $content = $line.TrimStart()
            
            # If we see a key without value followed by an array element
            if ($content -match '^([^:]+):\s*$') {
                $key = $matches[1].Trim()
                # Look at the next line
                if ($i + 1 -lt $lines.Length) {
                    $nextLine = $lines[$i + 1]
                    $nextIndent = $nextLine.Length - $nextLine.TrimStart().Length
                    $nextContent = $nextLine.TrimStart()
                    
                    # If the next line is an array element with the same indentation + 2
                    if ($nextContent -match '^-\s+' -and $nextIndent -eq $indent + 2) {
                        # Store with the key and relative indentation (not absolute)
                        $arrayKeys[$key] = $indent
                    }
                }
            }
        }
        
        foreach ($line in $lines) {
            $lineCount++
            if ($lineCount -gt $maxLines) {
                Write-Warning "YAML parsing stopped: too many lines ($lineCount > $maxLines)"
                break
            }
            
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }
            
            $indent = $line.Length - $line.TrimStart().Length
            $content = $line.TrimStart()
            
            # Handle indentation - return to the correct level
            $maxPop = 20
            $popCount = 0
            for ($j = $stack.Count - 1; $j -ge 0 -and $popCount -lt $maxPop; $j--) {
                if ($stack[$j].indent -ge $indent) {
                    $popCount++
                } else {
                    break
                }
            }
            
            if ($popCount -gt 0 -and $popCount -lt $maxPop) {
                $stack = $stack[0..($stack.Count - 1 - $popCount)]
            } elseif ($popCount -ge $maxPop) {
                Write-Warning "YAML parsing: too many stack pops ($popCount), resetting stack"
                $stack = @()
            }
            
            # If indentation is 0, we're at root level
            if ($indent -eq 0) {
                $current = $result
                $currentIsArray = $false
            } elseif ($stack.Count -eq 0) {
                $current = $result
                $currentIsArray = $false
            } else {
                $current = $stack[-1].obj
                $currentIsArray = $stack[-1].isArray
            }
            
            # Detect array elements (start with -)
            if ($content -match '^-\s*(.+)$') {
                $itemContent = $matches[1].Trim()
                
                # If the element is a key-value pair
                if ($itemContent -match '^([^:]+):\s*(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    
                    # Create a new object for this array element
                    $newItem = @{}
                    
                    # Find the parent array
                    # Simple strategy: search in the closest parent that contains an array
                    $targetArray = $null
                    $targetArrayKey = $null
                    $targetParent = $null
                    
                    # If we're in an array, find where it's stored
                    if ($currentIsArray) {
                        $targetArray = $current
                        # Search in all stack levels and in result
                        $searchObjects = @($result)
                        foreach ($si in $stack) {
                            if ($si.obj -is [hashtable]) {
                                $searchObjects += $si.obj
                            }
                        }
                        foreach ($searchObj in $searchObjects) {
                            if ($searchObj -is [hashtable]) {
                                foreach ($k in $searchObj.Keys) {
                                    if ($searchObj[$k] -is [array] -and $searchObj[$k] -eq $targetArray) {
                                        $targetArrayKey = $k
                                        $targetParent = $searchObj
                                        break
                                    }
                                }
                                if ($targetArrayKey) {
                                    break
                                }
                            }
                        }
                    } else {
                        # Search in the stack to find a parent array
                        for ($si = $stack.Count - 1; $si -ge 0; $si--) {
                            if ($stack[$si].isArray) {
                                $targetArray = $stack[$si].obj
                                # Find the parent that contains this array
                                $searchObjects = @($result)
                                if ($si -gt 0) {
                                    $searchObjects += $stack[$si - 1].obj
                                }
                                foreach ($searchObj in $searchObjects) {
                                    if ($searchObj -is [hashtable]) {
                                        foreach ($k in $searchObj.Keys) {
                                            if ($searchObj[$k] -is [array] -and $searchObj[$k] -eq $targetArray) {
                                                $targetArrayKey = $k
                                                $targetParent = $searchObj
                                                break
                                            }
                                        }
                                        if ($targetArrayKey) {
                                            break
                                        }
                                    }
                                }
                                break
                            }
                        }
                        
                        # If no array found in the stack, search in the direct parent
                        if (-not $targetArray -and $stack.Count -gt 0) {
                            $parent = $stack[-1].obj
                            if ($parent -is [hashtable]) {
                                # Search for a key that points to an array (priority: parameters, tags)
                                foreach ($k in @('parameters', 'tags', 'required')) {
                                    if ($parent.ContainsKey($k) -and $parent[$k] -is [array]) {
                                        $targetArray = $parent[$k]
                                        $targetArrayKey = $k
                                        $targetParent = $parent
                                        break
                                    }
                                }
                                # If not found, search for any array
                                if (-not $targetArray) {
                                    foreach ($k in $parent.Keys) {
                                        if ($parent[$k] -is [array]) {
                                            $targetArray = $parent[$k]
                                            $targetArrayKey = $k
                                            $targetParent = $parent
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    # If we found an array, add the element to it
                    if ($targetArray -and $targetParent -and $targetArrayKey) {
                        # Add element to array by directly modifying the parent
                        $targetParent[$targetArrayKey] = $targetParent[$targetArrayKey] + ,$newItem
                        # Update all references in the stack
                        for ($si = 0; $si -lt $stack.Count; $si++) {
                            if ($stack[$si].isArray) {
                                # Check if it's the same array by comparing with the parent
                                $stackParent = $null
                                if ($si -gt 0) {
                                    $stackParent = $stack[$si - 1].obj
                                } else {
                                    $stackParent = $result
                                }
                                if ($stackParent -is [hashtable] -and $stackParent.ContainsKey($targetArrayKey) -and $stackParent[$targetArrayKey] -is [array]) {
                                    if ($stack[$si].obj -eq $targetArray -or ($stackParent[$targetArrayKey] -eq $targetArray -and $stackParent[$targetArrayKey].Count -eq $targetArray.Count)) {
                                        $stack[$si].obj = $targetParent[$targetArrayKey]
                                    }
                                }
                            }
                        }
                        # Update current if it was the array
                        if ($current -eq $targetArray) {
                            $current = $targetParent[$targetArrayKey]
                        }
                        $stack += @{ indent = $indent; obj = $newItem; isArray = $false }
                        $current = $newItem
                        $currentIsArray = $false
                    } else {
                        # Fallback: search directly in result for known keys
                        $foundInResult = $false
                        foreach ($k in @('parameters', 'tags', 'required')) {
                            if ($result.ContainsKey($k) -and $result[$k] -is [array]) {
                                $result[$k] = $result[$k] + ,$newItem
                                $stack += @{ indent = $indent; obj = $newItem; isArray = $false }
                                $current = $newItem
                                $currentIsArray = $false
                                $foundInResult = $true
                                break
                            }
                        }
                        if (-not $foundInResult) {
                            # Create a new array and attach it to the parent
                            $newArray = @($newItem)
                            if ($stack.Count -gt 0) {
                                $parent = $stack[-1].obj
                                if ($parent -is [hashtable]) {
                                    # Search for a key that should be an array
                                    foreach ($k in @('parameters', 'tags')) {
                                        if ($parent.ContainsKey($k)) {
                                            $parent[$k] = $newArray
                                            break
                                        }
                                    }
                                }
                            }
                            $stack += @{ indent = $indent; obj = $newItem; isArray = $false }
                            $current = $newItem
                            $currentIsArray = $false
                        }
                    }
                    
                    # Process the value
                    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^\$ref') {
                        if ($value -match '^\$ref') {
                            $refValue = $value -replace '^["'']|["'']$', ''
                            $current['$ref'] = $refValue
                        } else {
                            # New object
                            $newObj = @{}
                            $current[$key] = $newObj
                            $stack += @{ indent = $indent + 2; obj = $newObj; isArray = $false }
                            $current = $newObj
                            $currentIsArray = $false
                        }
                    } else {
                        # Simple value
                        $current[$key] = $value -replace '^["'']|["'']$', ''
                    }
                } else {
                    # Simple array element (direct value)
                    if (-not $currentIsArray) {
                        # Create an array
                        $newArray = @()
                        # Find the key in the parent
                        if ($stack.Count -gt 0) {
                            $parent = $stack[-1].obj
                            if ($parent -is [hashtable]) {
                                foreach ($k in $parent.Keys) {
                                    if ($parent[$k] -eq $current) {
                                        $parent[$k] = $newArray
                                        break
                                    }
                                }
                            }
                        }
                        $current = $newArray
                        $currentIsArray = $true
                        if ($stack.Count -gt 0) {
                            $stack[-1].obj = $newArray
                            $stack[-1].isArray = $true
                        }
                    }
                    $current += ,($itemContent -replace '^["'']|["'']$', '')
                }
            }
            # Detect keys with values (no -)
            elseif ($content -match '^([^:]+):\s*(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Check if this key should be an array
                $shouldBeArray = $arrayKeys.ContainsKey($key)
                
                # Process the value
                if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^\$ref') {
                    if ($key -eq '$ref' -or $value -match '^\$ref') {
                        # Reference
                        $refValue = $value -replace '^["'']|["'']$', ''
                        if ($key -eq '$ref') {
                            $current['$ref'] = $refValue
                        } else {
                            $refObj = @{}
                            $refObj['$ref'] = $refValue
                            $current[$key] = $refObj
                        }
                    } elseif ($shouldBeArray) {
                        # Create an empty array that will be filled by following elements
                        $newArray = @()
                        $current[$key] = $newArray
                        $stack += @{ indent = $indent; obj = $newArray; isArray = $true }
                        $current = $newArray
                        $currentIsArray = $true
                    } else {
                        # New object
                        $newObj = @{}
                        $current[$key] = $newObj
                        $stack += @{ indent = $indent; obj = $newObj; isArray = $false }
                        $current = $newObj
                        $currentIsArray = $false
                    }
                } elseif ($key -eq 'tags') {
                    # tags must always be an array according to OpenAPI spec
                    if ($value -match '^\[(.+)\]$') {
                        # Inline array (e.g., tags: [VMs] or tags: [VMs, Health])
                        $items = $matches[1] -split ',' | ForEach-Object { $_.Trim() -replace '^["'']|["'']$', '' }
                        $current[$key] = $items
                    } else {
                        # Simple value without brackets (e.g., tags: VMs) -> convert to array
                        $cleanValue = $value -replace '^["'']|["'']$', ''
                        $current[$key] = @($cleanValue)
                    }
                } elseif ($key -eq 'required') {
                    # required must be a boolean according to OpenAPI spec
                    $cleanValue = $value.Trim() -replace '^["'']|["'']$', ''
                    $lowerValue = $cleanValue.ToLower()
                    if ($lowerValue -eq 'true') {
                        $current[$key] = $true
                    } elseif ($lowerValue -eq 'false') {
                        $current[$key] = $false
                    } else {
                        # Unknown value, keep as string (will be fixed in post-processing)
                        $current[$key] = $cleanValue
                    }
                } elseif ($value -match '^\[(.+)\]$') {
                    # Simple inline array (e.g., parameters: [param1, param2])
                    $items = $matches[1] -split ',' | ForEach-Object { $_.Trim() -replace '^["'']|["'']$', '' }
                    $current[$key] = $items
                } else {
                    # Simple value
                    $current[$key] = $value -replace '^["'']|["'']$', ''
                }
            }
        }
    }
    catch {
        Write-Warning "Error in Convert-HvoOpenApiYaml: $($_.Exception.Message)"
        Write-Warning $_.ScriptStackTrace
        return $result
    }
    
    return $result
}

function Repair-HvoOpenApiSpecStructure {
    param([hashtable]$Spec)
    
    if (-not $Spec -or $Spec.Count -eq 0) {
        return $Spec
    }
    
    # Create a copy to avoid modifying during iteration
    $fixed = @{}
    
    foreach ($key in $Spec.Keys) {
        $value = $Spec[$key]
        
        # Process values according to their type
        if ($value -is [hashtable]) {
            $fixed[$key] = Repair-HvoOpenApiSpecStructure -Spec $value
        } elseif ($value -is [array]) {
            # Preserve array type using @() and modifying in-place
            $arrayResult = @()
            foreach ($item in $value) {
                if ($item -is [hashtable]) {
                    $arrayResult += ,(Repair-HvoOpenApiSpecStructure -Spec $item)
                } else {
                    $arrayResult += ,$item
                }
            }
            $fixed[$key] = $arrayResult
        } else {
            $fixed[$key] = $value
        }
    }
    
    # Fix specific issues
    
    # 1. Extract responses from requestBody.content.application/json.schema.responses
    if ($fixed.ContainsKey('requestBody')) {
        $requestBody = $fixed['requestBody']
        if ($requestBody -is [hashtable]) {
            # Search for responses in requestBody.content.application/json.schema.responses
            if ($requestBody.ContainsKey('content')) {
                $content = $requestBody['content']
                if ($content -is [hashtable] -and $content.ContainsKey('application/json')) {
                    $appJson = $content['application/json']
                    if ($appJson -is [hashtable] -and $appJson.ContainsKey('schema')) {
                        $schema = $appJson['schema']
                        if ($schema -is [hashtable] -and $schema.ContainsKey('responses')) {
                            # Extract responses and move them to operation level
                            $nestedResponses = $schema['responses']
                            if (-not $fixed.ContainsKey('responses')) {
                                $fixed['responses'] = $nestedResponses
                            } else {
                                # Merge with existing responses (priority to existing ones)
                                foreach ($respKey in $nestedResponses.Keys) {
                                    if (-not $fixed['responses'].ContainsKey($respKey)) {
                                        $fixed['responses'][$respKey] = $nestedResponses[$respKey]
                                    }
                                }
                            }
                            # Remove responses from schema
                            $schema.Remove('responses')
                            # Clean schema: if only $ref remains, use the reference directly
                            if ($schema.Count -eq 1 -and $schema.ContainsKey('$ref')) {
                                $appJson['schema'] = @{ '$ref' = $schema['$ref'] }
                            } elseif ($schema.Count -eq 0) {
                                # If schema is empty after removal, remove it
                                $appJson.Remove('schema')
                            }
                        }
                    }
                }
            }
        }
    }
    
    # 2. Convert required from string "true"/"false" to boolean
    if ($fixed.ContainsKey('required')) {
        $requiredValue = $fixed['required']
        if ($requiredValue -is [string]) {
            $lowerValue = $requiredValue.ToLower()
            if ($lowerValue -eq 'true') {
                $fixed['required'] = $true
            } elseif ($lowerValue -eq 'false') {
                $fixed['required'] = $false
            }
        }
    }
    
    # 3. Ensure tags is always an array
    if ($fixed.ContainsKey('tags')) {
        $tagsValue = $fixed['tags']
        if ($tagsValue -isnot [array]) {
            if ($tagsValue -is [string] -and $tagsValue -match '^\[(.+)\]$') {
                # Inline array (e.g., [VMs] or [VMs, Health])
                $items = $matches[1] -split ',' | ForEach-Object { $_.Trim() -replace '^["'']|["'']$', '' }
                $fixed['tags'] = $items
            } else {
                # Simple value -> convert to array
                $cleanValue = $tagsValue -replace '^["'']|["'']$', ''
                $fixed['tags'] = @($cleanValue)
            }
        }
    }
    
    # 4. Recursively fix required in parameters and other structures
    if ($fixed.ContainsKey('parameters')) {
        $parameters = $fixed['parameters']
        if ($parameters -is [array]) {
            # Preserve array by modifying elements in-place
            for ($i = 0; $i -lt $parameters.Count; $i++) {
                $param = $parameters[$i]
                if ($param -is [hashtable] -and $param.ContainsKey('required')) {
                    $reqVal = $param['required']
                    if ($reqVal -is [string]) {
                        $lowerVal = $reqVal.ToLower()
                        if ($lowerVal -eq 'true') {
                            $param['required'] = $true
                        } elseif ($lowerVal -eq 'false') {
                            $param['required'] = $false
                        }
                    }
                }
            }
            # Ensure parameters remains an array
            $fixed['parameters'] = $parameters
        }
    }
    
    return $fixed
}

function Add-HvoOpenApiSchemas {
    param($Spec)
    
    $Spec.components.schemas.Error = @{
        type = "object"
        properties = @{
            error = @{
                type = "string"
                description = "Human-readable error message"
            }
            detail = @{
                type = "string"
                description = "Optional technical message"
            }
        }
        required = @("error")
    }
    
    $Spec.components.schemas.Vm = @{
        type = "object"
        properties = @{
            Name = @{ type = "string" }
            State = @{ type = "string" }
            CPUUsage = @{ type = "integer" }
            MemoryAssigned = @{ type = "integer" }
            Uptime = @{ type = "string" }
        }
    }
    
    $Spec.components.schemas.VmCreateRequest = @{
        type = "object"
        required = @("name", "memoryMB", "vcpu", "diskPath", "diskGB", "switchName")
        properties = @{
            name = @{
                type = "string"
                description = "VM name"
            }
            memoryMB = @{
                type = "integer"
                description = "Memory in MB"
            }
            vcpu = @{
                type = "integer"
                description = "Number of vCPUs"
            }
            diskPath = @{
                type = "string"
                description = "Disk path"
            }
            diskGB = @{
                type = "integer"
                description = "Disk size in GB"
            }
            switchName = @{
                type = "string"
                description = "Virtual switch name"
            }
            isoPath = @{
                type = "string"
                description = "ISO path (optional)"
            }
        }
    }
    
    $Spec.components.schemas.VmUpdateRequest = @{
        type = "object"
        properties = @{
            memoryMB = @{
                type = "integer"
                description = "Memory in MB"
            }
            vcpu = @{
                type = "integer"
                description = "Number of vCPUs"
            }
            switchName = @{
                type = "string"
                description = "Virtual switch name"
            }
            isoPath = @{
                type = "string"
                description = "ISO path"
            }
        }
    }
    
    $Spec.components.schemas.VmActionResponse = @{
        type = "object"
        properties = @{
            created = @{ type = "string" }
            exists = @{ type = "string" }
            deleted = @{ type = "string" }
            started = @{ type = "string" }
            stopped = @{ type = "string" }
            restarted = @{ type = "string" }
            suspended = @{ type = "string" }
            resumed = @{ type = "string" }
            updated = @{ type = "boolean" }
            unchanged = @{ type = "boolean" }
            name = @{ type = "string" }
        }
    }
    
    $Spec.components.schemas.Switch = @{
        type = "object"
        properties = @{
            Name = @{ type = "string" }
            SwitchType = @{
                type = "string"
                enum = @("Internal", "Private", "External")
            }
            Notes = @{ type = "string" }
        }
    }
    
    $Spec.components.schemas.SwitchCreateRequest = @{
        type = "object"
        required = @("name", "type")
        properties = @{
            name = @{
                type = "string"
                description = "Switch name"
            }
            type = @{
                type = "string"
                enum = @("Internal", "Private", "External")
                description = "Switch type"
            }
            netAdapterName = @{
                type = "string"
                description = "Network adapter name (required for External)"
            }
            notes = @{
                type = "string"
                description = "Optional notes"
            }
        }
    }
    
    $Spec.components.schemas.SwitchUpdateRequest = @{
        type = "object"
        properties = @{
            notes = @{
                type = "string"
                description = "Notes"
            }
        }
    }
    
    $Spec.components.schemas.HealthResponse = @{
        type = "object"
        properties = @{
            status = @{ type = "string" }
            config = @{ type = "object" }
            root = @{ type = "string" }
            time = @{
                type = "string"
                format = "date-time"
            }
        }
    }
}

function Add-HvoOpenApiResponses {
    param($Spec)
    
    $Spec.components.responses.Error = @{
        description = "Server error"
        content = @{
            "application/json" = @{
                schema = @{ '$ref' = "#/components/schemas/Error" }
            }
        }
    }
    
    $Spec.components.responses.NotFound = @{
        description = "Resource not found"
        content = @{
            "application/json" = @{
                schema = @{ '$ref' = "#/components/schemas/Error" }
            }
        }
    }
    
    $Spec.components.responses.BadRequest = @{
        description = "Invalid request"
        content = @{
            "application/json" = @{
                schema = @{ '$ref' = "#/components/schemas/Error" }
            }
        }
    }
}

Export-ModuleMember -Function *
