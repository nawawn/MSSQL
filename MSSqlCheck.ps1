#Requires -Modules DbaTools

# This script requires DbaTools PowerShell Module
Function Start-PreflightCheck{

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [String]$ComputerName,
        [Switch]$StopService
    )
    <#
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

    $ReportPath = "\\blm-scm-01\reports\PreFlightChecks"
    $CsvPath    = "C:\temp"
    If (-Not(Test-Path -path $ReportPath)){
        Write-Warning "$ReportPath Path not found"
        Exit 1
    }
    #>
}
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

Function Get-DbState{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{
        $QueryParam = @{
            SqlInstance = $ComputerName
            Database   = 'master'
            Query      = 'SELECT name,state_desc,user_access_desc,recovery_model_desc FROM sys.databases'
        }
        Write-Verbose "$ComputerName - Retreiving Database State Information..."
        #Invoke-Sqlcmd -ServerInstance $ComputerName -Database 'master' -Query 'SELECT name,state_desc,user_access_desc,recovery_model_desc FROM sys.databases'
        $Property = @('name','state_desc','user_access_desc','recovery_model_desc')
        Invoke-DbaQuery @QueryParam | Select-Object -Property $Property
    }    
}

Function Get-DbConnection{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{
        $Query  = 'SELECT DB_NAME(database_id) AS DatabaseName, COUNT(session_id) AS TotalConnections FROM sys.dm_exec_sessions GROUP BY DB_NAME(database_id)'
        If([Version](Get-SQLServerVersion -ComputerName $ComputerName).version -lt '11.00'){
            $Query = 'SELECT DB_NAME(dbid) AS DatabaseName, COUNT(dbid) AS TotalConnections FROM sys.sysprocesses GROUP BY DB_NAME(dbid)'
        }        
        $QueryParam = @{
            SqlInstance = $ComputerName
            Query  = $Query
        }
        $Property = @('DatabaseName','TotalConnections')
        Invoke-DbaQuery @QueryParam | Select-Object -Property $Property
    }
}

Function Get-SQLServerVersion {
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{
        $QueryParam = @{}    
        $QueryParam.Add('SqlInstance', $ComputerName)
        $QueryParam.Add('Database',    'master')
        $QueryParam.Add('Query',       "SELECT @@SERVERNAME AS ServerName, @@VERSION AS SQLVersion, (SELECT SERVERPROPERTY('ResourceVersion')) As Version")    
        
        Write-Verbose "$ComputerName - Retreiving SQL Server Version Information..."
        #Invoke-Sqlcmd -ServerInstance $ComputerName -Database 'master' -Query "SELECT @@SERVERNAME AS ServerName, @@VERSION AS ServerVersion, (SELECT SERVERPROPERTY('ResourceVersion')) As Version"
        $Property = @('ServerName','SQLVersion','Version')
        Invoke-DbaQuery @QueryParam | Select-Object -Property $Property
    }    
}

Function Get-DbBackupInfo{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{
        Write-Verbose "$ComputerName - Retreiving SQL Database Backup Information..."
        #$Property = @('Name','RecoveryModel','LastBackupDate','LastLogBackupDate','Owner','UserAccess','ActiveConnections','Size','Collation','CompatibilityLevel')
        #Get-SqlDatabase -ServerInstance $ComputerName | Select-Object -Property $Property
        $Property = @('Name','RecoveryModel','LastFullBackup','LastLogBackup','Owner','UserAccess','ActiveConnections','SizeMB','Collation','Compatibility')
        Get-DbaDatabase -SqlInstance $ComputerName | Select-Object -Property $Property
    }    
}

Function Test-DbBackupInfo{}

Function Get-SQLJobActivity{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{
        Write-Verbose "$ComputerName - Retreiving SQL Server Agent Job..."
        #$Property = @('Name','IsEnabled','JobSteps','CurrentRunStatus','LastRunOutcome','LastRunDate','NextRunDate','Category')
        #Get-SqlAgentJob -ServerInstance $ComputerName | Select-Object -Property $Property
        $Property = @('Name','IsEnabled','JobSteps','CurrentRunStatus','LastRunOutcome','LastRunDate','NextRunDate','Category')
        Get-DbaAgentJob -SqlInstance $ComputerName | Select-Object -Property $Property
    }    
}

Function Test-SQLJobActivity{
    [CmdletBinding()]
    [OutputType([bool])]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{        
        $Result = ($null -ne (Get-DbaRunningJob -SqlInstance $ComputerName))
        Write-Verbose "$ComputerName - Checking SQL Server Agent Job Activities: $Result"
        return ($Result)
    }
}

Function Get-UserNameFromSID{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$UserSID
    )
    Process{
        $objSID = New-Object System.Security.Principal.SecurityIdentifier ($UserSID)
        $objUser = $objSID.Translate( [System.Security.Principal.NTAccount])
        $objUser.Value
    }
}

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
            @{n='UserName'; e={(Get-UserNameFromSID $_.UserId)}}
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

