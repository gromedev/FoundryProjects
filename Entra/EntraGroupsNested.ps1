#Requires -Version 7.0
<#
.SYNOPSIS
    Shows cloud-only groups with nesting relationships
.DESCRIPTION
    Collects group nesting data (parent/child relationships)
    Outputs NULL for empty fields instead of empty strings
#>

[CmdletBinding()]
param(
    [string]$TestGroup = $null  # Optional: specify a group to test with
)

# Import modules
Import-Module (Join-Path $PSScriptRoot "Modules\Common.Functions.psm1") -Force

# Get configuration
$config = Get-Config
Initialize-DataPaths -Config $config

# Setup paths
$timestamp = Get-Date -Format $config.FileManagement.DateFormat
$tempPath = Join-Path $config.Paths.Temp "$($config.FilePrefixes.EntraGroups)-Nested_$timestamp.csv"
$progressFile = Join-Path $config.Paths.Temp "$($config.FilePrefixes.EntraGroups)-Nested_progress.json"

# Initialize CSV with relationship-focused headers (IDs and Names)
$csvHeader = "`"GroupId`",`"GroupName`",`"GroupType`",`"NestedGroupIds`",`"NestedGroupNames`",`"NestedGroupCount`",`"ParentGroupIds`",`"ParentGroupNames`",`"ParentGroupCount`",`"TotalRelationships`""
if ($PSVersionTable.PSVersion.Major -ge 6) {
    Set-Content -Path $tempPath -Value $csvHeader -Encoding UTF8
} else {
    Set-Content -Path $tempPath -Value $csvHeader -Encoding Unicode
}

# VERIFY CSV file creation
Write-Host "CSV file created at: $tempPath" -ForegroundColor Cyan
$initialLines = (Get-Content $tempPath -ErrorAction SilentlyContinue).Count
Write-Host "Initial line count: $initialLines (should be 1 for headers)" -ForegroundColor Cyan

# Load progress
$progress = Get-Progress -ProgressFile $progressFile
if (-not $progress) {
    $progress = @{
        ProcessedGroups          = 0
        CloudOnlyGroupsFound     = 0
        GroupsWithRelationships  = 0
        GroupsWrittenToCSV       = 0
        LastBatchNumber          = 0
        StartTime                = (Get-Date).ToString('o')
    }
}

try {
    # Connect to Graph
    Connect-ToGraph -Config $config.EntraID

    Write-Host "Process each group immediately with NULL for empty values" -ForegroundColor Yellow

    # MINIMAL memory footprint - only small buffer for CSV writing
    $resultBuffer = [System.Collections.Generic.List[string]]::new()

    # Counters
    $totalGroupsProcessed = $progress.ProcessedGroups
    $cloudOnlyGroupsFound = $progress.CloudOnlyGroupsFound
    $groupsWithRelationships = $progress.GroupsWithRelationships
    $groupsWrittenToCSV = $progress.GroupsWrittenToCSV
    $batchNumber = $progress.LastBatchNumber

    # Build query
    if ($TestGroup) {
        $nextLink = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$TestGroup'&`$select=displayName,id,onPremisesSyncEnabled,onPremisesSecurityIdentifier,securityEnabled,mailEnabled,mail&`$top=$($config.EntraID.BatchSize)"
        Write-Host "Testing with group: $TestGroup" -ForegroundColor Cyan
    } else {
        $nextLink = "https://graph.microsoft.com/v1.0/groups?`$select=displayName,id,onPremisesSyncEnabled,onPremisesSecurityIdentifier,securityEnabled,mailEnabled,mail&`$top=$($config.EntraID.BatchSize)"
    }

    # Process each group immediately as we find it
    while ($nextLink) {
        $batchNumber++
        Write-Host "Processing batch $batchNumber..." -ForegroundColor Gray
        
        # Memory check
        if (Test-MemoryPressure -ThresholdGB $config.EntraID.MemoryThresholdGB `
                                -WarningGB $config.EntraID.MemoryWarningThresholdGB) {
            Write-Host "  Memory pressure - writing buffer..." -ForegroundColor Yellow
            if ($resultBuffer.Count -gt 0) {
                Write-Host "    Emergency write: $($resultBuffer.Count) lines" -ForegroundColor Yellow
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    $resultBuffer | Add-Content -Path $tempPath -Encoding UTF8
                } else {
                    $resultBuffer | Add-Content -Path $tempPath -Encoding Unicode
                }
                $resultBuffer.Clear()
            }
        }
        
        # Get batch
        $batchData = Get-GraphBatch -NextLink $nextLink -Config $config.EntraID
        $groups = $batchData.Items
        $nextLink = $batchData.NextLink
        
        if ($groups.Count -eq 0) { 
            Write-Host "  No more groups found" -ForegroundColor Gray
            break 
        }
        
        # PROCESS EACH GROUP IMMEDIATELY - NO STORAGE
        foreach ($group in $groups) {
            $totalGroupsProcessed++
            
            # Check if cloud-only
            $isCloudOnly = ($null -eq $group.onPremisesSyncEnabled -or $group.onPremisesSyncEnabled -eq $false) -and
                          ($null -eq $group.onPremisesSecurityIdentifier -or $group.onPremisesSecurityIdentifier -eq "")
            
            if ($isCloudOnly) {
                $cloudOnlyGroupsFound++
                
                # Determine group type
                $groupType = if ($group.mail) {
                    if ($group.securityEnabled -eq $false) { "DistributionList" }
                    else { "MailEnabledSecurity" }
                } else { "Security" }
                
                Write-Host "  Checking: $($group.displayName)" -ForegroundColor DarkGray
                
                try {
                    # Rate limiting to prevent Graph timeouts
                    if ($cloudOnlyGroupsFound % 10 -eq 0) {
                        Start-Sleep -Milliseconds 100
                    }
                    
                    # RELATIONSHIP 1: What cloud-only groups does this group contain? (Children)
                    $nestedGroups = @()
                    $nestedGroupIds = @()
                    $nestedGroupNames = @()
                    
                    try {
                        $membersUri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/transitiveMembers/microsoft.graph.group?`$select=id,displayName,onPremisesSyncEnabled,onPremisesSecurityIdentifier"
                        $nestedResponse = Invoke-GraphWithRetry -Uri $membersUri -Config $config.EntraID
                        
                        if ($nestedResponse.value) {
                            # Filter to only cloud-only nested groups
                            $nestedGroups = $nestedResponse.value | Where-Object {
                                ($null -eq $_.onPremisesSyncEnabled -or $_.onPremisesSyncEnabled -eq $false) -and
                                ($null -eq $_.onPremisesSecurityIdentifier -or $_.onPremisesSecurityIdentifier -eq "")
                            }
                            
                            if ($nestedGroups) {
                                $nestedGroupIds = $nestedGroups.id
                                $nestedGroupNames = $nestedGroups.displayName | ForEach-Object {
                                    $_ -replace '"', '""' -replace ',', ';' -replace '\r?\n', ' '
                                }
                            }
                        }
                    } catch {
                        Write-Warning "    Error getting nested groups: $_"
                    }
                    
                    # RELATIONSHIP 2: What cloud-only groups contain this group? (Parents)
                    $parentGroups = @()
                    $parentGroupIds = @()
                    $parentGroupNames = @()
                    
                    try {
                        $memberOfUri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName,onPremisesSyncEnabled,onPremisesSecurityIdentifier"
                        $parentResponse = Invoke-GraphWithRetry -Uri $memberOfUri -Config $config.EntraID
                        
                        if ($parentResponse.value) {
                            # Filter to only cloud-only parent groups
                            $parentGroups = $parentResponse.value | Where-Object {
                                ($null -eq $_.onPremisesSyncEnabled -or $_.onPremisesSyncEnabled -eq $false) -and
                                ($null -eq $_.onPremisesSecurityIdentifier -or $_.onPremisesSecurityIdentifier -eq "")
                            }
                            
                            if ($parentGroups) {
                                $parentGroupIds = $parentGroups.id
                                $parentGroupNames = $parentGroups.displayName | ForEach-Object {
                                    $_ -replace '"', '""' -replace ',', ';' -replace '\r?\n', ' '
                                }
                            }
                        }
                    } catch {
                        Write-Warning "    Error getting parent groups: $_"
                    }
                    
                    # ONLY OUTPUT IF GROUP HAS RELATIONSHIPS (children OR parents)
                    $totalRelationships = $nestedGroups.Count + $parentGroups.Count
                    
                    if ($totalRelationships -gt 0) {
                        # Use NULL for empty fields, output both IDs and names
                        $nestedGroupIdsString = if ($nestedGroupIds.Count -gt 0) { 
                            $nestedGroupIds -join " | " 
                        } else { 
                            "NULL" 
                        }
                        $nestedGroupNamesString = if ($nestedGroupNames.Count -gt 0) { 
                            $nestedGroupNames -join " | " 
                        } else { 
                            "NULL" 
                        }
                        $parentGroupIdsString = if ($parentGroupIds.Count -gt 0) { 
                            $parentGroupIds -join " | " 
                        } else { 
                            "NULL" 
                        }
                        $parentGroupNamesString = if ($parentGroupNames.Count -gt 0) { 
                            $parentGroupNames -join " | " 
                        } else { 
                            "NULL" 
                        }
                        
                        $line = "`"$($group.id)`",`"$($group.displayName -replace '"', '""')`",`"$groupType`",`"$nestedGroupIdsString`",`"$nestedGroupNamesString`",`"$($nestedGroups.Count)`",`"$parentGroupIdsString`",`"$parentGroupNamesString`",`"$($parentGroups.Count)`",`"$totalRelationships`""
                        $resultBuffer.Add($line)
                        $groupsWithRelationships++
                        $groupsWrittenToCSV++
                        
                        Write-Host "    ADDED: $($nestedGroups.Count) children, $($parentGroups.Count) parents (Total written: $groupsWrittenToCSV)" -ForegroundColor Green
                        
                        # Write to file IMMEDIATELY for small buffers (every 10 results)
                        if ($resultBuffer.Count -ge 10) {
                            Write-Host "    Writing $($resultBuffer.Count) results to CSV..." -ForegroundColor Cyan
                            
                            # DIRECT FILE WRITE
                            try {
                                if ($PSVersionTable.PSVersion.Major -ge 6) {
                                    $resultBuffer | Add-Content -Path $tempPath -Encoding UTF8
                                } else {
                                    $resultBuffer | Add-Content -Path $tempPath -Encoding Unicode
                                }
                                $resultBuffer.Clear()
                                
                                # VERIFY the write worked
                                $currentLines = (Get-Content $tempPath).Count
                                Write-Host "      Write successful! CSV now has $currentLines total lines" -ForegroundColor Green
                                
                            } catch {
                                Write-Error "       Write failed: $_"
                            }
                        }
                    } else {
                        Write-Host "    - No nesting relationships (skipped)" -ForegroundColor DarkYellow
                    }
                    
                } catch {
                    Write-Warning "  Error processing group $($group.displayName): $_"
                    
                    # Rate limiting on errors
                    if ($_.Exception.Message -match "throttled|rate limit|429") {
                        Write-Host "    Detected throttling - extended pause..." -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    }
                }
            }
            
            # Progress update every 500 groups
            if ($totalGroupsProcessed % 500 -eq 0) {
                Write-Host "  Progress: $totalGroupsProcessed total, $cloudOnlyGroupsFound cloud-only, $groupsWrittenToCSV written to CSV" -ForegroundColor Cyan
                
                # Save progress frequently
                $progress.ProcessedGroups = $totalGroupsProcessed
                $progress.CloudOnlyGroupsFound = $cloudOnlyGroupsFound
                $progress.GroupsWithRelationships = $groupsWithRelationships
                $progress.GroupsWrittenToCSV = $groupsWrittenToCSV
                $progress.LastBatchNumber = $batchNumber
                Save-Progress -Progress $progress -ProgressFile $progressFile
            }
        }
        
        Write-Host "Batch $batchNumber complete: $totalGroupsProcessed total, $cloudOnlyGroupsFound cloud-only, $groupsWrittenToCSV written to CSV" -ForegroundColor Gray
    }

    # Write any remaining buffer
    if ($resultBuffer.Count -gt 0) {
        Write-Host "Writing final $($resultBuffer.Count) results to CSV..." -ForegroundColor Cyan
        
        # DIRECT FILE WRITE with verification
        try {
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $resultBuffer | Add-Content -Path $tempPath -Encoding UTF8
            } else {
                $resultBuffer | Add-Content -Path $tempPath -Encoding Unicode
            }
            
            # FINAL VERIFICATION
            $finalLines = (Get-Content $tempPath).Count
            Write-Host "Final write successful! CSV has $finalLines total lines" -ForegroundColor Green
            
        } catch {
            Write-Error " Final write failed: $_"
        }
    }

    # Use repository's file management system
    $finalFileName = "$($config.FilePrefixes.EntraGroups)_Nested_$timestamp.csv"
    Move-ProcessedCSV -SourcePath $tempPath -FinalFileName $finalFileName -Config $config

    # Clean up progress file on success
    if (Test-Path $progressFile) {
        Remove-Item $progressFile -Force
    }

    # Final results
    Write-Host "Total groups processed: $totalGroupsProcessed" -ForegroundColor White
    Write-Host "Cloud-only groups found: $cloudOnlyGroupsFound" -ForegroundColor Cyan
    Write-Host "Groups with relationships (written to CSV): $groupsWrittenToCSV" -ForegroundColor Yellow
    Write-Host "Cloud-only groups excluded (no relationships): $($cloudOnlyGroupsFound - $groupsWrittenToCSV)" -ForegroundColor Gray

} catch {
    Write-Error "Error in nested groups collection: $_"
    
    # Save progress on error
    $progress.ProcessedGroups = $totalGroupsProcessed
    $progress.CloudOnlyGroupsFound = $cloudOnlyGroupsFound
    $progress.GroupsWithRelationships = $groupsWithRelationships
    $progress.GroupsWrittenToCSV = $groupsWrittenToCSV
    Save-Progress -Progress $progress -ProgressFile $progressFile
    
    throw
} finally {
    # Minimal cleanup
    if ($resultBuffer) {
        $resultBuffer.Clear()
        $resultBuffer = $null
    }
    
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    
    $finalMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
    Write-Host "Final memory: $([Math]::Round($finalMemory,1))GB" -ForegroundColor Gray
}