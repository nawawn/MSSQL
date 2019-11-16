Function Get-SQLLog{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [DateTime]$After = (Get-Date).date
    )

    Process{        
        $Property = @(
            @{n='EventID';  e={$_.ID}},
            @{n='Index';    e={$_.RecordId}},
            @{n='Category'; e={$_.TaskDisplayName}},
            @{n='EntryType';e={$_.LevelDisplayName}},
            'Message',
            'TimeCreated',
            @{n='UserName'; e={(Get-UserName $_.UserId)}}
        )
        Write-Verbose "$ComputerName - Retrieving Event Log for MSSQLSERVER..."
        #Get-EventLog -ComputerName $ComputerName -LogName Application -After (Get-Date).date -Source MSSQLSERVER | 
        #    Select-Object EventID,Index,Category,EntryType,Message,InstanceID,TimeGenerated,UserName 
        Get-WinEvent -FilterHashtable @{Logname='Application'; ProviderName='MSSQLSERVER';StartTime=$After} -ComputerName $ComputerName |
            Select-Object -Property $Property
    }    
}

Function Get-DbErrorLog{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [DateTime]$After = (Get-Date).date
    )
    Process{
        Write-Verbose "$ComputerName - Retrieving SQL Db Error Log..."
        $Property = @('InstanceName','HasErrors','Text','LogDate')
        Get-DbaErrorLog -SqlInstance $ComputerName -After $After | Select-Object -Property $Property
    } 
}
