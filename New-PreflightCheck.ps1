#This script uses the SQL Configuration Manager to manage the SQL services.
#Compatible with PowerShell V 2.0, can run on Windows Server 2008 R2 with MSSQL Server 2008 R2

[CmdletBinding()]
Param(    
    [Switch]$StopService
)
DynamicParam{
    If ($StopService){
        $Attrib = New-Object System.Management.Automation.ParameterAttribute
        $Attrib.Mandatory = $false
        $Attrib.ParameterSetName = 'StopGroup'        
    
        $AttribCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
        $AttribCollection.Add($Attrib)

        $DynSJC = New-Object System.Management.Automation.RuntimeDefinedParameter("SkipJobCheck",[Switch],$Attrib)
        $DynSBC = New-Object System.Management.Automation.RuntimeDefinedParameter("SkipBackupCheck",[Switch],$Attrib)

        $ParamDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        $ParamDictionary.Add("SkipJobCheck", $DynSJC)
        $ParamDictionary.Add("SkipBackupCheck", $DynSBC)
        return $ParamDictionary
    }
}

Process{

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

$ReportPath = "\\FileServer\DBA\PostFlightCheck"
$CsvPath    = "C:\temp"
$Computer   = $env:COMPUTERNAME + "-Pre"
$Script:AllServices = $script:SrvConf.Services
$Script:RunningSrvs = $script:SrvConf.Services | Where-Object{$_.ServiceState -eq 'Running'}

Function Get-DriveSpace{
<#
.DESCRIPTION
   The script shows all the logical drive details of a computer. By default it displays all logical drives unless the Drive parameter is specified.
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

Function Test-DriveSpace{   
   #[OutputType([Bool])]
    Param(
        [ValidateNotNullOrEmpty()]
        [ValidatePattern("^[C-Zc-z]:")]
        [string]$Drive,
        [ValidateNotNullOrEmpty()]
        [Double]$SizeGB
    )
    $TestDrive = Get-DriveSpace | Where-Object{$_.Drive -eq $Drive}
    return ([double]$TestDrive.FreeSpaceGB -gt [Double]$SizeGB)
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
        #Hide Row haserror rowstate before return 
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

Function Get-SQLServerVersion {
    $QueryParam = @{
        ServerName = $env:COMPUTERNAME
        Database   = 'master'
        Query      = "SELECT @@SERVERNAME AS ServerName, @@VERSION AS ServerVersion, (SELECT SERVERPROPERTY('ResourceVersion')) As Version"
    }
    #Select -ExcludeProperty RowError,RowState,Table,ItemArray,HasError from the DataSet
    return (Invoke-SqlQuery @QueryParam | Select-Object ServerName,ServerVersion,Version)
}

Function Get-DbBackupInfo {    
    return ($script:Dbs | Select-Object Name,RecoveryModel,LastBackupDate,LastLogBackupDate,Owner,UserAccess,ActiveConnections)    
}

Function Test-DbBackupInfo {        
    $FailedBkp = $script:Srv.JobServer.Jobs | 
        Where-Object{($_.IsEnabled -eq $true) -and ($_.Name -like "*Backup*") -and ($_.LastRunOutcome -ne "Succeeded")} |
        Select-Object Name,IsEnabled,JobSteps,CurrentRunStatus,LastRunOutcome,LastRunDate,NextRunDate,Category
    return ($FailedBkp)
}

Function Get-SQLJobActivity {
    return ($script:Srv.JobServer.Jobs | Select-Object Name,IsEnabled,JobSteps,CurrentRunStatus,LastRunOutcome,LastRunDate,NextRunDate,Category)
}

Function Test-SQLJobActivity{      
    $script:Srv.JobServer.Jobs | 
        ForEach-Object{
            If($_.CurrentRunStatus -like 'Idle'){
                #$_.Name + "-" + "Idle"
                return $true
            }
            Else { return $false; break }
        }
}

Function Get-SQLLog {
    return (Get-EventLog -LogName Application -After (Get-Date).date -Source MSSQLSERVER | 
            Select-Object EventID,Index,Category,EntryType,Message,InstanceID,TimeGenerated,UserName )
}

Function Get-SQLServices{    
    return ( (New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $script:Srv.ComputerNamePhysicalNetBIOS).Services | 
        Select-Object ServiceState,Name,DisplayName,AcceptsPause,AcceptsStop,StartMode,ProcessID,ServiceAccount ) 
}

Function Suspend-SQLservices{
    Param(  [Switch]$Wait   )
    $Script:RunningSrvs | Where-Object{$_.AcceptsPause -eq $true} | ForEach-Object{$_.pause()}    
    If ($Wait){
        $SrvName = $Script:RunningSrvs | Where-Object{$_.AcceptsPause -eq $true} | Select-Object -ExpandProperty Name
        do{
            [bool]$IsRunning = (($SrvName | Get-Service | Where-Object{$_.Status -eq "Running"}).count -gt 0)
            Start-Sleep 1
        } while($IsRunning)
    } 
}

Function Resume-SQLservices{
    Param( [Switch]$Wait )
             
    $PausedSrv = (New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $script:Srv.ComputerNamePhysicalNetBIOS).Services | Where-Object{$_.ServiceState -eq "Paused"} 
    $PausedSrv | ForEach-Object{$_.resume()}    
    If ($Wait){
        $SrvName = $PausedSrv | Select-Object -ExpandProperty Name
        do{
            [bool]$IsPaused = (($SrvName | Get-Service | Where-Object{$_.Status -eq "Paused"}).count -gt 0)
            Start-Sleep 2
        } while($IsPaused)
    } 
}

Function Stop-SQLServices{
    Param( [Switch]$Wait  )       
    $Script:RunningSrvs | ForEach-Object{$_.stop()}    
    If ($Wait){
        $SrvName = $Script:RunningSrvs | Select-Object -ExpandProperty Name
        Do {
            [Bool]$IsRunning = (($SrvName | Get-Service | Where-Object{$_.Status -eq "Running"}).count -gt 0)
            Start-Sleep 2
        }While($IsRunning)
    }    
}

########################################################
# The main controller script
########################################################

#region Main()
    $Head = @"
        <style type="text/css">
            body {font-size:10pt; font-family:Tahoma}    
            tr:nth-child(even) {background: #f8f8f8}
            tr:nth-child(odd) {background: #dae5f4}    
        </style>   
"@
    #Generate the report
    $CInfo   = Get-DriveSpace  | ConvertTo-Html -Fragment -PreContent '<h4>Drive Details</h4>' -PostContent '<br/>' | Out-String
    $SqlSer  = Get-SQLServices | ConvertTo-Html -Fragment -PreContent '<h4>SQL Services Details</h4>' -PostContent '<br/>' | Out-String
    $DbState = Get-DbState | ConvertTo-Html -Fragment -PreContent '<h4>SQL Database State</h4>' -PostContent '<br/>' | Out-String
    $SqlVer  = Get-SQLServerVersion | ConvertTo-Html -Fragment -PreContent '<h4>SQL Server Version</h4>' -PostContent '<br/>' | Out-String
    $DBInfo  = Get-DbBackupInfo | ConvertTo-Html -Fragment -PreContent '<h4>Database Backup Info</h4>' -PostContent '<br/>' | Out-String
    $DBJob   = Get-SQLJobActivity | ConvertTo-Html -Fragment -PreContent '<h4>SQL Job Activities</h4>' -PostContent '<br/>' | Out-String
    $SqlLog  = Get-SQLLog | ConvertTo-Html -Fragment -PreContent '<h4>SQL Log from today</h4>' -PostContent '<br/>' | Out-String   

    Write-Verbose "Generating CSV for SQL services..."
    Get-SQLServices | Export-Csv -NoTypeInformation -Path "$CsvPath\$Computer.csv"

    Write-Verbose "Generating HTML Report..."
    If (Test-Path $ReportPath){
        ConvertTo-Html -Head $Head -Body "$CInfo $SqlSer $DbState $SqlVer $DBInfo $DBJob $SqlLog" -Title "SQL Server Pre-flight Check Report" | Out-File "$ReportPath\$Computer.html"
    }
    Else {  $OutFile =  [Environment]::GetFolderPath("Desktop")
            ConvertTo-Html -Head $Head -Body "$CInfo $SqlSer $DbState $SqlVer $DBInfo $DBJob $SqlLog" -Title "SQL Server Pre-flight Check Report" | Out-File "$OutFile\$Computer.html" -Force
    }

    Write-Verbose "Checking drive C for free space..."
    If (!(Test-DriveSpace -Drive "C:" -SizeGB 5)){ 
        $Msg = "There is not enough space on C drive. Pre-flight check failed!"
        Write-Warning $Msg             
        #[Environment]::Exit(2)
        Exit 1
    }

    If (-Not($PSBoundParameters.ContainsKey('SkipJobCheck'))){
        Write-Verbose "Checking Sql Job Activities..."
        #$true means it is idle
        $BkJob = Test-SQLJobActivity
        If ($BkJob -contains $false){
            $Msg = "SQL agent job is still running! Please check the report."
            Write-Warning $Msg
            #[Environment]::Exit(3)
            Exit 1
        }
    }
    
    If (-Not($PSBoundParameters.ContainsKey('SkipBackupCheck'))){
        Write-Verbose "Checking the last backup..."
        If (Test-DbBackupInfo){
            $Msg = "One of the last SQL Backup job is not succeeded! Please check the report."
            Write-Warning $Msg                
            #[Environment]::Exit(4)
            Exit 1
        }
    }

    If ($StopService){
        Write-Verbose "Pausing SQL services..."        
        Suspend-SQLservices -Wait

        Write-Verbose "Stopping SQL services..."
        Stop-SQLServices -Wait
    }
    Exit 0
}
#endregion