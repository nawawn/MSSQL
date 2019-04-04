[CmdletBinding()]
Param(    
    [Switch]$StartService
)

Write-Verbose "Loading SQL Management Object..."
If ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")){            
    [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO')
    [void][Reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
    
    $script:Srv = New-Object Microsoft.SqlServer.Management.Smo.Server("(local)")
    $script:SrvConf = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $script:Srv.ComputerNamePhysicalNetBIOS
    $script:Dbs = $script:Srv.Databases
}    
Else {
    $Msg = "This computer does NOT have the MS SQL Management Studio installed!"    
    Write-Warning $Msg   
    #[Environment]::Exit(1)
    Exit 1   
}

$ReportPath = "\\FileServer\DBA\PreFlightCheck"
$CsvPath = "C:\temp"
$Computer = $env:COMPUTERNAME + "-Pre"
$OutFile = $env:COMPUTERNAME + "-Post"
$Script:AllServices = $script:SrvConf.Services
$Script:StoppedServices = $script:SrvConf.Services | Where-Object{$_.ServiceState -eq "Stopped" -and $_.StartMode -eq "Auto"}

Function Get-DriveSpace{
<#
.DESCRIPTION
    The script extracts all the logical drive details of a computer. By default it displays all logical drives unless the Drive parameter is used.
.EXAMPLE
    Get-DriveSpace
.EXAMPLE
    Get-DriveSpace -Drive 'C:'
#>
    Param( 
        [AllowNull()]       
        [ValidatePattern("^[C-Zc-z]:")]
        [String]$Drive 
    )
    #[OutputType([System.Object])]    
    $Properties = @(
        @{n='Drive';e={$_.DeviceID}},
        @{n='FreeSpaceGB';e={[Math]::Round($_.FreeSpace/1GB,2)}},
        @{n='UsedSpaceGB';e={([Math]::Round($_.Size/1GB,2))-([Math]::Round($_.FreeSpace/1GB,2))}},
        @{n='TotalSizeGB';e={[Math]::Round($_.Size/1GB,2)}},
        'VolumeName'
    )
    If ($Drive){
        Write-Verbose "Details for Drive $Drive"
        return (Get-WmiObject -Class Win32_LogicalDisk | Where-Object{$_.DeviceID -eq $Drive} | Select-Object -Property $Properties)
    }
    Else { return (Get-WmiObject -Class Win32_LogicalDisk | Select-Object -Property $Properties) }
}

Function Invoke-SqlQuery{    
    Param(            
        [String]$ServerName,
        [String]$Database,
        [String]$Query        
    )
    #[Parameter(Mandatory)] not available in PS 2.0
    Begin{
        $SqlConn = New-Object System.Data.SqlClient.SqlConnection
        $Connstr = "Server=$ServerName;Database=$Database;Integrated Security=True;"
        $SqlConn.ConnectionString = $Connstr
    }
    Process{
        $SqlConn.Open()    
        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand($Query,$SqlConn)    
        $SqlDA  = New-Object System.Data.SqlClient.SqlDataAdapter($SqlCmd)
        $SqlDS  = New-Object System.Data.DataSet
        [void]$SqlDA.fill($SqlDS)
        [Array]$Data = $SqlDS.Tables[0]
        $SqlConn.Close()
        return ($Data)
    }
    End{}
}

Function Get-DbState{
    $QueryParam = @{
        ServerName = $env:COMPUTERNAME
        Database   = 'master'
        Query      = 'SELECT name,state_desc,user_access_desc,recovery_model_desc FROM sys.databases'
    }
    #Select -ExcludeProperty RowError,RowState,Table,ItemArray,HasError from the DataSet
    return (Invoke-SqlQuery @QueryParam | Select-Object name,state_desc,user_access_desc,recovery_model_desc)
}

Function Get-DbBackupInfo {    
    return ($script:Dbs | Select-Object Name,RecoveryModel,LastBackupDate,LastLogBackupDate,Owner,UserAccess,ActiveConnections)    
}

Function Get-SQLJobActivity {
    return ($script:Srv.JobServer.Jobs | Select-Object Name,IsEnabled,JobSteps,CurrentRunStatus,LastRunOutcome,LastRunDate,NextRunDate,Category)
}

Function Get-SQLLog {
    return (Get-EventLog -LogName Application -After (Get-Date).date -Source MSSQLSERVER | 
            Select-Object EventID,Index,Category,EntryType,Message,InstanceID,TimeGenerated,UserName )
}

Function Get-SQLServices{    
    return ( 
        (New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $script:Srv.ComputerNamePhysicalNetBIOS).Services | 
            Select-Object ServiceState,Name,DisplayName,AcceptsPause,AcceptsStop,StartMode,ProcessID,ServiceAccount 
    ) 
}

Function Get-CsvRunningServices{
    Param(        
        [String]$CsvFile = "$CsvPath\$Computer.csv"
    )
    If (Test-Path $CsvFile){
        $Csv = Import-Csv $CsvFile        
        return ($Csv | Where-Object{$_.ServiceState -eq "Running"} | Select-Object -ExpandProperty Name)
    }    
}

Function Start-SQLServices{
    Param( [Switch]$Wait )

    $CsvRunningSrv = Get-CsvRunningServices
    If ($CsvRunningSrv){
        Write-Verbose "Starting services which have running state in CSV..."       
        $Script:AllServices | 
            Where-Object{($_.ServiceState -eq "Stopped") -and ($CsvRunningSrv -contains $_.Name)} | 
            ForEach-Object{$_.start()}
            #Select-Object Name,ServiceState
        If ($Wait){                       
            Do {
                [Bool]$IsStopped = (($CsvRunningSrv | Get-Service | Where-Object{$_.Status -eq "Stopped"}).Count -gt 0)
                Write-Verbose "Services still in Stopped state? $IsStopped"
                Start-Sleep 3
            }While($IsStopped)        
        }    
    }
    #Elseif ("FileNotFile"){ #check the master sql services list from psd file}    
    Else{
        Write-Verbose "Unable to find the Services CSV file."
        Write-Verbose "Starting all services with StartMode set to Auto..."
        $Script:StoppedServices | ForEach-Object{$_.start()}
        If ($Wait){            
            $SrvName = $Script:StoppedServices | Select-Object -ExpandProperty Name
            Do {
                [Bool]$IsStopped = (($SrvName | Get-Service | Where-Object{$_.Status -eq "Stopped"}).Count -gt 0)
                Write-Verbose "Services still in Stopped state? $IsStopped"
                Start-Sleep 3
            }While($IsStopped)        
        }
    }    
}

#Put SQL server details section here.

#region main()
    $Head = @"
        <style type="text/css">
            body {font-size:10pt; font-family:Tahoma}    
            tr:nth-child(even) {background: #f8f8f8}
            tr:nth-child(odd) {background: #dae5f4}    
        </style>   
"@
    $BeforeServ  = Get-SQLServices | ConvertTo-Html -Fragment -PreContent '<h4>Before SQL Services Restart</h4>' -PostContent '<br/>' | Out-String

    If ($StartService){
        Start-SQLServices -Wait
        Start-Sleep 30
    }

    Write-Verbose "Generating the Post Flight report..."
    $CInfo   = Get-DriveSpace | ConvertTo-Html -Fragment -PreContent '<h4>Drive Details</h4>' -PostContent '<br/>' | Out-String
    $AfterServ = Get-SQLServices | ConvertTo-Html -Fragment -PreContent '<h4>After SQL Services Restart</h4>' -PostContent '<br/>' | Out-String
    $DbState = Get-DbState | ConvertTo-Html -Fragment -PreContent '<h4>SQL Database State</h4>' -PostContent '<br/>' | Out-String
    $DBInfo  = Get-DbBackupInfo | ConvertTo-Html -Fragment -PreContent '<h4>Database Backup Info</h4>' -PostContent '<br/>' | Out-String
    $DBJob   = Get-SQLJobActivity | ConvertTo-Html -Fragment -PreContent '<h4>SQL Job Activities</h4>' -PostContent '<br/>' | Out-String
    $SqlLog  = Get-SQLLog | ConvertTo-Html -Fragment -PreContent '<h4>SQL Log from today</h4>' -PostContent '<br/>' | Out-String

    If (Test-Path $ReportPath){
        ConvertTo-Html -Head $Head -Body "$CInfo $BeforeServ $AfterServ $DbState $DBInfo $DBJob $SqlLog" -Title "SQL Server Post-flight Check Report" | Out-File "$ReportPath\$OutFile.html"
    }
    Else{  
        $OutPath =  [Environment]::GetFolderPath("Desktop")
        ConvertTo-Html -Head $Head -Body "$CInfo $BeforeServ $AfterServ $DbState $DBInfo $DBJob $SqlLog" -Title "SQL Server Post-flight Check Report" | Out-File "$OutPath\$OutFile.html" -Force
    }

    #send-emailalert

#endregion