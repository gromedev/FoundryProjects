#Requires -Version 7.0
<#
.SYNOPSIS
    Collects Entra ID service principal data with parallel processing
.DESCRIPTION
    Collects comprehensive service principal information from Microsoft Entra ID
    Outputs FIVE separate CSV files:
    1. EntraServicePrincipals-BasicData - Core SP info (one row per SP)
    2. EntraServicePrincipals-OAuth2Permissions - OAuth2 permission scopes (one row per scope)
    3. EntraServicePrincipals-AppPermissions - Resource-specific app permissions (one row per permission)
    4. EntraServicePrincipals-Names - Service principal names (one row per name)
    5. EntraServicePrincipals-Tags - Tags (one row per tag)
#>

[CmdletBinding()]
param()

# Configuration
Import-Module (Resolve-Path (Join-Path $PSScriptRoot "Common.Functions.psm1")) -Force
$config = Get-Config

# Setup paths for outputs
$timestamp = Get-Date -Format $config.FileManagement.DateFormat
$tempPathBasic = Join-Path $config.Paths.Temp "EntraServicePrincipals-BasicData_$timestamp.csv"
$tempPathOAuth2 = Join-Path $config.Paths.Temp "EntraServicePrincipals-OAuth2Permissions_$timestamp.csv"
$tempPathAppPerms = Join-Path $config.Paths.Temp "EntraServicePrincipals-AppPermissions_$timestamp.csv"
$tempPathNames = Join-Path $config.Paths.Temp "EntraServicePrincipals-Names_$timestamp.csv"
$tempPathTags = Join-Path $config.Paths.Temp "EntraServicePrincipals-Tags_$timestamp.csv"

