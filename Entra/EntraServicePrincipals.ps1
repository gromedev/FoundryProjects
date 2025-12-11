#Requires -Version 7.0
<#
.SYNOPSIS
    Collects Entra ID service principal data with parallel processing
.DESCRIPTION
    Collects comprehensive service principal information from Microsoft Entra ID
    UserIdentifier column REMOVED (using displayName as primary identifier)
#>

[CmdletBinding()]
param()

# Import modules
Import-Module (Resolve-Path (Join-Path $PSScriptRoot "Modules\Common.Functions.psm1")) -Force

# Get configuration
$config = Get-Config
Initialize-DataPaths -Config $config

Write-Host $PSScriptRoot

# Setup paths
$timestamp = Get-Date -Format $config.FileManagement.DateFormat
$tempPath = Join-Path $config.Paths.Temp "EntraServicePrincipals_$timestamp.csv"

# Initialize CSV with headers - UserIdentifier REMOVED
$csvHeader = "`"displayName`",`"accountEnabled`",`"addIns`",`"appDescription`",`"appId`",`"appRoleAssignmentRequired`",`"deletedDateTime`",`"description`",`"oauth2PermissionScopes`",`"preferredSingleSignOnMode`",`"resourceSpecificApplicationPermissions`",`"servicePrincipalNames`",`"servicePrincipalType`",`"tags`""
Set-Content -Path $tempPath -Value $csvHeader -Encoding UTF8

# Initialize mutex for thread-safe file writing
$mutex = [System.Threading.Mutex]::new($false, "EntraServicePrincipalsCSVMutex")

