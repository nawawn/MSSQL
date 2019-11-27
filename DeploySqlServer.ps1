# Tested working without the mixed mode
Configuration DeployTestSql{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][ValidateNotNullorEmpty()]        
        [PSCredential]$SqlAdminCredential,
        [Parameter(Mandatory)][ValidateNotNullorEmpty()]
        [PSCredential]$SaCredential
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName SqlServerDsc
    Import-DscResource -ModuleName NetworkingDsc

    Node localhost{

        WindowsFeature InstallDotNet{
            Name   = 'Net-Framework-Features'
            Ensure = 'Present'    
        }          
    
        File DataDir{
            DestinationPath = 'C:\SQL\SQLData'
            Ensure = 'Present'
            Type   = 'Directory'
        }
        File LogsDir{
            DestinationPath = 'C:\SQL\SQLLogs'
            Ensure = 'Present'
            Type   = 'Directory'
    
        }
        File BackupDir{
            DestinationPath = 'C:\SQL\SQLBackups'
            Ensure = 'Present'
            Type   = 'Directory'
        }
        File TempDbaDir{
            DestinationPath = 'C:\SQL\TempDBA'
            Ensure = 'Present'
            Type   = 'Directory'
        }

        SqlSetup InstallSql{
            SourcePath          = 'D:\'        
            InstanceName        = 'MSSQLSERVER'        
            Features            = 'SQLENGINE'
            SQLCollation        = 'SQL_Latin1_General_CP1_CI_AS'
            InstallSharedDir    = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir         = 'C:\Program Files\Microsoft SQL Server'
            InstallSQLDataDir   = 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Data'        
            SQLUserDBDir        = 'C:\SQL\SQLData'
            SQLUserDBLogDir     = 'C:\SQL\SQLLogs'        
            SQLBackupDir        = 'C:\SQL\SQLBackups'
            #SecurityMode       = 'SQL'
            #SAPwd              = $SaPSCredential     
            #SQLSvcAccount      = PSCredential
            SQLSysAdminAccounts = @('Administrators', $SqlAdminCredential.UserName)
            UpdateEnabled       = 'False'
            ForceReboot         = $false
        
            DependsOn = '[WindowsFeature]InstallDotNet'
        }
        SqlDatabase NewDbaDatabase{
            Name         = 'DbaDatabase'
            ServerName   = 'localhost'
            InstanceName = 'MSSQLServer'
            DependsOn    = '[SqlSetup]InstallSql'        
        }

        Firewall SQLServer{
            Name        = 'SQLSERVER'
            DisplayName = 'SQL Server'
            Description = 'Allow inbound traffic to sql instance'            
            Profile     = ('Domain','Private')
            Direction   = 'Inbound'
            LocalPort   = '1433'          
            Protocol    = 'TCP'
            Ensure      = 'Present'
            Enabled     = 'True'        
        }       
        Firewall SQLAdmin{
            Name        = 'SQLAdmin'
            DisplayName = 'SQL Server DAC'
            Description = 'Allow inbound traffic to sql Dedicated Administrator Connection'            
            Profile     = ('Domain','Private')
            Direction   = 'Inbound'
            LocalPort   = '1434'          
            Protocol    = 'TCP'
            Ensure      = 'Present'
            Enabled     = 'True'        
        }
        Firewall SQLBrowser{
            Name        = 'SQLBrowser'
            DisplayName = 'SQL Browswer Service'
            Description = 'Allow inbound traffic to SQL Server Browser service connection'            
            Profile     = ('Domain','Private')
            Direction   = 'Inbound'
            LocalPort   = '1434'          
            Protocol    = 'UDP'
            Ensure      = 'Present'
            Enabled     = 'True'        
        }
        Firewall HTTPS{
            Name        = 'HTTPS'
            DisplayName = 'HTTPS endpoint'
            Description = 'Allow inbound traffic to instance with HTTPS endpoint through a URL'            
            Profile     = ('Domain','Private')
            Direction   = 'Inbound'
            LocalPort   = '443'          
            Protocol    = 'TCP'
            Ensure      = 'Present'
            Enabled     = 'True'        
        }
        Firewall HTTP{
            Name        = 'HTTP'
            DisplayName = 'HTTP endpoint'
            Description = 'Allow inbound traffic to instance with HTTP endpoint through a URL'            
            Profile     = ('Domain','Private')
            Direction   = 'Inbound'
            LocalPort   = '80'          
            Protocol    = 'TCP'
            Ensure      = 'Present'
            Enabled     = 'True'        
        }
         Firewall SQLDebugger{
            Name        = 'SQLDebugger'
            DisplayName = 'SQL Debugger RPC'
            Description = 'Allow inbound traffic to Transact-SQL debugger'            
            Profile     = ('Domain','Private')
            Direction   = 'Inbound'
            LocalPort   = '135'          
            Protocol    = 'TCP'
            Ensure      = 'Present'
            Enabled     = 'True'        
        }
        Firewall SQLAS{
            Name        = 'SQLAS'
            DisplayName = 'SQL Analysis Services'
            Description = 'Allow inbound traffic to SQL Analysis Services'            
            Profile     = ('Domain','Private')
            Direction   = 'Inbound'
            LocalPort   = '2383'          
            Protocol    = 'TCP'
            Ensure      = 'Present'
            Enabled     = 'True'        
        }
        Firewall SQLBrowserAS{
            Name        = 'SQLBrowserAS'
            DisplayName = 'SQL Browswer Service for Analysis Services'
            Description = 'Allow inbound traffic to SQL Server Browser service for Analysis Services'            
            Profile     = ('Domain','Private')
            Direction   = 'Inbound'
            LocalPort   = '2382'          
            Protocol    = 'UDP'
            Ensure      = 'Present'
            Enabled     = 'True'        
        }
    }
}

$Sqladmin = Get-Credential
$sa = Get-Credential
DeployTestSql -SqlAdminCredential $Sqladmin -SaCredential $sa

Start-DscConfiguration .\DeployTestSql -Wait -Force -Verbose