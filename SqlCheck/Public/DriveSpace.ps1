Function Get-DriveSpace{
    [CmdletBinding()]
    Param(
        [String]$ComputerName = $Env:ComputerName,
        [AllowNull()][ValidatePattern("^[C-Zc-z]:")]
        [String]$Drive
    )
    Process{
        $Property = @(
            @{n='Drive';e={$_.DeviceID}},
            @{n='FreeSpaceGB';e={[Math]::Round($_.FreeSpace/1GB,2)}},
            @{n='UsedSpaceGB';e={([Math]::Round($_.Size/1GB,2))-([Math]::Round($_.FreeSpace/1GB,2))}},
            @{n='TotalSizeGB';e={[Math]::Round($_.Size/1GB,2)}},
            'VolumeName'
        )
        If ($Drive){
            Write-Verbose "$ComputerName - Retrieving details for Drive $Drive..."
            Get-WmiObject -Class Win32_LogicalDisk -ComputerName $ComputerName | Where-Object{$_.DeviceID -eq $Drive} | Select-Object -Property $Property
        }
        Else {
            Write-Verbose "$ComputerName - Retrieving details for All Available Drive(s)..."
            Get-WmiObject -Class Win32_LogicalDisk -ComputerName $ComputerName | Select-Object -Property $Property
        }
    }
<#
.DESCRIPTION
    The script shows all the logical drive details of a computer. By default it displays all logical drives unless the Drive parameter is specified.
.EXAMPLE
    Get-DriveSpace
.EXAMPLE
    Get-DriveSpace -Drive 'C:'
#>    
}

Function Test-DriveSpace{
    [OutputType([Bool])]
    Param(
        [String]$ComputerName = $Env:ComputerName,
        [ValidateNotNullOrEmpty()][ValidatePattern("^[C-Zc-z]:")]
        [string]$Drive = 'C:',
        [ValidateNotNullOrEmpty()]
        [Double]$SizeGB = 5
    )
    Process{
        $TestDrive = Get-DriveSpace -ComputerName $ComputerName | Where-Object{$_.Drive -eq $Drive}
        return ([Double]$TestDrive.FreeSpaceGB -gt [Double]$SizeGB)
    }
<#
.DESCRIPTION
    The script returns true if the available space on the drive is larger than the given Gigabyte value. By default it checks against 5 GB available space.
.EXAMPLE
    Test-DriveSpace -ComputerName testmachine -Drive 'C:' -SizeGB 10
#>     
}