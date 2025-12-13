#Requires -Version 7.0
<#
.SYNOPSIS
    Collects Entra ID cloud-only groups with parallel processing
.DESCRIPTION
    Collects basic group properties for all cloud-only groups
    Outputs THREE separate CSV files:
    1. EntraGroups-BasicData - Core group info (one row per group)
    2. EntraGroups-Types - Group types (one row per type)
    3. EntraGroups-Tags - Group tags (one row per tag)
#>

[CmdletBinding()]
param()

# Import modules
Import-Module (Resolve-Path (Join-Path $PSScriptRoot "Common.Functions.psm1")) -Force

# Get configuration
$config = Get-Config

# Setup paths for THREE outputs
$timestamp = Get-Date -Format $config.FileManagement.DateFormat
$tempPathBasic = Join-Path $config.Paths.Temp "EntraGroups-BasicData_$timestamp.csv"
$tempPathTypes = Join-Path $config.Paths.Temp "EntraGroups-Types_$timestamp.csv"
$tempPathTags = Join-Path $config.Paths.Temp "EntraGroups-Tags_$timestamp.csv"

# Initialize CSV with headers
$csvHeaderBasic = "`"GroupId`",`"GroupName`",`"classification`",`"deletedDateTime`",`"description`",`"mailEnabled`",`"membershipRule`",`"securityEnabled`",`"isAssignableToRole`""
Set-Content -Path $tempPathBasic -Value $csvHeaderBasic -Encoding UTF8

$csvHeaderTypes = "`"GroupId`",`"GroupName`",`"GroupType`""
Set-Content -Path $tempPathTypes -Value $csvHeaderTypes -Encoding UTF8

$csvHeaderTags = "`"GroupId`",`"GroupName`",`"Tag`""
Set-Content -Path $tempPathTags -Value $csvHeaderTags -Encoding UTF8

Write-Host "CSV Headers created" -ForegroundColor Yellow

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
    $selectFields = "displayName,id,classification,deletedDateTime,description,groupTypes,mailEnabled,membershipRule,securityEnabled,isAssignableToRole,onPremisesSyncEnabled,tags"
    
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
            $batchResultsBasic = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $batchResultsTypes = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $batchResultsTags = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
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
                $localBatchResultsBasic = $using:batchResultsBasic
                $localBatchResultsTypes = $using:batchResultsTypes
                $localBatchResultsTags = $using:batchResultsTags
                
                try {
                    # Skip AD-synced groups
                    if ($group.onPremisesSyncEnabled -eq $true) {
                        continue
                    }
                    
                    # Use pre-converted date values
                    $deletedDateTime = ConvertTo-SafeCSV -Value ($group.StandardDeletedDateTime ?? "")
                    
                    # Properly escape ALL text fields
                    $displayName = ConvertTo-SafeCSV -Value ($group.displayName ?? "")
                    $classification = ConvertTo-SafeCSV -Value ($group.classification ?? "")
                    $description = ConvertTo-SafeCSV -Value ($group.description ?? "")
                    $membershipRule = ConvertTo-SafeCSV -Value ($group.membershipRule ?? "")
                    
                    # Create basic group line (WITHOUT groupTypes and tags)
                    $lineBasic = "{0},{1},{2},{3},{4},{5},{6},{7},{8}" -f `
                        (ConvertTo-SafeCSV -Value ($group.id ?? "")),
                        $displayName,
                        $classification,
                        $deletedDateTime,
                        $description,
                        (ConvertTo-SafeCSV -Value ($group.StandardMailEnabled ?? "")),
                        $membershipRule,
                        (ConvertTo-SafeCSV -Value ($group.StandardSecurityEnabled ?? "")),
                        (ConvertTo-SafeCSV -Value ($group.StandardIsAssignableToRole ?? ""))
                    
                    $localBatchResultsBasic.Add($lineBasic)
                    
                    # ===========================================
                    # GROUP TYPES (separate CSV)
                    # ===========================================
                    if ($group.groupTypes -and $group.groupTypes.Count -gt 0) {
                        foreach ($groupType in $group.groupTypes) {
                            $lineType = "`"{0}`",`"{1}`",`"{2}`"" -f `
                                $group.id,
                                ($group.displayName ?? ""),
                                ($groupType ?? "")
                            
                            $localBatchResultsTypes.Add($lineType)
                        }
                    }
                    
                    # ===========================================
                    # GROUP TAGS (separate CSV)
                    # ===========================================
                    if ($group.tags -and $group.tags.Count -gt 0) {
                        foreach ($tag in $group.tags) {
                            $lineTag = "`"{0}`",`"{1}`",`"{2}`"" -f `
                                $group.id,
                                ($group.displayName ?? ""),
                                ($tag ?? "")
                            
                            $localBatchResultsTags.Add($lineTag)
                        }
                    }
                }
                catch {
                    Write-Warning "Error processing group $($group.displayName): $_"
                }
            }
            
            # Write batches to files
            if ($batchResultsBasic.Count -gt 0) {
                $batchResultsBasic | Add-Content -Path $tempPathBasic -Encoding UTF8
            }
            
            if ($batchResultsTypes.Count -gt 0) {
                $batchResultsTypes | Add-Content -Path $tempPathTypes -Encoding UTF8
            }
            
            if ($batchResultsTags.Count -gt 0) {
                $batchResultsTags | Add-Content -Path $tempPathTags -Encoding UTF8
            }
            
            $totalProcessed += $groups.Count
            Write-Host "Completed batch $batchNumber. Total groups processed: $totalProcessed"
        }
    }
    
    Write-Host "Processing complete. Total cloud-only groups processed: $totalProcessed" -ForegroundColor Green
    
    # Move ALL THREE files to final location
    Move-ProcessedCSV -SourcePath $tempPathBasic -FinalFileName "EntraGroups-BasicData_$timestamp.csv" -Config $config
    Move-ProcessedCSV -SourcePath $tempPathTypes -FinalFileName "EntraGroups-Types_$timestamp.csv" -Config $config
    Move-ProcessedCSV -SourcePath $tempPathTags -FinalFileName "EntraGroups-Tags_$timestamp.csv" -Config $config
}
catch {
    Write-Error "Error collecting Entra groups: $_"
    throw
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}