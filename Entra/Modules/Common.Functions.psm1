#Requires -Version 7.0
<#
.SYNOPSIS
    Common functions for GIAM data collection

    Removed functions:
        Find-GIAMConfig
        Initialize-GIAMEnvironment
        Convert-ToStandardBoolean
#>

#region Configuration
function Get-Config {
    param (
        [string]$ConfigPath = "giam-config.json"
        #$config = Get-Config -ConfigPath (Resolve-Path "..\..\giam-config.json").Path -Force -Verbose
    )
    
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at: $ConfigPath"
    }
    
    try {
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Error reading configuration: $_"
    }
}
#endregion


#region Path Management
function Initialize-DataPaths {
    param (
        [Parameter(Mandatory)]
        [object]$Config
    )
    
    foreach ($path in $Config.Paths.PSObject.Properties.Value) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}
#endregion

#region File Management
function Move-ProcessedCSV {
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
    Write-Host "CSV saved to: $finalPath"
}
#endregion

#region Memory Management
function Test-MemoryPressure {
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
#endregion

#region Progress Management
function Save-Progress {
    param (
        [Parameter(Mandatory)]
        [hashtable]$Progress,
        
        [Parameter(Mandatory)]
        [string]$ProgressFile
    )
    
    $Progress | ConvertTo-Json -Depth 10 | Set-Content -Path $ProgressFile
}

function Get-Progress {
    param (
        [Parameter(Mandatory)]
        [string]$ProgressFile
    )
    
    if (Test-Path $ProgressFile) {
        Write-Host "Resuming from previous progress..."
        return Get-Content $ProgressFile | ConvertFrom-Json -AsHashtable
    }
    
    return $null
}
#endregion

#region Date Standardization
function Convert-ToStandardDateTime {
    param (
        [object]$DateValue,
        [string]$SourceFormat = "Auto"
    )
    
    # Return empty string for null/empty values
    if ($null -eq $DateValue -or $DateValue -eq '' -or $DateValue -eq 0) {
        return ""
    }
    
    try {
        switch ($SourceFormat) {
            'GraphAPI' {
                # Handle Microsoft Graph API ISO 8601 format
                $date = [DateTime]::Parse($DateValue, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                return $date.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            }
            'LDAP' {
                # Handle LDAP datetime format (from AD.Functions.psm1)
                $dateString = if ($DateValue -is [byte[]]) {
                    [System.Text.Encoding]::UTF8.GetString($DateValue)
                }
                else {
                    $DateValue.ToString()
                }
                
                if ($dateString -match '(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})') {
                    $date = [DateTime]::ParseExact(
                        $matches[1..6] -join '',
                        'yyyyMMddHHmmss',
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                    return $date.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
                }
                
                $date = [DateTime]::Parse($dateString)
                return $date.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            }
            'FileTime' {
                # Handle Windows FileTime format (from AD.Functions.psm1)
                $fileTimeValue = if ($DateValue -is [byte[]]) {
                    [BitConverter]::ToInt64($DateValue, 0)
                }
                else {
                    [Int64]::Parse($DateValue.ToString())
                }
                
                if ($fileTimeValue -eq 0 -or 
                    $fileTimeValue -eq [Int64]::MaxValue -or 
                    $fileTimeValue -eq 9223372036854775807) {
                    return ""
                }
                
                return [DateTime]::FromFileTime($fileTimeValue).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            }
            'Epoch' {
                # Handle Unix epoch seconds
                $epochSeconds = [double]$DateValue
                $date = [DateTime]::UnixEpoch.AddSeconds($epochSeconds)
                return $date.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            }
            default {
                # Auto-detect format
                $stringValue = $DateValue.ToString()
                
                # Check for Graph API format (ISO 8601 with Z or offset)
                if ($stringValue -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}') {
                    return Convert-ToStandardDateTime -DateValue $DateValue -SourceFormat 'GraphAPI'
                }
                
                # Check for LDAP format (yyyyMMddHHmmss)
                if ($stringValue -match '^\d{14}') {
                    return Convert-ToStandardDateTime -DateValue $DateValue -SourceFormat 'LDAP'
                }
                
                # Check for epoch (numeric)
                if ($DateValue -is [int] -or $DateValue -is [long] -or $DateValue -is [double]) {
                    # If it's a large number, assume FileTime; if smaller, assume Epoch
                    if ([long]$DateValue -gt 100000000000) {
                        return Convert-ToStandardDateTime -DateValue $DateValue -SourceFormat 'FileTime'
                    }
                    else {
                        return Convert-ToStandardDateTime -DateValue $DateValue -SourceFormat 'Epoch'
                    }
                }
                
                # Default: try to parse as standard datetime
                $date = [DateTime]::Parse($stringValue, [System.Globalization.CultureInfo]::InvariantCulture)
                return $date.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
            }
        }
    }
    catch {
        Write-Warning "Failed to convert date value '$DateValue': $_"
        return ""
    }
}
#endregion


Export-ModuleMember -Function @(
    'Get-Config',
    'Initialize-DataPaths',
    'Move-ProcessedCSV',
    'Test-MemoryPressure',
    'Write-BufferToFile',
    'Save-Progress',
    'Get-Progress',
    'Convert-ToStandardDateTime'
)