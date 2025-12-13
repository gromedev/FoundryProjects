#Requires -Version 7.0
function Get-Config {
    <#
    .SYNOPSIS
    Returns the module configuration, initialized once. Adjust values as required:
    - Modules, Common: Do not change.
    - Paths: Do not change.
    - TenantId, ClientId, CertificateThumbprint: define the Entra ID authentication context.
    - BatchSize, ParallelThrottle, RateLimitDelayMs: control API throughput.
    - RetryAttempts, RetryDelaySeconds: define fault-handling behavior.
    - MemoryThresholdGB, MemoryWarningThresholdGB: set memory safety limits.
    - TargetGroup, ScopeToGroup: govern scoping (optional).
    - SizeThresholdPercent, DateFormat: control file-management behavior.
    - UniqueUsers, UniqueGroups, UniqueRoles, UniqueApplications: set hashtable capacity expectations.
    - MemoryCheckInterval: defines how often memory usage is inspected.
    #>
    if (-not $script:Config) {
        $script:Config = @{
            Modules = @{
                Common = "Common.Functions.psm1"
            }
            Paths = @{
                CSV = Join-Path $PSScriptRoot "Import\CSVs"
                Temp = Join-Path $PSScriptRoot "Import\temp"
            }
            EntraID = @{
                TenantId = "thomasmartingrome.onmicrosoft.com"
                ClientId = "f8091812-4a88-44c6-9c1d-4ea5abe1bda6"
                CertificateThumbprint = "97a1540bc199dd4406d48101073879ba2573390e"
                BatchSize = 999
                ParallelThrottle = 10
                RateLimitDelayMs = 10
                RetryAttempts = 3
                RetryDelaySeconds = 5
                MemoryThresholdGB = 12
                MemoryWarningThresholdGB = 10
                TargetGroup = $null
                ScopeToGroup = $false
            }
            FileManagement = @{
                SizeThresholdPercent = 20
                DateFormat = "yyyyMMdd_HHmmss"
            }
            Metrics = @{
                HashTableLimits = @{
                    UniqueUsers = 500000
                    UniqueGroups = 5000000
                    UniqueRoles = 500000
                    UniqueApplications = 500000
                }
                MemoryCheckInterval = 50000
            }
        }
    }
    $config = $script:Config

    # output paths creation
    foreach ($pathKey in $config.Paths.Keys) {
        $path = $config.Paths[$pathKey]
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
    return $config
}

function Connect-ToGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph API with certificate authentication
    #>
    param (
        [Parameter(Mandatory)]
        [object]$Config,
        
        [int]$RetryCount = 0
    )
    
    $maxRetries = $Config.RetryAttempts
    
    while ($RetryCount -lt $maxRetries) {
        try {
            Connect-MgGraph -ClientId $Config.ClientId `
                           -TenantId $Config.TenantId `
                           -CertificateThumbprint $Config.CertificateThumbprint `
                           -NoWelcome
            
            $context = Get-MgContext
            if ($context) {
                Write-Verbose "Successfully connected to Graph API"
                return $true
            }
        }
        catch {
            $RetryCount++
            if ($RetryCount -lt $maxRetries) {
                Write-Warning "Graph connection failed, attempt $RetryCount of $maxRetries. Retrying in $($Config.RetryDelaySeconds) seconds..."
                Start-Sleep -Seconds $Config.RetryDelaySeconds
            }
            else {
                throw "Failed to connect to Graph API after $maxRetries attempts: $_"
            }
        }
    }
    
    return $false
}
function Invoke-GraphWithRetry {
    <#
    .SYNOPSIS
        Invokes Graph API request with automatic retry and rate limit handling
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Uri,
        
        [Parameter(Mandatory)]
        [object]$Config,
        
        [string]$Method = "GET",
        
        [int]$RetryCount = 0
    )
    
    $maxRetries = $Config.RetryAttempts
    
    while ($RetryCount -lt $maxRetries) {
        try {
            $result = Invoke-MgGraphRequest -Uri $Uri -Method $Method
            return $result
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            if ($statusCode -eq 429) {
                # Rate limited - check for Retry-After header
                $retryAfter = 60
                if ($_.Exception.Response.Headers.RetryAfter) {
                    $retryAfter = $_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds
                }
                Write-Warning "Rate limited. Waiting $retryAfter seconds..."
                Start-Sleep -Seconds $retryAfter
                # Don't count rate limit against retry count
                continue
            }
            
            $RetryCount++
            if ($RetryCount -lt $maxRetries) {
                Write-Warning "Graph request failed, attempt $RetryCount of $maxRetries. Retrying in $($Config.RetryDelaySeconds) seconds..."
                Start-Sleep -Seconds $Config.RetryDelaySeconds
            }
            else {
                throw "Graph request failed after $maxRetries attempts: $_"
            }
        }
    }
}
function Get-GraphBatch {
<#
    .SYNOPSIS
        Gets a batch of results from Graph API with pagination support
#>
    param($NextLink, $Config)
    $response = Invoke-MgGraphRequest -Method GET -Uri $NextLink
    return @{
        Items = $response.value
        NextLink = $response.'@odata.nextLink'
    }
}
function Test-MemoryPressure {
    <#
    .SYNOPSIS
        Checks current memory usage and triggers garbage collection if needed
    #>
    param (
        [double]$ThresholdGB,
        [double]$WarningGB
    )
    
    $currentMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
    
    if ($currentMemory -gt $ThresholdGB) {
        Write-Warning "Memory usage critical: $([Math]::Round($currentMemory, 2))GB"
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        Start-Sleep -Seconds 2
        return $true
    }
    elseif ($currentMemory -gt $WarningGB) {
        Write-Warning "Memory usage high: $([Math]::Round($currentMemory, 2))GB"
    }
    
    return $false
}
function Write-BufferToFile {
    <#
    .SYNOPSIS
        Writes buffer contents to file and clears buffer
    #>
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$Buffer,
        
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    if ($Buffer.Count -gt 0) {
        $Buffer | Add-Content -Path $FilePath -Encoding UTF8
        $Buffer.Clear()
    }
}
function Move-ProcessedCSV {
    <#
    .SYNOPSIS
        Moves completed CSV to final location with size validation
    .DESCRIPTION
        Validates file size against existing files, creates backups,
        and moves to error folder if size difference exceeds threshold
    #>
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        
        [Parameter(Mandatory)]
        [string]$FinalFileName,
        
        [Parameter(Mandatory)]
        [object]$Config
    )
    
    if (-not (Test-Path $SourcePath)) {
        return
    }
    
    $finalPath = Join-Path $Config.Paths.CSV $FinalFileName
    $sourceSize = (Get-Item $SourcePath).Length
    
    # Check existing file
    if (Test-Path $finalPath) {
        $existingSize = (Get-Item $finalPath).Length
        $sizeDiffPercent = [Math]::Abs(($sourceSize - $existingSize) / $existingSize * 100)
        
        if ($sizeDiffPercent -gt $Config.FileManagement.SizeThresholdPercent) {
            # Move to error folder
            $errorPath = Join-Path $Config.Paths.Error "$FinalFileName`_$(Get-Date -Format $Config.FileManagement.DateFormat)_SizeMismatch.csv"
            Move-Item -Path $SourcePath -Destination $errorPath -Force
            
            $logContent = @"
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Error: Size Mismatch
Size Difference: $([Math]::Round($sizeDiffPercent, 1))%
Source Size: $sourceSize bytes
Existing Size: $existingSize bytes
"@
            Set-Content -Path "$errorPath.log" -Value $logContent
            
            Write-Warning "File size difference ($([Math]::Round($sizeDiffPercent, 1))%) exceeds threshold. File moved to: $errorPath"
            return
        }
        
        # Backup existing
        $backupPath = Join-Path $Config.Paths.Backup "$FinalFileName`_$(Get-Date -Format $Config.FileManagement.DateFormat).csv"
        Copy-Item -Path $finalPath -Destination $backupPath -Force
    }
    
    # Move to final location
    Move-Item -Path $SourcePath -Destination $finalPath -Force
    Write-Verbose "CSV saved to: $finalPath"
}
function Save-Progress {
    <#
    .SYNOPSIS
        Saves progress state to JSON file for resumable operations
    #>
    param (
        [Parameter(Mandatory)]
        [hashtable]$Progress,
        
        [Parameter(Mandatory)]
        [string]$ProgressFile
    )
    
    $Progress | ConvertTo-Json -Depth 10 | Set-Content -Path $ProgressFile
}
function Get-Progress {
    <#
    .SYNOPSIS
        Loads progress state from JSON file
    #>
    param (
        [Parameter(Mandatory)]
        [string]$ProgressFile
    )
    
    if (Test-Path $ProgressFile) {
        Write-Verbose "Resuming from previous progress..."
        return Get-Content $ProgressFile | ConvertFrom-Json -AsHashtable
    }
    
    return $null
}
function Convert-ToStandardDateTime {
    <#
    .SYNOPSIS
        Converts Graph API ISO 8601 datetime to standard format
    .DESCRIPTION
        SIMPLIFIED VERSION - Only supports Graph API format (ISO 8601)
        Returns format: yyyy-MM-dd HH:mm:ss
    .EXAMPLE
        Convert-ToStandardDateTime -DateValue "2024-03-15T10:30:00Z"
        Returns: "2024-03-15 10:30:00"
    #>
    param (
        [object]$DateValue,
        [string]$SourceFormat = "GraphAPI"  # Kept for backward compatibility
    )
    
    # Return empty string for null/empty values
    if ($null -eq $DateValue -or $DateValue -eq '' -or $DateValue -eq 0) {
        return ""
    }
    
    try {
        # Parse ISO 8601 format (Graph API standard)
        $date = [DateTime]::Parse(
            $DateValue, 
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind
        )
        return $date.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        Write-Warning "Failed to convert date value '$DateValue': $_"
        return ""
    }
}
function Get-InitialUserQuery {
    <#
    .SYNOPSIS
        Builds initial user query with optional group scoping
    #>
    param (
        [Parameter(Mandatory)]
        [object]$Config,
        
        [Parameter(Mandatory)]
        [string]$SelectFields,
        
        [Parameter(Mandatory)]
        [int]$BatchSize
    )
    
    if ($Config.ScopeToGroup -and $Config.TargetGroup) {
        Write-Verbose "Scoping collection to group: $($Config.TargetGroup)"
        
        # Get the group ID
        $groupResponse = Invoke-GraphWithRetry `
            -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$($Config.TargetGroup)'" `
            -Config $Config
        
        if (-not $groupResponse.value -or $groupResponse.value.Count -eq 0) {
            throw "Group '$($Config.TargetGroup)' not found in tenant"
        }
        
        $groupId = $groupResponse.value[0].id
        Write-Verbose "Found group ID: $groupId"
        
        return "https://graph.microsoft.com/v1.0/groups/$groupId/members?`$select=$SelectFields&`$top=$BatchSize"
    }
    else {
        Write-Verbose "Collecting all users in tenant"
        return "https://graph.microsoft.com/v1.0/users?`$select=$SelectFields&`$top=$BatchSize"
    }
}
Export-ModuleMember -Function @(
    'Get-Config',
    'Set-ConfigValue',
    'Initialize-DataPaths',
    'Connect-ToGraph',
    'Invoke-GraphWithRetry',
    'Get-GraphBatch',
    'Invoke-GraphRequestWithPaging',
    'Get-InitialUserQuery'
    'Move-ProcessedCSV',
    'Test-MemoryPressure',
    'Write-BufferToFile',
    'Save-Progress',
    'Get-Progress',
    'Convert-ToStandardDateTime'
)