try {
    # Connect to Graph
    Connect-ToGraph -Config $config.EntraID
    
    # Initialize processing variables
    $resultBuffer = [System.Collections.Generic.List[string]]::new()
    $totalProcessed = 0
    $batchNumber = 0
    
    # Initialize batch processing
    $batchSize = $config.EntraID.BatchSize
    
    # Define the select fields for service principals
    $selectFields = "appDisplayName,accountEnabled,addIns,displayName,appId,appRoleAssignmentRequired,deletedDateTime,description,oauth2PermissionScopes,resourceSpecificApplicationPermissions,servicePrincipalNames,servicePrincipalType,tags,notes"
    
    # Build initial query for service principals
    $nextLink = "https://graph.microsoft.com/v1.0/serviceprincipals?`$select=$selectFields&`$top=$batchSize"
    
    Write-Host "Starting service principal collection..."
    
    while ($nextLink) {
        $batchNumber++
        Write-Host "Processing batch $batchNumber..."
        
        # Check memory pressure every 10 batches
        if ($batchNumber % 10 -eq 0) {
            if (Test-MemoryPressure -ThresholdGB $config.EntraID.MemoryThresholdGB `
                                    -WarningGB $config.EntraID.MemoryWarningThresholdGB) {
                # Write buffer when memory pressure detected
                if ($resultBuffer.Count -gt 0) {
                    Write-BufferToFile -Buffer $resultBuffer -FilePath $tempPath
                }
            }
        }
        
        # Get batch
        $batchData = Get-GraphBatch -NextLink $nextLink -Config $config.EntraID
        $servicePrincipals = $batchData.Items
        $nextLink = $batchData.NextLink
        
        if ($servicePrincipals.Count -gt 0) {
            # Pre-convert dates and booleans before parallel processing
            foreach ($sp in $servicePrincipals) {
                # Standardize boolean values
                $sp | Add-Member -NotePropertyName 'StandardAccountEnabled' -NotePropertyValue $(
                    if ($null -ne $sp.accountEnabled) { if ($sp.accountEnabled) { "1" } else { "0" } } else { "" }
                )
                $sp | Add-Member -NotePropertyName 'StandardAppRoleAssignmentRequired' -NotePropertyValue $(
                    if ($null -ne $sp.appRoleAssignmentRequired) { if ($sp.appRoleAssignmentRequired) { "1" } else { "0" } } else { "" }
                )
                
                # Convert datetime
                $sp | Add-Member -NotePropertyName 'StandardDeletedDateTime' -NotePropertyValue $(
                    if ($sp.deletedDateTime) { 
                        Convert-ToStandardDateTime -DateValue $sp.deletedDateTime -SourceFormat 'GraphAPI' 
                    } else { "" }
                )
            }
            
            # Process service principals in parallel
            $batchResults = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
            $servicePrincipals | ForEach-Object -ThrottleLimit $config.EntraID.ParallelThrottle -Parallel {
                $sp = $_
                $localBatchResults = $using:batchResults
                $errorValue = "NULL"
                
                try {
                    # Process addIns array safely
                    $addIns = if ($sp.addIns -and $sp.addIns.Count -gt 0) {
                        ($sp.addIns | ForEach-Object { $_.type } | Select-Object -First 10) -join ' | '
                    } else { $errorValue }
                    
                    # Clean up text fields for CSV safety
                    $cleanDescription = if ($sp.description) {
                        ($sp.description -replace "`r`n", " " -replace "`n", " " -replace "`t", " " -replace '"', '""').Trim()
                    } else { $errorValue }
                    
                    $cleanNotes = if ($sp.notes) {
                        ($sp.notes -replace "`r`n", " " -replace "`n", " " -replace "`t", " " -replace '"', '""').Trim()
                    } else { $errorValue }
                    
                    # Process oauth2PermissionScopes array
                    $oauth2PermissionScopes = if ($sp.oauth2PermissionScopes -and $sp.oauth2PermissionScopes.Count -gt 0) {
                        ($sp.oauth2PermissionScopes | ForEach-Object { $_.value } | Select-Object -First 20) -join ' | '
                    } else { $errorValue }
                    
                    # Process resourceSpecificApplicationPermissions array
                    $resourceSpecificApplicationPermissions = if ($sp.resourceSpecificApplicationPermissions -and $sp.resourceSpecificApplicationPermissions.Count -gt 0) {
                        ($sp.resourceSpecificApplicationPermissions | ForEach-Object { $_.value } | Select-Object -First 10) -join ' | '
                    } else { $errorValue }
                    
                    # Process servicePrincipalNames array
                    $servicePrincipalNames = if ($sp.servicePrincipalNames -and $sp.servicePrincipalNames.Count -gt 0) {
                        ($sp.servicePrincipalNames | Select-Object -First 15) -join ' | '
                    } else { $errorValue }
                    
                    # Process tags array
                    $tags = if ($sp.tags -and $sp.tags.Count -gt 0) {
                        ($sp.tags | Select-Object -First 10) -join ' | '
                    } else { $errorValue }
                    
                    # Format CSV line (UserIdentifier removed - displayName is first field)
                    $line = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`",`"{8}`",`"{9}`",`"{10}`",`"{11}`",`"{12}`",`"{13}`"" -f `
                        (($sp.displayName ?? $errorValue) -replace '"', '""'),
                        ($sp.StandardAccountEnabled ?? $errorValue),
                        ($addIns -replace '"', '""'),
                        $cleanNotes,
                        ($sp.appId ?? $errorValue),
                        ($sp.StandardAppRoleAssignmentRequired ?? $errorValue),
                        ($sp.StandardDeletedDateTime ?? $errorValue),
                        $cleanDescription,
                        ($oauth2PermissionScopes -replace '"', '""'),
                        ($errorValue),
                        ($resourceSpecificApplicationPermissions -replace '"', '""'),
                        ($servicePrincipalNames -replace '"', '""'),
                        (($sp.servicePrincipalType ?? $errorValue) -replace '"', '""'),
                        ($tags -replace '"', '""')
                    
                    $localBatchResults.Add($line)
                }
                catch {
                    Write-Warning "Error processing service principal $($sp.displayName): $_"
                }
            }
            
            # Write batch to file (thread-safe) and add to main buffer
            if ($batchResults.Count -gt 0) {
                # Add to main buffer for memory management
                foreach ($result in $batchResults) {
                    $resultBuffer.Add($result)
                }
                
                # Write buffer when full
                if ($resultBuffer.Count -ge $config.ActiveDirectory.BufferLimit) {
                    try {
                        $mutex.WaitOne() | Out-Null
                        Write-BufferToFile -Buffer $resultBuffer -FilePath $tempPath
                    }
                    finally {
                        $mutex.ReleaseMutex()
                    }
                }
                
                $totalProcessed += $servicePrincipals.Count
                Write-Host "Completed batch $batchNumber. Total service principals processed: $totalProcessed"
            }
        }
        
        # Clear batch data to manage memory
        $servicePrincipals = $null
        $batchData = $null
        
        # Force garbage collection every 20 batches
        if ($batchNumber % 20 -eq 0) {
            [System.GC]::Collect()
        }
    }
    
    # Write remaining buffer
    if ($resultBuffer.Count -gt 0) {
        try {
            $mutex.WaitOne() | Out-Null
            Write-BufferToFile -Buffer $resultBuffer -FilePath $tempPath
        }
        finally {
            $mutex.ReleaseMutex()
        }
    }
    
    Write-Host "Processing complete! Total service principals processed: $totalProcessed" -ForegroundColor Green
    
    # Move to final location
    Move-ProcessedCSV -SourcePath $tempPath -FinalFileName "EntraServicePrincipals_$timestamp.csv" -Config $config
}
catch {
    Write-Error "Error collecting Entra service principals: $_"
    throw
}
finally {
    # Clean up
    if ($resultBuffer) { 
        $resultBuffer.Clear()
        $resultBuffer = $null
    }
    if ($mutex) { 
        $mutex.Dispose() 
    }
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}