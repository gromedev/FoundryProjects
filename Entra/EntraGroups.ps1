#Requires -Version 7.0
<#
.SYNOPSIS
    Collects Entra ID cloud-only groups with parallel processing
.DESCRIPTION
    Collects basic group properties for all cloud-only groups
    GroupIdentifier column REMOVED (redundant with displayName)
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
$tempPath = Join-Path $config.Paths.Temp "EntraGroups_$timestamp.csv"

# Initialize CSV with headers - GroupIdentifier REMOVED
$csvHeader = "`"displayName`",`"Id`",`"classification`",`"deletedDateTime`",`"description`",`"groupTypes`",`"mailEnabled`",`"membershipRule`",`"securityEnabled`",`"isAssignableToRole`""
Set-Content -Path $tempPath -Value $csvHeader -Encoding UTF8

Write-Host "CSV Header created with 10 fields in order:" -ForegroundColor Yellow
Write-Host "1. displayName, 2. Id, 3. classification, 4. deletedDateTime, 5. description" -ForegroundColor Gray  
Write-Host "6. groupTypes, 7. mailEnabled, 8. membershipRule, 9. securityEnabled, 10. isAssignableToRole" -ForegroundColor Gray

# Proper CSV escaping function with explicit empty quotes for nulls
function ConvertTo-SafeCSV {
    param([string]$Value)
    
    if ([string]::IsNullOrEmpty($Value)) {
        return '""'
    }
    
    # Remove dangerous characters that break CSV structure
    $cleanValue = $Value -replace "`r`n", " " -replace "`n", " " -replace "`r", " " -replace "`t", " "
    $cleanValue = $cleanValue -replace '\s+', ' '  # Collapse multiple spaces
    $cleanValue = $cleanValue.Trim()
    
    # CRITICAL: Escape double quotes for CSV
    $cleanValue = $cleanValue -replace '"', '""'
    
    # Return with quotes
    return "`"$cleanValue`""
}

try {
    # Connect to Graph
    Connect-ToGraph -Config $config.EntraID
    
    # Initialize batch processing
    $batchSize = $config.EntraID.BatchSize
    $totalProcessed = 0
    $batchNumber = 0
    
    # Use BETA endpoint for reliable isAssignableToRole values
    $selectFields = "displayName,id,classification,deletedDateTime,description,groupTypes,mailEnabled,membershipRule,securityEnabled,isAssignableToRole,onPremisesSyncEnabled"
    
    $nextLink = "https://graph.microsoft.com/beta/groups?`$select=$selectFields&`$top=$batchSize"
    
    Write-Host "Using BETA endpoint for reliable isAssignableToRole values" -ForegroundColor Cyan
    Write-Host "Starting cloud-only groups collection..."
    
    while ($nextLink) {
        $batchNumber++
        Write-Host "Processing batch $batchNumber..."
        
        # Check memory only every 10 batches
        if ($batchNumber % 10 -eq 0) {
            if (Test-MemoryPressure -ThresholdGB $config.EntraID.MemoryThresholdGB `
                                    -WarningGB $config.EntraID.MemoryWarningThresholdGB) {
                # Memory cleanup handled in function
            }
        }
        
        # Get batch directly
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
        $groups = $response.value
        $nextLink = $response.'@odata.nextLink'
        
        if ($groups.Count -gt 0) {
            # Pre-convert dates before parallel processing
            foreach ($group in $groups) {
                $group | Add-Member -NotePropertyName 'StandardDeletedDateTime' -NotePropertyValue $(
                    if ($group.deletedDateTime) { 
                        Convert-ToStandardDateTime -DateValue $group.deletedDateTime -SourceFormat 'GraphAPI' 
                    } else { "" }
                )
            }

            # Pre-convert boolean values before parallel processing
            foreach ($group in $groups) {
                $group | Add-Member -NotePropertyName 'StandardMailEnabled' -NotePropertyValue $(
                    if ($null -ne $group.mailEnabled) { if ($group.mailEnabled) { "1" } else { "0" } } else { "" }
                )
                $group | Add-Member -NotePropertyName 'StandardSecurityEnabled' -NotePropertyValue $(
                    if ($null -ne $group.securityEnabled) { if ($group.securityEnabled) { "1" } else { "0" } } else { "" }
                )
                $group | Add-Member -NotePropertyName 'StandardIsAssignableToRole' -NotePropertyValue $(
                    if ($null -ne $group.isAssignableToRole) { 
                        if ($group.isAssignableToRole) { "1" } else { "0" } 
                    } else { "" }
                )
            }
            
            # Process groups in parallel
            $batchResults = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
            $groups | ForEach-Object -ThrottleLimit $config.EntraID.ParallelThrottle -Parallel {
                # Import the CSV function in parallel scope
                function ConvertTo-SafeCSV {
                    param([string]$Value)
                    if ([string]::IsNullOrEmpty($Value)) { 
                        return '""'
                    }
                    $cleanValue = $Value -replace "`r`n", " " -replace "`n", " " -replace "`r", " " -replace "`t", " "
                    $cleanValue = $cleanValue -replace '\s+', ' '
                    $cleanValue = $cleanValue.Trim()
                    $cleanValue = $cleanValue -replace '"', '""'
                    return "`"$cleanValue`""
                }
                
                $group = $_
                $localBatchResults = $using:batchResults
                $errorValue = "NULL"
                
                try {
                    # Skip AD-synced groups
                    if ($group.onPremisesSyncEnabled -eq $true) {
                        continue
                    }
                    
                    # Properly escape groupTypes array
                    $groupTypesString = if ($group.groupTypes -and $group.groupTypes.Count -gt 0) {
                        $safeTypes = $group.groupTypes | ForEach-Object { 
                            $_ -replace '"', '""' -replace ",", ";" -replace "`r`n", " " 
                        }
                        ConvertTo-SafeCSV -Value ($safeTypes -join ' | ')
                    } else { ConvertTo-SafeCSV -Value $errorValue }
                    
                    # Use pre-converted date values
                    $deletedDateTime = ConvertTo-SafeCSV -Value ($group.StandardDeletedDateTime ?? $errorValue)
                    
                    # Properly escape ALL text fields
                    $displayName = ConvertTo-SafeCSV -Value ($group.displayName ?? $errorValue)
                    $classification = ConvertTo-SafeCSV -Value ($group.classification ?? $errorValue)
                    $description = ConvertTo-SafeCSV -Value ($group.description ?? $errorValue)
                    $membershipRule = ConvertTo-SafeCSV -Value ($group.membershipRule ?? $errorValue)
                    
                    # Create line with ALL fields properly escaped (GroupIdentifier removed)
                    $line = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f `
                        $displayName,
                        (ConvertTo-SafeCSV -Value ($group.id ?? $errorValue)),
                        $classification,
                        $deletedDateTime,
                        $description,
                        $groupTypesString,
                        (ConvertTo-SafeCSV -Value ($group.StandardMailEnabled ?? $errorValue)),
                        $membershipRule,
                        (ConvertTo-SafeCSV -Value ($group.StandardSecurityEnabled ?? $errorValue)),
                        (ConvertTo-SafeCSV -Value ($group.StandardIsAssignableToRole ?? $errorValue))
                    
                    # Verify field count
                    $fieldCount = ($line -split ',(?=(?:[^"]*"[^"]*")*[^"]*$)').Count
                    if ($fieldCount -ne 10) {
                        Write-Warning "FIELD COUNT MISMATCH for group $($group.displayName): Expected 10 fields, got $fieldCount"
                    }
                    
                    $localBatchResults.Add($line)
                }
                catch {
                    Write-Warning "Error processing group $($group.displayName): $_"
                }
            }
            
            # Write batch to file
            if ($batchResults.Count -gt 0) {
                $batchResults | Add-Content -Path $tempPath -Encoding UTF8
                $totalProcessed += $groups.Count
                Write-Host "Completed batch $batchNumber. Total groups processed: $totalProcessed"
            }
        }
    }
    
    Write-Host "Processing complete. Total cloud-only groups processed: $totalProcessed" -ForegroundColor Green
    
    # Move to final location
    Move-ProcessedCSV -SourcePath $tempPath -FinalFileName "EntraGroups_$timestamp.csv" -Config $config
}
catch {
    Write-Error "Error collecting Entra groups: $_"
    throw
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}