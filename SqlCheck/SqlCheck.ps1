#Requires -Modules DbaTools

# This script requires DbaTools PowerShell Module
# Arguments for Preflight check
$Params = @{
    PreReportPath  = "\\FileServer\reports\PreFlightChecks"
    PostReportPath = "\\FileServer\reports\PostFlightChecks"
    CsvPath        = "\\FileServer\reports\CSV"
    MasterConfig     = "\\FileServer\reports\Scripts\MasterConfig.psd1"
}
Function Start-PreflightCheck{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName,Position = 0)]
        [String]$ComputerName,
        [Switch]$StopService,
        [Parameter(Mandatory)][System.IO.FileInfo]$ReportPath, 
        [Parameter(Mandatory)][System.IO.FileInfo]$CsvPath
    )
    DynamicParam{
        If ($StopService){
            $Attrib = New-Object System.Management.Automation.ParameterAttribute
            $Attrib.Mandatory = $false
            $Attrib.ParameterSetName = 'StopGroup'        
        
            $AttribCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $AttribCollection.Add($Attrib)

            $DynNoDC = New-Object System.Management.Automation.RuntimeDefinedParameter("NoDriveCheck",[Switch],$Attrib)
            $DynNoJC = New-Object System.Management.Automation.RuntimeDefinedParameter("NoJobCheck",[Switch],$Attrib)
            $DynNoBC = New-Object System.Management.Automation.RuntimeDefinedParameter("NoBackupCheck",[Switch],$Attrib)

            $ParamDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            $ParamDictionary.Add("NoDriveCheck", $DynNoDC)
            $ParamDictionary.Add("NoJobCheck", $DynNoJC)
            $ParamDictionary.Add("NoBackupCheck", $DynNoBC)
            return $ParamDictionary
        }
    }
    Begin{}
    Process{
        If (-Not(Test-Path -path $ReportPath)){
            Write-Warning "$ReportPath Path not found"
            [Environment]::Exit(2)
        }
        If (-Not(Test-Path -path $CsvPath)){
            Write-Warning "$CsvPath Path not found"
            [Environment]::Exit(2)
        }
        Write-Verbose "Function Call: Get-SqlServiceCsvReport"
        Get-SqlServiceCsvReport -ComputerName $ComputerName -OutputPath $CsvPath

        Write-Verbose "Function Call: Get-SQLServerHtmlReport"
        Get-SQLServerHtmlReport -ComputerName $ComputerName -OutputPath $ReportPath -Suffix 'Pre'
        If ($StopService){
            If(-Not($PSBoundParameters.ContainsKey('NoDriveCheck'))){
                Write-Verbose "Function Call: Test-DriveSpace"
                If (!(Test-DriveSpace -ComputerName $ComputerName -Drive "C:" -SizeGB 5)){                
                    Write-Warning "There is not enough space on C drive."            
                    [Environment]::Exit(3)
                }
            }        
            If(-Not($PSBoundParameters.ContainsKey('NoJobCheck'))){
                Write-Verbose "Function Call: Test-SQLJobActivity"
                If(Test-SQLJobActivity -ComputerName $ComputerName){
                    Write-Warning "SQL agent job is still running! Please check the report."                
                    [Environment]::Exit(4)
                }
            }        
            If(-Not($PSBoundParameters.ContainsKey('NoBackupCheck'))){
                Write-Verbose "Function Call: Get-SQLJobActivity"
                $BackupJob = Get-SQLJobActivity -ComputerName $ComputerName | Where-Object{($_.Name -like "*Backup*") -and ($_.LastRunOutcome -like 'Failed')}
                If($BackupJob){
                    Write-Warning "Failed Backup job(s) found! Please check the report."                
                    [Environment]::Exit(5)
                }
            }        
            Write-Verbose "Function Call: Stop-SqlServices"
            Stop-SQLServices -ComputerName $ComputerName
        }
    }    
}

