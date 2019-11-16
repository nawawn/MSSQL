Function Get-SQLServerVer {
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

Function Get-DbSession{
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [String]$ComputerName
    )
    Process{
        $Query  = 'SELECT DB_NAME(database_id) AS DatabaseName, COUNT(session_id) AS TotalConnections FROM sys.dm_exec_sessions GROUP BY DB_NAME(database_id)'
        If([Version](Get-SQLServerVer -ComputerName $ComputerName).version -lt '11.00'){
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
