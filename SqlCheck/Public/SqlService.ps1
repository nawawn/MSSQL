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
        [System.IO.FileInfo]$CSVPath = "\\FileServer\Reports\CSV",
        [System.IO.FileInfo]$MasterList = '\\FileServer\reports\Scripts\MasterList.psd1'
    )
    Begin {
        $RunningSrv = @()
        $CsvFile    = "$CSVPath\$ComputerName.csv"        
    }
    Process {
        If (Test-Path -Path $CsvFile){
            $Csv = Import-Csv -Path $CsvFile            
            $RunningSrv = ($Csv | Where-Object{$_.ServiceState -eq "Running"} | Select-Object -ExpandProperty Name)            
        }
        Elseif (Test-Path -Path $MasterList){            
            $ServiceList = Import-PowerShellDataFile -Path $MasterList
            $RunningSrv = $($ServiceList.$ComputerName.Running.Name)            
        }
        Else{
            Write-Warning "Unable to obtain running services details from either CSV or PSD1 file!"
        }
        If ($RunningSrv){
            Write-Verbose "Starting services according to running state in CSV..."       
            $RunningSrv | Get-Service -ComputerName $ComputerName | Start-Service
        } 
        Else{
            Write-Warning "Please reboot the server, if the problem persists."
        }
    }
}