Function Start-PostflightCheck{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName,Position = 0)]
        [String]$ComputerName,
        [Switch]$StartService,
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$ReportPath,
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$CSVPath,
        [System.IO.FileInfo]$MasterConfig
    )
    Process{
        Write-Verbose "Function Call: Get-SQLServices"
        $BeforeStart  = Get-SQLServices -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>Before SQL Services Restart</h4>' -PostContent '<br/>' | Out-String
        
        If ($StartService){
            Write-Verbose "Function Call: Start-SQLServices"
            Start-SQLServices -ComputerName $ComputerName
        }

        Write-Verbose "Function Call: Get-SQLServerHtmlReport"
        Get-SQLServerHtmlReport -ComputerName $ComputerName -OutputPath $ReportPath -HtmlFragment $BeforeStart -Suffix 'Post'
    }
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
        $TestDrive = Get-DriveSpace -ComputerName $ComputerName -Drive $Drive
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
        Write-Verbose "$Computername - Retrieving total connection session..."
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
            [void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO")
            [void][System.Reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")
            
            $SqlServer  = New-Object Microsoft.SqlServer.Management.Smo.Server($ComputerName)
            $SqlConfMgr = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $SqlServer.ComputerNamePhysicalNetBIOS            
        }    
        Else {         
            Write-Warning "Please install MS SQL Management Studio"   
            [Environment]::Exit(1)
        }

        Write-Verbose "$ComputerName - Stopping SQL Services..."
        $SqlConfMgr.Services | Where-Object{$_.ServiceState -eq 'Running'} | ForEach-Object{$_.stop()}    
        If ($Wait){
            $SrvName = $SqlConfMgr.Services | Where-Object{$_.ServiceState -eq 'Running'} | Select-Object -ExpandProperty Name
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
        [Parameter(Madatory)][System.IO.FileInfo]$CSVPath,        
        [Parameter(Madatory)][System.IO.FileInfo]$MasterConfig
    )
    Begin {
        $RunningSrv = @()
        $SrvToStart = @()
        $CsvFile    = "$CSVPath\$ComputerName.csv"        
    }
    Process {        
        If (Test-Path -Path $CsvFile){
            $Csv = Import-Csv -Path $CsvFile            
            $RunningSrv = ($Csv | Where-Object{$_.State -eq "Running"} | Select-Object -ExpandProperty ServiceName)            
        }        
        Elseif(Test-Path -Path $MasterConfig){            
            $ServiceList = Import-PowerShellDataFile -Path $MasterConfig
            $RunningSrv = $($ServiceList.$ComputerName.Running.Name)            
        }
        Else{
            Write-Warning "Unable to obtain running services details from either CSV or PSD1 file!"
        }
        If ($RunningSrv){
            Write-Verbose "Starting services according to the previous running state..."       
            #$RunningSrv | Get-Service -ComputerName $ComputerName | Start-Service
            Foreach($Service in $RunningSrv){
                If (-Not(Test-ServiceStatus -Name $Service -Status 'Running' -ComputerName $ComputerName)){
                    $SrvToStart += $Service
                }
            }
            #Start the required service first - MSSQLSERVER, then start the rest
            $SrvToStart | Get-Service -ComputerName $ComputerName -RequiredServices | Start-Service
            $SrvToStart | Get-Service -ComputerName $ComputerName | Where-Object{$_.Status -ne 'Running'} | Start-Service
        } 
        Else{
            Write-Verbose "Starting services startup mode set to Automatic..."
            # Errors from start-service are non-terminating ones. So, try{}catch{} won't work unless you specify '-ea stop'
            $SrvToStart = (Get-DbaService -ComputerName $ComputerName | Where-Object{$_.StartMode -eq 'Automatic'}).ServiceName
            $SrvToStart | Get-Service -ComputerName $ComputerName -RequiredServices | Start-Service
            $SrvToStart | Get-Service -ComputerName $ComputerName | Where-Object{$_.Status -ne 'Running'} | Start-Service
            
            Write-Verbose "Please reboot the server, if the problem persists."
        }
        
    }
}

Function Get-SQLServerHtmlReport{
    Param(
        [Parameter()][ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [String]$HtmlFragment,
        [String]$Suffix = 'Pre',
        [System.IO.FileInfo]$OutputPath
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
        #$SqlErr  = Get-DbErrorLog -ComputerName $ComputerName | ConvertTo-Html -Fragment -PreContent '<h4>SQL Error Log from today</h4>' -PostContent '<br/>' | Out-String
        
        If ($HtmlFragment){
            $Body = "$CInfo $HtmlFragment $SqlSer $DbState $DbConns $SqlVer $DBInfo $DBJob $SqlLog $SqlErr"
        }
        Else{
            $Body = "$CInfo $SqlSer $DbState $DbConns $SqlVer $DBInfo $DBJob $SqlLog $SqlErr"
        }

        Write-Verbose "Generating SQL Server HTML Report..."
        If (Test-Path $OutputPath){
            ConvertTo-Html -Head $Head -Body "$Body" -Title "SQL Server $Suffix-flight Check Report" | 
                Out-File "$OutputPath\$ComputerName-$Suffix.html"
        }
        Else {  
            $OutFile =  [Environment]::GetFolderPath("Desktop")
            ConvertTo-Html -Head $Head -Body "$Body" -Title "SQL Server $Suffix-flight Check Report" | 
                Out-File "$OutFile\$ComputerName-$Suffix.html" -Force
        }
    }
}

Function Get-SQLServiceCsvReport{
    Param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName,
        [System.IO.FileInfo]$OutputPath
    )
    Process{
        Write-Verbose "$ComputerName - Saving SQL services to CSV file..."
        Get-SQLServices -ComputerName $ComputerName | Export-Csv -Path "$OutputPath\$ComputerName.csv" -NoTypeInformation
    }    
}

Function Get-SqlServicePsd1{
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

Export-ModuleMember -Function Start-*,Stop-*,Get-*,Test-*