Function Get-SQLServices{
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{
        Write-Verbose "$ComputerName - Retrieving SQL Services status..."
        $Property = @('State','ServiceName','DisplayName','ServiceType','InstanceName','StartMode','StartName')
        Get-DbaService -ComputerName $ComputerName | Select-Object -Property $Property
    }
}

Function Stop-SQLServices{
    [CmdletBinding()]
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName, 
        [Switch]$Wait  
    )
    Process{
        Write-Verbose "Loading SQL Management Object..."
        If ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")){            
            [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO')
            [void][Reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
            
            $SqlServer = New-Object Microsoft.SqlServer.Management.Smo.Server($ComputerName)
            $SqlConf = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $SqlServer.ComputerNamePhysicalNetBIOS            
        }    
        Else {         
            Write-Warning "Please install MS SQL Management Studio"   
            [Environment]::Exit(1)
        }

        Write-Verbose "$ComputerName - Stopping SQL Services..."
        $SqlConf.Services | Where-Object{$_.ServiceState -eq 'Running'} | ForEach-Object{$_.stop()}    
        If ($Wait){
            $SrvName = $SqlConf.Services | Where-Object{$_.ServiceState -eq 'Running'} | Select-Object -ExpandProperty Name
            Do {
                [Bool]$IsRunning = (($SrvName | Get-Service -ComputerName $ComputerName | Where-Object{$_.Status -eq "Running"}).count -gt 0)
                Write-Verbose "Services being stopped? $IsRunning"
                Start-Sleep 3
            }While($IsRunning)
        }
    }        
}
Function Test-ServiceStatus{
    #Is the service running
    [CmdletBinding()]
    [OutputType([bool])]
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [ValidateSet('Running', 'Stopped', 'Paused')]
        [String]$Status = 'Running'
    )
    Process{
        return ($Status -eq (Get-Service -Name $Name -ComputerName $ComputerName -ErrorAction 'SilentlyContinue').Status)
    }
}
Function Start-SQLServices{
    [CmdletBinding()]
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [System.IO.FileInfo]$CSVPath = "\\blm-scm-01\Reports\CSV",
        [System.IO.FileInfo]$MasterList = '\\blm-scm-01\reports\Scripts\MasterList.psd1'
    )
    Begin {
        $CsvFile = "$CSVPath\$ComputerName.csv"
        If (Test-Path $CsvFile){
            $Csv = Import-Csv $CsvFile
            #$Csv
            $CsvRunningSrv = ($Csv | Where-Object{$_.ServiceState -eq "Running"} | Select-Object -ExpandProperty Name)
            $CsvRunningSrv | Get-Service -ComputerName $ComputerName | Start-Service
        }
        Elseif(Test-Path $MasterList){
            Write-Warning "Unable to find the Services CSV file: $CsvFile"
            $ServiceList = Import-PowerShellDataFile $MasterList
            If ($null -ne $($ServiceList.$ComputerName.Running.Name)){
                $ServiceList.$ComputerName.Running.Name | Get-Service -ComputerName | Start-Service
            }
            Else {
                Write-Warning "Unable to obtain running services from the Master Service List for $ComputerName!"
            }
        }
        Else{
            Write-Warning "Please manually restart the Sql services or reboot the server!"
        }
    }
    Process {
        If ($CsvRunningSrv){
            Write-Verbose "Starting services according to running state in CSV..."       
            $CsvRunningSrv | Get-Service -ComputerName $ComputerName | Start-Service
        } 
        Else{            
            Write-Warning "Unable to find the CSV file with Services info"
            Write-Warning "The start-up process for services is ignored."
            Write-Warning "Please reboot the server, if the problem persists."
        }
    }
}

Function Start-SQLServices1{
    #This doesn't work on remote machine - only works on local machine
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [System.IO.FileInfo]$CSVPath = "\\blm-scm-01\Reports\CSV",
        [Switch]$Wait  
    )
    Begin{
        $CsvFile = "$CSVPath\$ComputerName.csv"
        If (Test-Path $CsvFile){
            $Csv = Import-Csv $CsvFile
            #$Csv
            $CsvRunningSrv = ($Csv | Where-Object{$_.ServiceState -eq "Running"} | Select-Object -ExpandProperty Name)
        }
        Else {
            Write-Warning "Unable to find the Services CSV file: $CsvFile"
        }
    }
    Process{
        Write-Verbose "Loading SQL Management Object..."
        If ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")){            
            [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO')
            [void][Reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
            
            $SqlServer = New-Object Microsoft.SqlServer.Management.Smo.Server($ComputerName)
            $SqlConf = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $SqlServer.ComputerNamePhysicalNetBIOS            
        }    
        Else {         
            Write-Warning "Please install MS SQL Management Studio"   
            [Environment]::Exit(1)
        }
        If ($CsvRunningSrv){
            Write-Verbose "Starting services which have running state in CSV..."       
            $SqlConf.Services | 
                Where-Object{($_.ServiceState -eq "Stopped") -and ($CsvRunningSrv -contains $_.Name)} | 
                ForEach-Object{$_.start()}
                #Select-Object Name,ServiceState
            If ($Wait){                       
                Do {
                    [Bool]$IsStopped = (($CsvRunningSrv | Get-Service -ComputerName $ComputerName | Where-Object{$_.Status -eq "Stopped"}).Count -gt 0)
                    Write-Verbose "Services still being started? $IsStopped"
                    Start-Sleep 3
                }While($IsStopped)        
            }    
        }
        #Elseif ("FileNotFile"){ #check the master sql services list from psd file}  
        #### This needs to be fixed....  
        Else{            
            Write-Verbose "Starting all services with StartMode set to Auto..."
            $SqlConf.Services | Where-Object{$_.ServiceState -eq "Stopped" -and $_.StartMode -eq "Auto"} | ForEach-Object{$_.start()}
            If ($Wait){            
                $SrvName = $SqlConf.Services | Where-Object{$_.ServiceState -eq "Stopped" -and $_.StartMode -eq "Auto"} | Select-Object -ExpandProperty Name
                Do {
                    [Bool]$IsStopped = (($SrvName | Get-Service -ComputerName $ComputerName | Where-Object{$_.Status -eq "Stopped"}).Count -gt 0)
                    Write-Verbose "Services being started? $IsStopped"
                    Start-Sleep 3
                }While($IsStopped)        
            }
        }
    }        
}

