#Requires -Version 7.0
<#
.SYNOPSIS
    Collects ALL Entra ID permissions (Roles + Graph API) in a single combined CSV
.DESCRIPTION
    Combined script that collects both Entra role assignments and Graph API permissions
    Outputs single CSV with all permission types
    Uses empty strings for missing values (no NULL)
#>

[CmdletBinding()]
param(
    [string]$TestUser = $null  # Optional: specify a user to test with
)

# Import modules
Import-Module (Join-Path $PSScriptRoot "Modules\Common.Functions.psm1") -Force

# Get configuration
$config = Get-Config
Initialize-DataPaths -Config $config

# Setup paths
$timestamp = Get-Date -Format $config.FileManagement.DateFormat
$tempPath = Join-Path $config.Paths.Temp "EntraUsers-AllPermissions_$timestamp.csv"

# Initialize CSV with combined headers - Keep both IDs and Names
$csvHeader = "`"UserPrincipalName`",`"EntraRole`",`"EntraRoleType`",`"GraphPermissionType`",`"GraphPermission`",`"AppId`",`"AppName`",`"ResourceId`",`"ResourceName`""
Set-Content -Path $tempPath -Value $csvHeader -Encoding UTF8

try {
    # Connect to Graph
    Connect-ToGraph -Config $config.EntraID
    
    # Get security group members for role assignments
    $securityGroupMembers = Get-SecurityGroupMembers -Config $config.EntraID
    
    # Initialize processing variables
    $resultBuffer = [System.Collections.Generic.List[string]]::new()
    $totalProcessed = 0
    $permissionsFound = 0
    
    # ===========================================
    # STEP 1: Build ENTRA ROLE lookup table
    # ===========================================
    Write-Host "Building Entra role lookup table..."
    $userEntraRoles = @{}  # userId -> array of role assignments
    
    # Get all ACTIVE role assignments in bulk
    Write-Host "Collecting all active role assignments..."
    try {
        $activeAssignments = Invoke-GraphRequestWithPaging `
            -Uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal,roleDefinition&`$select=principalId,assignmentType,principal,roleDefinition" `
            -Config $config.EntraID
        
        Write-Host "Found $($activeAssignments.Count) active role assignments"
        
        foreach ($assignment in $activeAssignments) {
            # Determine assignment type
            $assignmentType = if ($assignment.assignmentType -eq "Assigned") {
                "Permanent"
            } else {
                "PIM"
            }
            
            # Process user assignments
            if ($assignment.principal.'@odata.type' -eq '#microsoft.graph.user') {
                $userId = $assignment.principal.id
                
                if (-not $userEntraRoles.ContainsKey($userId)) {
                    $userEntraRoles[$userId] = @()
                }
                
                $userEntraRoles[$userId] += @{
                    RoleName = $assignment.roleDefinition.displayName
                    AssignmentType = $assignmentType
                    UserPrincipalName = $assignment.principal.userPrincipalName
                }
            }
            # Process group assignments
            elseif ($assignment.principal.'@odata.type' -eq '#microsoft.graph.group' -and
                    $securityGroupMembers.ContainsKey($assignment.principal.id)) {
                
                $groupInfo = $securityGroupMembers[$assignment.principal.id]
                $groupAssignmentType = "Group-$assignmentType ($($groupInfo.GroupDisplayName))"
                
                foreach ($member in $groupInfo.Members) {
                    if ($member.Type -eq "User" -and $member.UserPrincipalName) {
                        $memberKey = $member.UserPrincipalName.ToLower()
                        
                        if (-not $userEntraRoles.ContainsKey($memberKey)) {
                            $userEntraRoles[$memberKey] = @()
                        }
                        
                        $userEntraRoles[$memberKey] += @{
                            RoleName = $assignment.roleDefinition.displayName
                            AssignmentType = $groupAssignmentType
                            UserPrincipalName = $member.UserPrincipalName
                            IsGroupBased = $true
                        }
                    }
                }
            }
        }
        
        $activeAssignments = $null
        [System.GC]::Collect()
        
    } catch {
        Write-Warning "Error collecting active role assignments: $_"
    }
    
    # Get all ELIGIBLE role assignments in bulk
    Write-Host "Collecting all eligible role assignments..."
    try {
        $eligibleAssignments = Invoke-GraphRequestWithPaging `
            -Uri "https://graph.microsoft.com/beta/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal,roleDefinition&`$select=principalId,principal,roleDefinition" `
            -Config $config.EntraID
        
        Write-Host "Found $($eligibleAssignments.Count) eligible role assignments"
        
        foreach ($assignment in $eligibleAssignments) {
            # Process user assignments
            if ($assignment.principal.'@odata.type' -eq '#microsoft.graph.user') {
                $userId = $assignment.principal.id
                
                if (-not $userEntraRoles.ContainsKey($userId)) {
                    $userEntraRoles[$userId] = @()
                }
                
                $userEntraRoles[$userId] += @{
                    RoleName = $assignment.roleDefinition.displayName
                    AssignmentType = "PIM"
                    UserPrincipalName = $assignment.principal.userPrincipalName
                }
            }
            # Process group assignments
            elseif ($assignment.principal.'@odata.type' -eq '#microsoft.graph.group' -and
                    $securityGroupMembers.ContainsKey($assignment.principal.id)) {
                
                $groupInfo = $securityGroupMembers[$assignment.principal.id]
                $groupAssignmentType = "Group-PIM ($($groupInfo.GroupDisplayName))"
                
                foreach ($member in $groupInfo.Members) {
                    if ($member.Type -eq "User" -and $member.UserPrincipalName) {
                        $memberKey = $member.UserPrincipalName.ToLower()
                        
                        if (-not $userEntraRoles.ContainsKey($memberKey)) {
                            $userEntraRoles[$memberKey] = @()
                        }
                        
                        $userEntraRoles[$memberKey] += @{
                            RoleName = $assignment.roleDefinition.displayName
                            AssignmentType = $groupAssignmentType
                            UserPrincipalName = $member.UserPrincipalName
                            IsGroupBased = $true
                        }
                    }
                }
            }
        }
        
        $eligibleAssignments = $null
        [System.GC]::Collect()
        
    } catch {
        Write-Warning "Error collecting eligible role assignments: $_"
    }
    
    Write-Host "Entra role lookup table built with $($userEntraRoles.Count) entries"
    
    # ===========================================
    # STEP 2: Build GRAPH PERMISSIONS lookup table
    # ===========================================
    Write-Host "Building Graph permissions lookup table..."
    $userGraphPermissions = @{}  # userId -> array of graph permissions
    $spCache = @{}  # Service principal cache
    
    # Get all OAuth2 permission grants (delegated permissions) in bulk
    Write-Host "Collecting all OAuth2 permission grants..."
    try {
        $oauth2Grants = Invoke-GraphRequestWithPaging `
            -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" `
            -Config $config.EntraID
        
        Write-Host "Found $($oauth2Grants.Count) OAuth2 permission grants"
        
        foreach ($grant in $oauth2Grants) {
            if ($grant.principalId -and $grant.scope) {
                # Get service principal info for resource (API being accessed)
                if ($grant.resourceId -and -not $spCache.ContainsKey($grant.resourceId)) {
                    try {
                        $sp = Invoke-GraphWithRetry `
                            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($grant.resourceId)" `
                            -Config $config.EntraID
                        
                        $spCache[$grant.resourceId] = @{
                            AppId = $sp.appId
                            DisplayName = $sp.displayName
                        }
                    }
                    catch {
                        # Cache miss
                    }
                }
                
                $resourceInfo = $spCache[$grant.resourceId]
                
                # Process each scope
                foreach ($scope in ($grant.scope -split ' ')) {
                    if ([string]::IsNullOrWhiteSpace($scope)) { continue }
                    
                    if (-not $userGraphPermissions.ContainsKey($grant.principalId)) {
                        $userGraphPermissions[$grant.principalId] = @()
                    }
                    
                    $userGraphPermissions[$grant.principalId] += @{
                        PermissionType = "Delegated"
                        Permission = $scope
                        AppId = $grant.clientId
                        AppName = ""  # Client app name not available from OAuth2 grants
                        ResourceId = if ($resourceInfo) { $resourceInfo.AppId } else { "" }
                        ResourceName = if ($resourceInfo) { $resourceInfo.DisplayName } else { "" }
                    }
                }
            }
        }
        
        $oauth2Grants = $null
        [System.GC]::Collect()
        
    } catch {
        Write-Warning "Error collecting OAuth2 permission grants: $_"
    }
    
    Write-Host "Graph permissions lookup table built with $($userGraphPermissions.Count) users"
    
    # ===========================================
    # STEP 3: Process users and combine permissions
    # ===========================================
    Write-Host "Processing users in batches..."
    $batchSize = $config.EntraID.BatchSize
    $batchNumber = 0
    
    if ($TestUser) {
        $nextLink = "https://graph.microsoft.com/v1.0/users?`$filter=startsWith(userPrincipalName,'$TestUser')&`$select=id,userPrincipalName&`$top=$batchSize"
        Write-Host "Testing with user: $TestUser"
    } else {
        $nextLink = Get-InitialUserQuery -Config $config.EntraID -SelectFields "id,userPrincipalName" -BatchSize $batchSize
    }
    
    while ($nextLink) {
        $batchNumber++
        Write-Host "Processing user batch $batchNumber..."
        
        # Check memory
        if (Test-MemoryPressure -ThresholdGB $config.EntraID.MemoryThresholdGB `
                                -WarningGB $config.EntraID.MemoryWarningThresholdGB) {
            if ($resultBuffer.Count -gt 0) {
                Write-BufferToFile -Buffer $resultBuffer -FilePath $tempPath
            }
            
            # Clear caches if too large
            if ($spCache.Count -gt 10000) {
                $spCache.Clear()
            }
        }
        
        # Get batch
        $batchData = Get-GraphBatch -NextLink $nextLink -Config $config.EntraID
        $users = $batchData.Items
        $nextLink = $batchData.NextLink
        
        if ($users.Count -gt 0) {
            foreach ($user in $users) {
                $userHasAnyPermissions = $false
                
                # ===========================================
                # OUTPUT ENTRA ROLES
                # ===========================================
                $userEntraRoleList = @()
                
                # Check direct user roles (by userId)
                if ($userEntraRoles.ContainsKey($user.id)) {
                    $userEntraRoleList += $userEntraRoles[$user.id]
                }
                
                # Check group-based roles (by UPN)
                $upnKey = $user.userPrincipalName.ToLower()
                if ($userEntraRoles.ContainsKey($upnKey)) {
                    $userEntraRoleList += $userEntraRoles[$upnKey]
                }
                
                # Write Entra role assignments
                if ($userEntraRoleList.Count -gt 0) {
                    foreach ($role in $userEntraRoleList) {
                        $line = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`",`"{8}`"" -f `
                            $user.userPrincipalName,
                            $role.RoleName,
                            $role.AssignmentType,
                            "",
                            "",
                            "",
                            "",
                            "",
                            ""
                        $resultBuffer.Add($line)
                        $permissionsFound++
                        $userHasAnyPermissions = $true
                    }
                }
                
                # ===========================================
                # OUTPUT GRAPH DELEGATED PERMISSIONS
                # ===========================================
                if ($userGraphPermissions.ContainsKey($user.id)) {
                    foreach ($permission in $userGraphPermissions[$user.id]) {
                        $line = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`",`"{8}`"" -f `
                            $user.userPrincipalName,
                            "",
                            "",
                            $permission.PermissionType,
                            $permission.Permission,
                            $permission.AppId,
                            $permission.AppName,
                            $permission.ResourceId,
                            $permission.ResourceName
                        
                        $resultBuffer.Add($line)
                        $permissionsFound++
                        $userHasAnyPermissions = $true
                    }
                }
                
                # ===========================================
                # OUTPUT GRAPH APPLICATION PERMISSIONS (per user)
                # ===========================================
                try {
                    $appRoleAssignments = Invoke-GraphWithRetry `
                        -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)/appRoleAssignments" `
                        -Config $config.EntraID
                    
                    foreach ($assignment in $appRoleAssignments.value) {
                        # Get service principal info
                        if ($assignment.resourceId -and -not $spCache.ContainsKey($assignment.resourceId)) {
                            try {
                                $sp = Invoke-GraphWithRetry `
                                    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($assignment.resourceId)" `
                                    -Config $config.EntraID
                                
                                $spCache[$assignment.resourceId] = @{
                                    AppRoles = $sp.appRoles
                                    DisplayName = $sp.displayName
                                    AppId = $sp.appId
                                }
                            }
                            catch {
                                # Cache miss
                            }
                        }
                        
                        $spInfo = $spCache[$assignment.resourceId]
                        
                        if ($spInfo) {
                            $appRole = $spInfo.AppRoles | Where-Object { $_.Id -eq $assignment.appRoleId }
                            
                            if ($appRole) {
                                $line = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`",`"{8}`"" -f `
                                    $user.userPrincipalName,
                                    "",
                                    "",
                                    "Application",
                                    $appRole.Value,
                                    $spInfo.AppId,
                                    $spInfo.DisplayName,
                                    $assignment.resourceId,
                                    $spInfo.DisplayName
                                
                                $resultBuffer.Add($line)
                                $permissionsFound++
                                $userHasAnyPermissions = $true
                            }
                        }
                    }
                }
                catch {
                    # Error getting app role assignments for this user - continue
                }
                
                # If user has NO permissions at all, add empty entry
                if (-not $userHasAnyPermissions) {
                    $line = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`",`"{8}`"" -f `
                        $user.userPrincipalName,
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        "",
                        ""
                    $resultBuffer.Add($line)
                }
                
                $totalProcessed++
                
                # Write buffer when full
                if ($resultBuffer.Count -ge $config.ActiveDirectory.BufferLimit) {
                    Write-BufferToFile -Buffer $resultBuffer -FilePath $tempPath
                }
            }
            
            Write-Host "Completed batch $batchNumber. Total users processed: $totalProcessed... Found $permissionsFound permissions"
        }
        
        # Clear batch data
        $users = $null
        $batchData = $null
    }
    
    # Write remaining buffer
    if ($resultBuffer.Count -gt 0) {
        Write-BufferToFile -Buffer $resultBuffer -FilePath $tempPath
    }
    
    Write-Host "Processing complete!" -ForegroundColor Green
    Write-Host "Total users processed: $totalProcessed" -ForegroundColor Cyan
    Write-Host "Total permissions found: $permissionsFound" -ForegroundColor Cyan
    
    # Move to final location
    Move-ProcessedCSV -SourcePath $tempPath -FinalFileName "EntraUsers-AllPermissions_$timestamp.csv" -Config $config

} catch {
    Write-Error "Error collecting permissions: $_"
    throw
} finally {
    # Clean up
    if ($resultBuffer) { 
        $resultBuffer.Clear()
        $resultBuffer = $null
    }
    if ($userEntraRoles) {
        $userEntraRoles.Clear()
        $userEntraRoles = $null
    }
    if ($userGraphPermissions) {
        $userGraphPermissions.Clear()
        $userGraphPermissions = $null
    }
    if ($spCache) {
        $spCache.Clear()
        $spCache = $null
    }
    if ($securityGroupMembers) {
        $securityGroupMembers.Clear()
        $securityGroupMembers = $null
    }
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}