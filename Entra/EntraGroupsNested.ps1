#Requires -Version 7.0
<#
.SYNOPSIS
    Shows cloud-only groups with nesting relationships
.DESCRIPTION
    Collects group nesting data (parent/child relationships), Outputs one row per relationship (either Contains or MemberOf)
    Outputs ONE separate CSV files:
    1. EntraGroups-Relationships
#>

[CmdletBinding()]
param(
    [string]$TestGroup = $null  # Optional: specify a group to test with
)

# Configuration
Import-Module (Resolve-Path (Join-Path $PSScriptRoot "Common.Functions.psm1")) -Force
$config = Get-Config

# Setup paths for outputs
$timestamp = Get-Date -Format $config.FileManagement.DateFormat
$tempPath = Join-Path $config.Paths.Temp "EntraGroups-Relationships_$timestamp.csv"
$progressFile = Join-Path $config.Paths.Temp "EntraGroups-Relationships_progress.json"

# Initialize CSV with relationship headers (one row per relationship)
$csvHeader = "`"GroupId`",`"GroupName`",`"GroupType`",`"RelatedGroupId`",`"RelatedGroupName`",`"RelationshipType`""
if ($PSVersionTable.PSVersion.Major -ge 6) {
    Set-Content -Path $tempPath -Value $csvHeader -Encoding UTF8
} else {
    Set-Content -Path $tempPath -Value $csvHeader -Encoding Unicode
}

# Load progress
$progress = Get-Progress -ProgressFile $progressFile
if (-not $progress) {
    $progress = @{
        ProcessedGroups          = 0
        CloudOnlyGroupsFound     = 0
        RelationshipsWritten     = 0
        LastBatchNumber          = 0
        StartTime                = (Get-Date).ToString('o')
    }
}