Function Get-SQLServerHtmlReport{
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [System.IO.FileInfo]$OutputPath = "\\blm-scm-01\Reports\PreFlightChecks"
    )
    Begin{
        $Head = @"
        <style type="text/css">
            body {font-size:10pt; font-family:Tahoma}    
            tr:nth-child(even) {background: #f8f8f8}
            tr:nth-child(odd) {background: #dae5f4}    
        </style>   
"@
    }
    Process{
        #Generate the report
        $CInfo   = Get-DriveSpace -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>Drive Details</h4>' -PostContent '<br/>' | Out-String
        $SqlSer  = Get-SQLServices -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Services Details</h4>' -PostContent '<br/>' | Out-String
        $DbState = Get-DbState -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Database State</h4>' -PostContent '<br/>' | Out-String
        $DbConns = Get-DbConnection -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Database Connection Summary</h4>' -PostContent '<br/>' | Out-String
        $SqlVer  = Get-SQLServerVersion -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Server Version</h4>' -PostContent '<br/>' | Out-String
        $DBInfo  = Get-DbBackupInfo -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>Database Backup Info</h4>' -PostContent '<br/>' | Out-String
        $DBJob   = Get-SQLJobActivity -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Job Activities</h4>' -PostContent '<br/>' | Out-String
        $SqlLog  = Get-SQLLog -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Log from today</h4>' -PostContent '<br/>' | Out-String
        $SqlErr  = Get-DbErrorLog -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Error Log from today</h4>' -PostContent '<br/>' | Out-String

        Write-Verbose "Generating SQL Server HTML Report..."
        If (Test-Path $OutputPath){
            ConvertTo-Html -Head $Head -Body "$CInfo $SqlSer $DbState $DbConns $SqlVer $DBInfo $DBJob $SqlLog $SqlErr" -Title "SQL Server Pre-flight Check Report" | 
                Out-File "$OutputPath\$ComputerName-Pre.html"
        }
        Else {  
            $OutFile =  [Environment]::GetFolderPath("Desktop")
            ConvertTo-Html -Head $Head -Body "$CInfo $SqlSer $DbState $DbConns $SqlVer $DBInfo $DBJob $SqlLog $SqlErr" -Title "SQL Server Pre-flight Check Report" | 
                Out-File "$OutFile\$ComputerName-Pre.html" -Force
        }
    }
}

Function Get-SQLServiceCsvReport{
    Param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [System.IO.FileInfo]$OutputPath = "\\blm-scm-01\Reports\CSV"
    )
    Process{
        Write-Verbose "Generating CSV for SQL services..."
        Get-SQLServices -ComputerName $ComputerName | Export-Csv -Path "$OutputPath\$ComputerName.csv" -NoTypeInformation
    }    
}

Function Get-ServicePsd1{
    Param(
            [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName,Position=0)]
            [String]$ComputerName
        )
    Begin{
        $begin = '@{'
        $end = '}'
        Write-Output $begin
    }
    Process{
        $ServiceList = (Get-DbaService -ComputerName $ComputerName) 
        [String]$Running = (($ServiceList.where{$_.State -eq 'Running'}).ServiceName) | Foreach-Object{"'"+ "$_" + "',"}
        [String]$Stopped = (($ServiceList.where{$_.State -eq 'Stopped'}).ServiceName) | Foreach-Object{"'"+ "$_" + "',"}
        Write-Output "`'$ComputerName`' = @{"        
        Write-Output "`t Running = @{"
        Write-Output "`t`t Name = $((-Join $Running).TrimEnd(','))"
        Write-Output "`t }"
        Write-Output "`t Stopped = @{"
        Write-Output "`t`t Name = $((-Join $Stopped).TrimEnd(','))"
        Write-Output "`t }"
        Write-Output "}"              
    }
    End{
        Write-Output $end
    }
}