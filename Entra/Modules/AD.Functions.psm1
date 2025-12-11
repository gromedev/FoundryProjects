#Requires -Version 7.0
<#
.SYNOPSIS
    Active Directory specific functions

    Removed
        Get-ADGroupMemberCount
#>

# Import common functions
Import-Module (Join-Path $PSScriptRoot "Common.Functions.psm1") -Force

#region LDAP Connection Management
function New-LDAPConnection {
    param (
        [Parameter(Mandatory)]
        [object]$Config,
        
        [int]$RetryCount = 0
    )
    
    $maxRetries = $Config.RetryAttempts
    
    while ($RetryCount -lt $maxRetries) {
        try {
            Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction Stop
            
            $domain = ($env:USERDNSDOMAIN -split '\.')[0]
            $identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($domain, 389)
            $connection = New-Object System.DirectoryServices.Protocols.LdapConnection($identifier)
            $connection.SessionOptions.ProtocolVersion = 3
            $connection.SessionOptions.ReferralChasing = 'None'
            $connection.Timeout = New-TimeSpan -Seconds $Config.SearchTimeoutSeconds
            
            return $connection
        }
        catch {
            $RetryCount++
            if ($RetryCount -lt $maxRetries) {
                Write-Warning "LDAP connection failed, attempt $RetryCount of $maxRetries. Retrying in $($Config.RetryDelaySeconds) seconds..."
                Start-Sleep -Seconds $Config.RetryDelaySeconds
            }
            else {
                throw "Failed to establish LDAP connection after $maxRetries attempts: $_"
            }
        }
    }
}

function New-LDAPSearchRequest {
    param (
        [string]$SearchBase,
        [string]$Filter,
        [string[]]$Attributes
    )
    
    $searchRequest = New-Object System.DirectoryServices.Protocols.SearchRequest
    $searchRequest.DistinguishedName = $SearchBase
    $searchRequest.Filter = $Filter
    $searchRequest.Scope = [System.DirectoryServices.Protocols.SearchScope]::Subtree
    
    if ($Attributes) {
        $searchRequest.Attributes.AddRange($Attributes)
    }
    
    return $searchRequest
}
#endregion

#region Group Filtering Functions
function Get-ADGroupFilter {
    param (
        [Parameter(Mandatory)]
        [object]$Config
    )
    if ($Config.ScopeToGroup -and $Config.TargetGroup) {
        Write-Host "Scoping AD collection to group: $($Config.TargetGroup)"
        # Get group DN
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $searchBase = $domain.GetDirectoryEntry().distinguishedName
        $groupSearcher = [System.DirectoryServices.DirectorySearcher]::new([ADSI]"LDAP://$searchBase")
        $groupSearcher.Filter = "(&(objectClass=group)(name=$($Config.TargetGroup)))"
        $groupSearcher.PropertiesToLoad.Add("distinguishedName") | Out-Null
        $groupResult = $groupSearcher.FindOne()
        if (-not $groupResult) {
            throw "Group '$($Config.TargetGroup)' not found in Active Directory"
        }
        $groupDN = $groupResult.Properties["distinguishedName"][0]
        Write-Host "Found group DN: $groupDN"
        # Return filter for users who are members of this group
        return "(&(objectCategory=user)(memberOf=$groupDN))"
    }
    else {
        Write-Host "Collecting all users in Active Directory"
        return "(objectCategory=user)"
    }
}
 
#endregion

#region Attribute Processing
function Convert-LDAPDateTimeString {
    param (
        [object]$DateTimeValue
    )
    
    try {
        $dateString = if ($DateTimeValue -is [byte[]]) {
            [System.Text.Encoding]::UTF8.GetString($DateTimeValue)
        }
        else {
            $DateTimeValue.ToString()
        }
        
        if ($dateString -match '(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})') {
            $date = [DateTime]::ParseExact(
                $matches[1..6] -join '',
                'yyyyMMddHHmmss',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            return $date.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
        }
        
        return [DateTime]::Parse($dateString).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return "NULL"
    }
}

function Convert-FileTimeToDateTime {
    param (
        [object]$FileTime
    )
    
    try {
        if ($null -eq $FileTime) { return "NULL" }
        
        $fileTimeValue = if ($FileTime -is [byte[]]) {
            [BitConverter]::ToInt64($FileTime, 0)
        }
        else {
            [Int64]::Parse($FileTime.ToString())
        }
        
        if ($fileTimeValue -eq 0 -or 
            $fileTimeValue -eq [Int64]::MaxValue -or 
            $fileTimeValue -eq 9223372036854775807) {
            return "NULL"
        }
        
        return [DateTime]::FromFileTime($fileTimeValue).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return "NULL"
    }
}
<#
function Get-ADGroupTypes {
    param (
        [int]$GroupType
    )
    
    $types = @()
    
    # Scope
    switch ($GroupType -band 0x0000000F) {
        2 { $types += "Global" }
        4 { $types += "DomainLocal" }
        8 { $types += "Universal" }
        default { $types += "Unknown" }
    }
    
    # Type
    if ($GroupType -band 0x80000000) {
        $types += "Security"
    } else {
        $types += "Distribution"
    }
    
    return $types -join ' | '
}#>

function Get-ADGroupTypes {
    param (
        [int]$GroupType
    )
    
    $types = @()
    
    # Handle negative values (security groups have 0x80000000 bit set, making them negative)
    $unsignedGroupType = if ($GroupType -lt 0) {
        [uint32]($GroupType + 4294967296)  # Convert to unsigned
    }
    else {
        [uint32]$GroupType
    }
    
    # Scope - check the bottom 4 bits
    $scopeBits = $unsignedGroupType -band 0x0000000F
    switch ($scopeBits) {
        2 { $types += "Global" }
        4 { $types += "DomainLocal" }  
        8 { $types += "Universal" }
        default {
            # Handle common edge cases
            if ($scopeBits -eq 0) {
                $types += "Global"  # Default for many groups
            }
            else {
                $types += "Unknown-Scope-$scopeBits"
            }
        }
    }
    
    # Type - check security bit (0x80000000)
    if ($unsignedGroupType -band 0x80000000) {
        $types += "Security"
    }
    else {
        $types += "Distribution"
    }
    
    return $types -join ' | '
}
#endregion

Export-ModuleMember -Function @(
    'New-LDAPConnection',
    'New-LDAPSearchRequest',
    'Convert-LDAPDateTimeString',
    'Convert-FileTimeToDateTime',
    'Get-ADGroupTypes',
    'Get-ADGroupFilter'
)