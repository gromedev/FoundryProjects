#Requires -Version 7.0
<#
.SYNOPSIS
    Collects Entra ID user data AND group memberships in a single pass
.DESCRIPTION
    Combined script that collects both basic user data and group memberships
    Outputs two separate CSV files from a single user iteration
#>

[CmdletBinding()]
param()

# Import modules
Import-Module (Resolve-Path (Join-Path $PSScriptRoot "Modules\Common.Functions.psm1")) -Force

# Get configuration
$config = Get-Config
Initialize-DataPaths -Config $config

Write-Host $PSScriptRoot

# Setup paths for BOTH outputs
$timestamp = Get-Date -Format $config.FileManagement.DateFormat
$tempPathUsers = Join-Path $config.Paths.Temp "$($config.FilePrefixes.EntraUsers)_$timestamp.csv"
$tempPathGroups = Join-Path $config.Paths.Temp "$($config.FilePrefixes.EntraGroups)_$timestamp.csv"

# Initialize CSV headers - Keep both GroupId AND GroupName
$csvHeaderUsers = "`"UserPrincipalName`",`"Id`",`"accountEnabled`",`"UserType`",`"assignedLicenses`",`"CustomSecurityAttributes`",`"createdDateTime`",`"LastSignInDateTime`",`"OnPremisesSyncEnabled`",`"OnPremisesSamAccountName`",`"PasswordPolicies`""
Set-Content -Path $tempPathUsers -Value $csvHeaderUsers -Encoding UTF8

$csvHeaderGroups = "`"UserPrincipalName`",`"GroupId`",`"GroupName`",`"GroupRoleAssignable`",`"GroupType`",`"GroupMembershipType`",`"GroupSecurityEnabled`",`"MembershipPath`""
Set-Content -Path $tempPathGroups -Value $csvHeaderGroups -Encoding UTF8

# Initialize mutexes for thread-safe file writing (one per file)
$mutexUsers = [System.Threading.Mutex]::new($false, "EntraUsersCSVMutex")
$mutexGroups = [System.Threading.Mutex]::new($false, "EntraGroupsCSVMutex")