# Initialize CSV with headers
$csvHeaderBasic = "`"ServicePrincipalId`",`"ServicePrincipalName`",`"accountEnabled`",`"appDescription`",`"appId`",`"appRoleAssignmentRequired`",`"deletedDateTime`",`"description`",`"preferredSingleSignOnMode`",`"servicePrincipalType`""
Set-Content -Path $tempPathBasic -Value $csvHeaderBasic -Encoding UTF8

$csvHeaderOAuth2 = "`"ServicePrincipalId`",`"ServicePrincipalName`",`"OAuth2PermissionScope`""
Set-Content -Path $tempPathOAuth2 -Value $csvHeaderOAuth2 -Encoding UTF8

$csvHeaderAppPerms = "`"ServicePrincipalId`",`"ServicePrincipalName`",`"ResourceSpecificApplicationPermission`""
Set-Content -Path $tempPathAppPerms -Value $csvHeaderAppPerms -Encoding UTF8

$csvHeaderNames = "`"ServicePrincipalId`",`"ServicePrincipalName`",`"ServicePrincipalNameValue`""
Set-Content -Path $tempPathNames -Value $csvHeaderNames -Encoding UTF8

$csvHeaderTags = "`"ServicePrincipalId`",`"ServicePrincipalName`",`"Tag`""
Set-Content -Path $tempPathTags -Value $csvHeaderTags -Encoding UTF8

# Initialize mutexes for thread-safe file writing (one per file)
$mutexBasic = [System.Threading.Mutex]::new($false, "EntraSPBasicCSVMutex")
$mutexOAuth2 = [System.Threading.Mutex]::new($false, "EntraSPOAuth2CSVMutex")
$mutexAppPerms = [System.Threading.Mutex]::new($false, "EntraSPAppPermsCSVMutex")
$mutexNames = [System.Threading.Mutex]::new($false, "EntraSPNamesCSVMutex")
$mutexTags = [System.Threading.Mutex]::new($false, "EntraSPTagsCSVMutex")

try {
    # Connect to Graph
    Connect-ToGraph -Config $config.EntraID
    
    # Initialize processing variables
    $resultBufferBasic = [System.Collections.Generic.List[string]]::new()
    $resultBufferOAuth2 = [System.Collections.Generic.List[string]]::new()
    $resultBufferAppPerms = [System.Collections.Generic.List[string]]::new()
    $resultBufferNames = [System.Collections.Generic.List[string]]::new()
    $resultBufferTags = [System.Collections.Generic.List[string]]::new()
    
    $totalProcessed = 0
    $batchNumber = 0
    
    # Initialize batch processing
    $batchSize = $config.EntraID.BatchSize
    
    # Define the select fields for service principals
    $selectFields = "appDisplayName,accountEnabled,addIns,displayName,appId,appRoleAssignmentRequired,deletedDateTime,description,oauth2PermissionScopes,resourceSpecificApplicationPermissions,servicePrincipalNames,servicePrincipalType,tags,notes"
    
    # Build initial query for service principals
    $nextLink = "https://graph.microsoft.com/v1.0/serviceprincipals?`$select=$selectFields&`$top=$batchSize"
    
    Write-Verbose "Starting service principal collection..."
    
    while ($nextLink) {
        $batchNumber++
        Write-Verbose "Processing batch $batchNumber..."
        
        # Check memory pressure every 10 batches
        if ($batchNumber % 10 -eq 0) {
            if (Test-MemoryPressure -ThresholdGB $config.EntraID.MemoryThresholdGB `
                                    -WarningGB $config.EntraID.MemoryWarningThresholdGB) {
                # Write buffers when memory pressure detected
                if ($resultBufferBasic.Count -gt 0) {
                    Write-BufferToFile -Buffer $resultBufferBasic -FilePath $tempPathBasic
                }
                if ($resultBufferOAuth2.Count -gt 0) {
                    Write-BufferToFile -Buffer $resultBufferOAuth2 -FilePath $tempPathOAuth2
                }
                if ($resultBufferAppPerms.Count -gt 0) {
                    Write-BufferToFile -Buffer $resultBufferAppPerms -FilePath $tempPathAppPerms
                }
                if ($resultBufferNames.Count -gt 0) {
                    Write-BufferToFile -Buffer $resultBufferNames -FilePath $tempPathNames
                }
                if ($resultBufferTags.Count -gt 0) {
                    Write-BufferToFile -Buffer $resultBufferTags -FilePath $tempPathTags
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
            $batchResultsBasic = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $batchResultsOAuth2 = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $batchResultsAppPerms = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $batchResultsNames = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $batchResultsTags = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
            $servicePrincipals | ForEach-Object -ThrottleLimit $config.EntraID.ParallelThrottle -Parallel {
                $sp = $_
                $localBatchResultsBasic = $using:batchResultsBasic
                $localBatchResultsOAuth2 = $using:batchResultsOAuth2
                $localBatchResultsAppPerms = $using:batchResultsAppPerms
                $localBatchResultsNames = $using:batchResultsNames
                $localBatchResultsTags = $using:batchResultsTags
                
                try {
                    # Clean up text fields for CSV safety
                    $cleanDescription = if ($sp.description) {
                        ($sp.description -replace "`r`n", " " -replace "`n", " " -replace "`t", " " -replace '"', '""').Trim()
                    } else { "" }
                    
                    $cleanNotes = if ($sp.notes) {
                        ($sp.notes -replace "`r`n", " " -replace "`n", " " -replace "`t", " " -replace '"', '""').Trim()
                    } else { "" }
                    
                    # BASIC DATA
                    $lineBasic = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`",`"{8}`",`"{9}`"" -f `
                        ($sp.id ?? ""),
                        (($sp.displayName ?? "") -replace '"', '""'),
                        ($sp.StandardAccountEnabled ?? ""),
                        $cleanNotes,
                        ($sp.appId ?? ""),
                        ($sp.StandardAppRoleAssignmentRequired ?? ""),
                        ($sp.StandardDeletedDateTime ?? ""),
                        $cleanDescription,
                        (""),
                        (($sp.servicePrincipalType ?? "") -replace '"', '""')
                    
                    $localBatchResultsBasic.Add($lineBasic)

                    # OAUTH2 PERMISSION SCOPES
                    if ($sp.oauth2PermissionScopes -and $sp.oauth2PermissionScopes.Count -gt 0) {
                        foreach ($scope in $sp.oauth2PermissionScopes) {
                            if ($scope.value) {
                                $lineOAuth2 = "`"{0}`",`"{1}`",`"{2}`"" -f `
                                    $sp.id,
                                    ($sp.displayName ?? ""),
                                    ($scope.value ?? "")
                                
                                $localBatchResultsOAuth2.Add($lineOAuth2)
                            }
                        }
                    }
                    
                    # RESOURCE-SPECIFIC APP PERMISSIONS
                    if ($sp.resourceSpecificApplicationPermissions -and $sp.resourceSpecificApplicationPermissions.Count -gt 0) {
                        foreach ($permission in $sp.resourceSpecificApplicationPermissions) {
                            if ($permission.value) {
                                $lineAppPerm = "`"{0}`",`"{1}`",`"{2}`"" -f `
                                    $sp.id,
                                    ($sp.displayName ?? ""),
                                    ($permission.value ?? "")
                                
                                $localBatchResultsAppPerms.Add($lineAppPerm)
                            }
                        }
                    }
                    
                    # SERVICE PRINCIPAL NAMES
                    if ($sp.servicePrincipalNames -and $sp.servicePrincipalNames.Count -gt 0) {
                        foreach ($spName in $sp.servicePrincipalNames) {
                            if ($spName) {
                                $lineName = "`"{0}`",`"{1}`",`"{2}`"" -f `
                                    $sp.id,
                                    ($sp.displayName ?? ""),
                                    ($spName ?? "")
                                
                                $localBatchResultsNames.Add($lineName)
                            }
                        }
                    }
                    
                    # TAGS
                    if ($sp.tags -and $sp.tags.Count -gt 0) {
                        foreach ($tag in $sp.tags) {
                            if ($tag) {
                                $lineTag = "`"{0}`",`"{1}`",`"{2}`"" -f `
                                    $sp.id,
                                    ($sp.displayName ?? ""),
                                    ($tag ?? "")
                                
                                $localBatchResultsTags.Add($lineTag)
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Error processing service principal $($sp.displayName): $_"
                }
            }
            
            # Add batch results to main buffers
            foreach ($result in $batchResultsBasic) {
                $resultBufferBasic.Add($result)
            }
            foreach ($result in $batchResultsOAuth2) {
                $resultBufferOAuth2.Add($result)
            }
            foreach ($result in $batchResultsAppPerms) {
                $resultBufferAppPerms.Add($result)
            }
            foreach ($result in $batchResultsNames) {
                $resultBufferNames.Add($result)
            }
            foreach ($result in $batchResultsTags) {
                $resultBufferTags.Add($result)
            }
            
            # Write buffers when full
            if ($resultBufferBasic.Count -ge $config.ActiveDirectory.BufferLimit) {
                try {
                    $mutexBasic.WaitOne() | Out-Null
                    Write-BufferToFile -Buffer $resultBufferBasic -FilePath $tempPathBasic
                }
                finally {
                    $mutexBasic.ReleaseMutex()
                }
            }
            
            if ($resultBufferOAuth2.Count -ge $config.ActiveDirectory.BufferLimit) {
                try {
                    $mutexOAuth2.WaitOne() | Out-Null
                    Write-BufferToFile -Buffer $resultBufferOAuth2 -FilePath $tempPathOAuth2
                }
                finally {
                    $mutexOAuth2.ReleaseMutex()
                }
            }
            
            if ($resultBufferAppPerms.Count -ge $config.ActiveDirectory.BufferLimit) {
                try {
                    $mutexAppPerms.WaitOne() | Out-Null
                    Write-BufferToFile -Buffer $resultBufferAppPerms -FilePath $tempPathAppPerms
                }
                finally {
                    $mutexAppPerms.ReleaseMutex()
                }
            }
            
            if ($resultBufferNames.Count -ge $config.ActiveDirectory.BufferLimit) {
                try {
                    $mutexNames.WaitOne() | Out-Null
                    Write-BufferToFile -Buffer $resultBufferNames -FilePath $tempPathNames
                }
                finally {
                    $mutexNames.ReleaseMutex()
                }
            }
            
            if ($resultBufferTags.Count -ge $config.ActiveDirectory.BufferLimit) {
                try {
                    $mutexTags.WaitOne() | Out-Null
                    Write-BufferToFile -Buffer $resultBufferTags -FilePath $tempPathTags
                }
                finally {
                    $mutexTags.ReleaseMutex()
                }
            }
            
            $totalProcessed += $servicePrincipals.Count
            Write-Verbose "Completed batch $batchNumber. Total service principals processed: $totalProcessed"
        }
        
        # Clear batch data to manage memory
        $servicePrincipals = $null
        $batchData = $null
        
        # Force garbage collection every 20 batches
        if ($batchNumber % 20 -eq 0) {
            [System.GC]::Collect()
        }
    }
    
    # Write remaining buffers
    if ($resultBufferBasic.Count -gt 0) {
        try {
            $mutexBasic.WaitOne() | Out-Null
            Write-BufferToFile -Buffer $resultBufferBasic -FilePath $tempPathBasic
        }
        finally {
            $mutexBasic.ReleaseMutex()
        }
    }
    
    if ($resultBufferOAuth2.Count -gt 0) {
        try {
            $mutexOAuth2.WaitOne() | Out-Null
            Write-BufferToFile -Buffer $resultBufferOAuth2 -FilePath $tempPathOAuth2
        }
        finally {
            $mutexOAuth2.ReleaseMutex()
        }
    }
    
    if ($resultBufferAppPerms.Count -gt 0) {
        try {
            $mutexAppPerms.WaitOne() | Out-Null
            Write-BufferToFile -Buffer $resultBufferAppPerms -FilePath $tempPathAppPerms
        }
        finally {
            $mutexAppPerms.ReleaseMutex()
        }
    }
    
    if ($resultBufferNames.Count -gt 0) {
        try {
            $mutexNames.WaitOne() | Out-Null
            Write-BufferToFile -Buffer $resultBufferNames -FilePath $tempPathNames
        }
        finally {
            $mutexNames.ReleaseMutex()
        }
    }
    
    if ($resultBufferTags.Count -gt 0) {
        try {
            $mutexTags.WaitOne() | Out-Null
            Write-BufferToFile -Buffer $resultBufferTags -FilePath $tempPathTags
        }
        finally {
            $mutexTags.ReleaseMutex()
        }
    }
    
    Write-Verbose "Processing complete! Total service principals processed: $totalProcessed"
    
    # Move ALL FIVE files to final location
    Move-ProcessedCSV -SourcePath $tempPathBasic -FinalFileName "EntraServicePrincipals-BasicData_$timestamp.csv" -Config $config
    Move-ProcessedCSV -SourcePath $tempPathOAuth2 -FinalFileName "EntraServicePrincipals-OAuth2Permissions_$timestamp.csv" -Config $config
    Move-ProcessedCSV -SourcePath $tempPathAppPerms -FinalFileName "EntraServicePrincipals-AppPermissions_$timestamp.csv" -Config $config
    Move-ProcessedCSV -SourcePath $tempPathNames -FinalFileName "EntraServicePrincipals-Names_$timestamp.csv" -Config $config
    Move-ProcessedCSV -SourcePath $tempPathTags -FinalFileName "EntraServicePrincipals-Tags_$timestamp.csv" -Config $config
}
catch {
    Write-Error "Error collecting Entra service principals: $_"
    throw
}
finally {
    # Clean up
    if ($resultBufferBasic) { 
        $resultBufferBasic.Clear()
        $resultBufferBasic = $null
    }
    if ($resultBufferOAuth2) { 
        $resultBufferOAuth2.Clear()
        $resultBufferOAuth2 = $null
    }
    if ($resultBufferAppPerms) { 
        $resultBufferAppPerms.Clear()
        $resultBufferAppPerms = $null
    }
    if ($resultBufferNames) { 
        $resultBufferNames.Clear()
        $resultBufferNames = $null
    }
    if ($resultBufferTags) { 
        $resultBufferTags.Clear()
        $resultBufferTags = $null
    }
    if ($mutexBasic) { $mutexBasic.Dispose() }
    if ($mutexOAuth2) { $mutexOAuth2.Dispose() }
    if ($mutexAppPerms) { $mutexAppPerms.Dispose() }
    if ($mutexNames) { $mutexNames.Dispose() }
    if ($mutexTags) { $mutexTags.Dispose() }
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}