try {
    # Connect to Graph
    Connect-ToGraph -Config $config.EntraID

    #  memory footprint - only small buffer for CSV writing
    $resultBuffer = [System.Collections.Generic.List[string]]::new()

    # Counters
    $totalGroupsProcessed = $progress.ProcessedGroups
    $cloudOnlyGroupsFound = $progress.CloudOnlyGroupsFound
    $relationshipsWritten = $progress.RelationshipsWritten
    $batchNumber = $progress.LastBatchNumber

    # Build query
    if ($TestGroup) {
        $nextLink = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$TestGroup'&`$select=displayName,id,onPremisesSyncEnabled,onPremisesSecurityIdentifier,securityEnabled,mailEnabled,mail&`$top=$($config.EntraID.BatchSize)"
        Write-Verbose "Testing with group: $TestGroup"
    } else {
        $nextLink = "https://graph.microsoft.com/v1.0/groups?`$select=displayName,id,onPremisesSyncEnabled,onPremisesSecurityIdentifier,securityEnabled,mailEnabled,mail&`$top=$($config.EntraID.BatchSize)"
    }

    # Process each group immediately as we find it
    while ($nextLink) {
        $batchNumber++
        Write-Verbose "Processing batch $batchNumber..."
        
        # Memory check
        if (Test-MemoryPressure -ThresholdGB $config.EntraID.MemoryThresholdGB `
                                -WarningGB $config.EntraID.MemoryWarningThresholdGB) {
            Write-Verbose "Memory pressure - writing buffer..."
            if ($resultBuffer.Count -gt 0) {
                Write-Verbose "Emergency write: $($resultBuffer.Count) lines"
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
            Write-Verbose "  No more groups found"
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
                
                Write-Verbose "  Checking: $($group.displayName)"
                
                try {
                    # Rate limiting to prevent Graph timeouts
                    if ($cloudOnlyGroupsFound % 10 -eq 0) {
                        Start-Sleep -Milliseconds 100
                    }
                    
                    # RELATIONSHIP 1: What cloud-only groups does this group contain? (Children)
                    $nestedGroups = @()
                    
                    try {
                        $membersUri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/transitiveMembers/microsoft.graph.group?`$select=id,displayName,onPremisesSyncEnabled,onPremisesSecurityIdentifier"
                        $nestedResponse = Invoke-GraphWithRetry -Uri $membersUri -Config $config.EntraID
                        
                        if ($nestedResponse.value) {
                            # Filter to only cloud-only nested groups
                            $nestedGroups = $nestedResponse.value | Where-Object {
                                ($null -eq $_.onPremisesSyncEnabled -or $_.onPremisesSyncEnabled -eq $false) -and
                                ($null -eq $_.onPremisesSecurityIdentifier -or $_.onPremisesSecurityIdentifier -eq "")
                            }
                        }
                    } catch {
                        Write-Warning "Error getting nested groups: $_"
                    }
                    
                    # RELATIONSHIP 2: What cloud-only groups contain this group? (Parents)
                    $parentGroups = @()
                    
                    try {
                        $memberOfUri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName,onPremisesSyncEnabled,onPremisesSecurityIdentifier"
                        $parentResponse = Invoke-GraphWithRetry -Uri $memberOfUri -Config $config.EntraID
                        
                        if ($parentResponse.value) {
                            # Filter to only cloud-only parent groups
                            $parentGroups = $parentResponse.value | Where-Object {
                                ($null -eq $_.onPremisesSyncEnabled -or $_.onPremisesSyncEnabled -eq $false) -and
                                ($null -eq $_.onPremisesSecurityIdentifier -or $_.onPremisesSecurityIdentifier -eq "")
                            }
                        }
                    } catch {
                        Write-Warning "Error getting parent groups: $_"
                    }
                    
                    # OUTPUT ONE ROW PER NESTED GROUP (Contains relationship)
                    if ($nestedGroups.Count -gt 0) {
                        foreach ($nestedGroup in $nestedGroups) {
                            $line = "`"$($group.id)`",`"$($group.displayName -replace '"', '""')`",`"$groupType`",`"$($nestedGroup.id)`",`"$($nestedGroup.displayName -replace '"', '""')`",`"Contains`""
                            $resultBuffer.Add($line)
                            $relationshipsWritten++
                        }
                    }
                    
                    # OUTPUT ONE ROW PER PARENT GROUP (MemberOf relationship)
                    if ($parentGroups.Count -gt 0) {
                        foreach ($parentGroup in $parentGroups) {
                            $line = "`"$($group.id)`",`"$($group.displayName -replace '"', '""')`",`"$groupType`",`"$($parentGroup.id)`",`"$($parentGroup.displayName -replace '"', '""')`",`"MemberOf`""
                            $resultBuffer.Add($line)
                            $relationshipsWritten++
                        }
                    }
                    
                    if ($nestedGroups.Count -gt 0 -or $parentGroups.Count -gt 0) {
                        Write-Verbose "ADDED: $($nestedGroups.Count) children, $($parentGroups.Count) parents (Total written: $relationshipsWritten)"
                        
                        # Write to file for small buffers (every 10 results)
                        if ($resultBuffer.Count -ge 10) {
                            Write-Verbose "Writing $($resultBuffer.Count) results to CSV..."
                            
                            # DIRECT FILE WRITE
                            try {
                                if ($PSVersionTable.PSVersion.Major -ge 6) {
                                    $resultBuffer | Add-Content -Path $tempPath -Encoding UTF8
                                } else {
                                    $resultBuffer | Add-Content -Path $tempPath -Encoding Unicode
                                }
                                $resultBuffer.Clear()                      
                            } catch {
                                Write-Error "Write failed: $_"
                            }
                        }
                    } else {
                        Write-Verbose "- No nesting relationships (skipped)"
                    }
                    
                } catch {
                    Write-Warning "Error processing group $($group.displayName): $_"
                    
                    # Rate limiting on errors
                    if ($_.Exception.Message -match "throttled|rate limit|429") {
                        Write-Verbose "Detected throttling - extended pause..."
                        Start-Sleep -Seconds 2
                    }
                }
            }
            
            # Progress update every 500 groups
            if ($totalGroupsProcessed % 500 -eq 0) {
                Write-Verbose "Progress: $totalGroupsProcessed total, $cloudOnlyGroupsFound cloud-only, $relationshipsWritten relationships written"
                
                # Save progress frequently
                $progress.ProcessedGroups = $totalGroupsProcessed
                $progress.CloudOnlyGroupsFound = $cloudOnlyGroupsFound
                $progress.RelationshipsWritten = $relationshipsWritten
                $progress.LastBatchNumber = $batchNumber
                Save-Progress -Progress $progress -ProgressFile $progressFile
            }
        }
        
        Write-Verbose "Batch $batchNumber complete: $totalGroupsProcessed total, $cloudOnlyGroupsFound cloud-only, $relationshipsWritten relationships written"
    }

    # Write any remaining buffer
    if ($resultBuffer.Count -gt 0) {
        Write-Verbose "Writing final $($resultBuffer.Count) results to CSV..."
        
        # DIRECT FILE WRITE with verification
        try {
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $resultBuffer | Add-Content -Path $tempPath -Encoding UTF8
            } else {
                $resultBuffer | Add-Content -Path $tempPath -Encoding Unicode
            }
            
            # FINAL VERIFICATION
            $finalLines = (Get-Content $tempPath).Count
            Write-Verbose "Final write successful! CSV has $finalLines total lines"
            
        } catch {
            Write-Error "Final write failed: $_"
        }
    }

    $finalFileName = "EntraGroups-Relationships_$timestamp.csv"
    Move-ProcessedCSV -SourcePath $tempPath -FinalFileName $finalFileName -Config $config

    # Clean up progress file on success
    if (Test-Path $progressFile) {
        Remove-Item $progressFile -Force
    }

    # Final results
    Write-Verbose "Total groups processed: $totalGroupsProcessed"

} catch {
    Write-Error "Error in nested groups collection: $_"
    
    # Save progress on error
    $progress.ProcessedGroups = $totalGroupsProcessed
    $progress.CloudOnlyGroupsFound = $cloudOnlyGroupsFound
    $progress.RelationshipsWritten = $relationshipsWritten
    Save-Progress -Progress $progress -ProgressFile $progressFile
    
    throw
} finally {
    #  cleanup
    if ($resultBuffer) {
        $resultBuffer.Clear()
        $resultBuffer = $null
    }
    
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    
    $finalMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
    Write-Verbose "Final memory: $([Math]::Round($finalMemory,1))GB"
}