try {
    # Connect to Graph
    Connect-ToGraph -Config $config.EntraID
    
    # Get SKU mapping for licenses
    Write-Host "Getting license SKU mappings..."
    $skus = Get-MgSubscribedSku
    $skuLookup = @{}
    foreach ($sku in $skus) {
        $skuLookup[$sku.SkuId] = $sku.SkuPartNumber
    }
    
    # Initialize group cache (shared across parallel processing)
    $script:groupCache = @{}

    # Initialize batch processing
    $batchSize = $config.EntraID.BatchSize
    $totalProcessed = 0
    $batchNumber = 0
    
    # Build initial query
    $selectFields = "userPrincipalName,id,accountEnabled,userType,assignedLicenses,customSecurityAttributes,createdDateTime,signInActivity,onPremisesSyncEnabled,onPremisesSamAccountName,passwordPolicies"
    $nextLink = Get-InitialUserQuery -Config $config.EntraID -SelectFields $selectFields -BatchSize $batchSize
    
    Write-Host "Starting combined user and group collection..."
    
    while ($nextLink) {
        $batchNumber++
        Write-Host "Processing batch $batchNumber..."
        
        # Check memory only every 10 batches
        if ($batchNumber % 10 -eq 0) {
            if (Test-MemoryPressure -ThresholdGB $config.EntraID.MemoryThresholdGB `
                                    -WarningGB $config.EntraID.MemoryWarningThresholdGB) {
                # Clear group cache if it gets too large
                if ($script:groupCache.Count -gt 1000) {
                    $script:groupCache.Clear()
                }
            }
        }
        
        # Get batch directly
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
        $users = $response.value
        $nextLink = $response.'@odata.nextLink'
        
        if ($users.Count -gt 0) {
            # Pre-convert dates and booleans before parallel processing
            foreach ($user in $users) {
                # Standardize datetime values
                $user | Add-Member -NotePropertyName 'StandardCreatedDateTime' -NotePropertyValue $(
                    if ($user.createdDateTime) { 
                        Convert-ToStandardDateTime -DateValue $user.createdDateTime -SourceFormat 'GraphAPI' 
                    } else { "" }
                )
                $user | Add-Member -NotePropertyName 'StandardLastSignInDateTime' -NotePropertyValue $(
                    if ($user.signInActivity.lastSignInDateTime) { 
                        Convert-ToStandardDateTime -DateValue $user.signInActivity.lastSignInDateTime -SourceFormat 'GraphAPI' 
                    } else { "" }
                )
                
                # Standardize boolean values
                $user | Add-Member -NotePropertyName 'StandardAccountEnabled' -NotePropertyValue $(
                    if ($null -ne $user.accountEnabled) { if ($user.accountEnabled) { "1" } else { "0" } } else { "" }
                )
                $user | Add-Member -NotePropertyName 'StandardOnPremisesSyncEnabled' -NotePropertyValue $(
                    if ($null -ne $user.onPremisesSyncEnabled) { if ($user.onPremisesSyncEnabled) { "1" } else { "0" } } else { "" }
                )
            }
            
            # Process users in parallel - collect BOTH user data AND group memberships
            $batchResultsUsers = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            $batchResultsGroups = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
            
            $users | ForEach-Object -ThrottleLimit $config.EntraID.ParallelThrottle -Parallel {
                # Import module in parallel scope
                Import-Module (Join-Path $using:PSScriptRoot "Modules\Common.Functions.psm1") -Force
                
                $user = $_
                $localBatchResultsUsers = $using:batchResultsUsers
                $localBatchResultsGroups = $using:batchResultsGroups
                $localSkuLookup = $using:skuLookup
                $localConfig = $using:config
                $localGroupCache = $using:groupCache
                $errorValue = "NULL"
                
                try {
                    # ===========================================
                    # PART 1: USER BASIC DATA
                    # ===========================================
                    
                    # Convert licenses to SKU names
                    $licenses = if ($user.assignedLicenses) {
                        ($user.assignedLicenses.skuId | ForEach-Object { 
                            $localSkuLookup[$_] 
                        } | Where-Object { $_ }) -join ' | '
                    } else { $errorValue }
                    
                    # Handle custom attributes
                    $attributes = if ($user.customSecurityAttributes -and 
                                     ($user.customSecurityAttributes | ConvertTo-Json -Compress) -ne "null") {
                        $user.customSecurityAttributes | ConvertTo-Json -Compress
                    } else { $errorValue }
                    
                    # Use pre-converted values
                    $createdDateTime = if ($user.StandardCreatedDateTime) { $user.StandardCreatedDateTime } else { $errorValue }
                    $lastSignInDateTime = if ($user.StandardLastSignInDateTime) { $user.StandardLastSignInDateTime } else { $errorValue }
                    
                    # Build user data line (UserIdentifier removed)
                    $lineUser = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`",`"{8}`",`"{9}`",`"{10}`"" -f `
                        ($user.userPrincipalName ?? $errorValue),
                        ($user.id ?? $errorValue),
                        ($user.StandardAccountEnabled ?? $errorValue),
                        ($user.userType ?? $errorValue),
                        $licenses,
                        $attributes,
                        $createdDateTime,
                        $lastSignInDateTime,
                        ($user.StandardOnPremisesSyncEnabled ?? $errorValue),
                        ($user.onPremisesSamAccountName ?? $errorValue),
                        ($user.passwordPolicies ?? $errorValue)
                    
                    $localBatchResultsUsers.Add($lineUser)
                    
                    # ===========================================
                    # PART 2: USER GROUP MEMBERSHIPS
                    # ===========================================
                    
                    # Get user's direct group memberships
                    $directGroups = Invoke-GraphWithRetry `
                        -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)/memberOf" `
                        -Config $localConfig.EntraID
                    
                    # Get group IDs for direct memberships
                    $directGroupIds = @($directGroups.value | 
                        Where-Object { $_.'@odata.type' -eq "#microsoft.graph.group" } | 
                        Select-Object -ExpandProperty id)
                    
                    # Get all group memberships (direct + transitive)
                    $userGroups = Invoke-GraphWithRetry `
                        -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)/transitiveMemberOf" `
                        -Config $localConfig.EntraID
                    
                    if (-not $userGroups.value -or $userGroups.value.Count -eq 0) {
                        # User has no groups - add empty entry
                        $lineGroup = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`"" -f `
                            $user.userPrincipalName,
                            $errorValue,
                            $errorValue,
                            $errorValue,
                            $errorValue,
                            $errorValue,
                            $errorValue,
                            $errorValue
                        $localBatchResultsGroups.Add($lineGroup)
                    }
                    else {
                        foreach ($group in $userGroups.value) {
                            if ($group.'@odata.type' -ne "#microsoft.graph.group") { continue }
                            
                            # Determine if direct or inherited
                            $isDirectMember = $directGroupIds -contains $group.id
                            $membershipPath = if ($isDirectMember) { "Direct" } else { "Inherited" }
                            
                            # Get group info from cache or determine on the fly
                            if (-not $localGroupCache.ContainsKey($group.id)) {
                                # Determine group type
                                $groupType = if ($group.groupTypes.Count -eq 0) {
                                    if (-not $group.mailEnabled -and $group.securityEnabled) {
                                        "Security"
                                    }
                                    elseif ($group.mailEnabled -and $group.securityEnabled) {
                                        "Mail-enabled Security"
                                    }
                                    elseif ($group.mailEnabled -and -not $group.securityEnabled) {
                                        "Distribution"
                                    }
                                    else {
                                        $errorValue
                                    }
                                }
                                else {
                                    "Microsoft 365"
                                }
                                
                                $localGroupCache[$group.id] = @{
                                    DisplayName = $group.displayName
                                    IsAssignableToRole = if ($null -eq $group.isAssignableToRole) { "0" } else { if ($group.isAssignableToRole) { "1" } else { "0" } }
                                    SecurityEnabled = if ($null -ne $group.securityEnabled) { if ($group.securityEnabled) { "1" } else { "0" } } else { "" }
                                    Type = $groupType
                                    MembershipType = if ($group.membershipRule) { "Dynamic" } else { "Assigned" }
                                }
                            }
                            
                            $groupInfo = $localGroupCache[$group.id]
                            
                            # Format CSV line with both GroupId and GroupName
                            $lineGroup = "`"{0}`",`"{1}`",`"{2}`",`"{3}`",`"{4}`",`"{5}`",`"{6}`",`"{7}`"" -f `
                                $user.userPrincipalName,
                                $group.id,
                                $groupInfo.DisplayName,
                                $groupInfo.IsAssignableToRole,
                                $groupInfo.Type,
                                $groupInfo.MembershipType,
                                $groupInfo.SecurityEnabled,
                                $membershipPath
                            
                            $localBatchResultsGroups.Add($lineGroup)
                        }
                    }
                }
                catch {
                    Write-Warning "Error processing user $($user.userPrincipalName): $_"
                }
            }
            
            # Write BOTH batches to their respective files (thread-safe)
            if ($batchResultsUsers.Count -gt 0) {
                try {
                    $mutexUsers.WaitOne() | Out-Null
                    $batchResultsUsers | Add-Content -Path $tempPathUsers -Encoding UTF8
                }
                finally {
                    $mutexUsers.ReleaseMutex()
                }
            }
            
            if ($batchResultsGroups.Count -gt 0) {
                try {
                    $mutexGroups.WaitOne() | Out-Null
                    $batchResultsGroups | Add-Content -Path $tempPathGroups -Encoding UTF8
                }
                finally {
                    $mutexGroups.ReleaseMutex()
                }
            }
            
            $totalProcessed += $users.Count
            Write-Host "Completed batch $batchNumber. Total users processed: $totalProcessed"
        }
    }
    
    Write-Host "Processing complete. Total users processed: $totalProcessed" -ForegroundColor Green
    
    # Move BOTH files to final location
    Move-ProcessedCSV -SourcePath $tempPathUsers -FinalFileName "$($config.FilePrefixes.EntraUsers)_$timestamp.csv" -Config $config
    Move-ProcessedCSV -SourcePath $tempPathGroups -FinalFileName "$($config.FilePrefixes.EntraGroups)_$timestamp.csv" -Config $config
}
catch {
    Write-Error "Error collecting Entra users and groups: $_"
    throw
}
finally {
    if ($mutexUsers) { $mutexUsers.Dispose() }
    if ($mutexGroups) { $mutexGroups.Dispose() }
    if ($script:groupCache) {
        $script:groupCache.Clear()
    }
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}